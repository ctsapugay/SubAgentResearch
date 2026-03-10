defmodule SkillToSandbox.Agent.Runner do
  @moduledoc """
  Drives an LLM in a bash-command loop inside a Docker sandbox container.

  Each iteration asks the LLM for a single bash command, executes it via
  `CLI.execute/1`, appends the output to the conversation context, and
  repeats until the LLM signals completion (`DONE`), impossibility (`STUCK`),
  or the step limit is reached.

  ## Context format

  The loop uses `"Command: X\\nOutput:\\n..."` — NOT `"$ X"` — to avoid
  teaching the LLM to echo a `$` prefix back, which would cause bash to
  fail with `$: command not found`.
  """

  require Logger

  alias SkillToSandbox.Analysis.LLMClient
  alias SkillToSandbox.Tools.CLI

  @default_max_steps 12
  @done_signal "DONE"
  @stuck_signal "STUCK"

  @default_system_prompt """
  You are an AI agent with bash access inside a Docker container.
  The workspace is at /workspace. Skill files are at /workspace/skill/.

  On each turn respond with ONLY a single raw bash command.
  Rules:
  - No markdown fences (no ``` wrapping)
  - No $ prefix (write: ls /workspace — NOT: $ ls /workspace)
  - No explanation, just the command

  Correct examples:
    node --version
    ls /workspace
    head -n 5 /workspace/tool_manifest.json

  When the task is fully complete and you have confirmed the result, respond with exactly: DONE
  If the task is impossible given the available tools and environment, respond with exactly: STUCK
  If your previous command produced an error, analyze the error and try a DIFFERENT approach — do not retry the exact same command.
  """

  @doc """
  Run the agent loop for `task` inside `container_id`.

  ## Options

    * `:max_steps` — maximum loop iterations (default: #{@default_max_steps})
    * `:system_prompt` — override the default system prompt string
    * `:preflight` — boolean; if `true` (default) runs a container sanity check first

  ## Returns

    * `{:ok, :done, steps}` — LLM signalled completion
    * `{:error, :stuck, steps}` — LLM signalled impossibility
    * `{:error, :step_limit, steps}` — loop exhausted without a terminal signal
    * `{:error, reason}` — hard error (bad config, container unreachable, etc.)
  """
  @spec run(String.t(), String.t(), keyword()) ::
          {:ok, :done, [map()]}
          | {:error, :stuck, [map()]}
          | {:error, :step_limit, [map()]}
          | {:error, term()}
  def run(task, container_id, opts \\ []) do
    max_steps = Keyword.get(opts, :max_steps, @default_max_steps)
    system_prompt = Keyword.get(opts, :system_prompt, @default_system_prompt)
    preflight = Keyword.get(opts, :preflight, true)

    Logger.info(
      "[Agent.Runner] Starting for container #{String.slice(container_id, 0, 12)}, max_steps=#{max_steps}"
    )

    with :ok <- maybe_preflight(container_id, preflight) do
      initial_context = "Task: #{task}\n\nBegin. What is your first command?"
      run_loop(initial_context, container_id, system_prompt, max_steps)
    end
  end

  @doc """
  Strip markdown code fences and leading shell-prompt prefixes from an LLM response.

  Applied in order:
  1. Trim surrounding whitespace
  2. Strip ` ```bash ... ``` `, ` ```sh ... ``` `, or ` ``` ... ``` ` fences
  3. Trim again
  4. Strip leading `$ ` or `$\\t` shell-prompt prefix
  5. Final trim

  Public so it can be called from IEx and tested independently.
  """
  @spec strip_command(String.t()) :: String.t()
  def strip_command(text) when is_binary(text) do
    text
    |> String.trim()
    |> strip_fences()
    |> String.trim()
    |> strip_shell_prefix()
    |> String.trim()
  end

  # -- Private --

  defp run_loop(initial_context, container_id, system_prompt, max_steps) do
    result =
      Enum.reduce_while(1..max_steps, {initial_context, []}, fn step_num,
                                                                 {context, acc_steps} ->
        case LLMClient.chat(system_prompt, context) do
          {:ok, raw_response} ->
            command = strip_command(raw_response)

            cond do
              command == @done_signal ->
                {:halt, {:ok, :done, acc_steps}}

              command == @stuck_signal ->
                {:halt, {:error, :stuck, acc_steps}}

              true ->
                started_at = System.monotonic_time(:millisecond)

                exec_result =
                  CLI.execute(%{
                    "command" => command <> " 2>&1 | tee /proc/1/fd/1",
                    "container_id" => container_id
                  })

                elapsed_ms = System.monotonic_time(:millisecond) - started_at

                output =
                  case exec_result do
                    {:ok, out} -> String.slice(out, 0, 1000)
                    {:error, err} -> "ERROR: #{inspect(err)}"
                  end

                step = %{
                  step: step_num,
                  command: command,
                  output: output,
                  elapsed_ms: elapsed_ms,
                  status: if(match?({:ok, _}, exec_result), do: :ok, else: :error)
                }

                # CRITICAL: use "Command: X" NOT "$ X" — the $ prefix teaches the LLM to echo it back
                next_context =
                  context <>
                    "\n\nCommand: #{command}\nOutput:\n#{output}\n\nNext command (or #{@done_signal}/#{@stuck_signal}):"

                {:cont, {next_context, acc_steps ++ [step]}}
            end

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, :done, steps} -> {:ok, :done, steps}
      {:error, :stuck, steps} -> {:error, :stuck, steps}
      {:error, reason} when not is_list(reason) -> {:error, reason}
      {_context, steps} -> {:error, :step_limit, steps}
    end
  end

  defp maybe_preflight(_container_id, false), do: :ok

  defp maybe_preflight(container_id, true) do
    case CLI.execute(%{"command" => "echo preflight_ok", "container_id" => container_id}) do
      {:ok, output} ->
        if output =~ "preflight_ok", do: :ok, else: :ok

      {:error, reason} ->
        {:error, "Container preflight failed: #{inspect(reason)}"}
    end
  end

  defp strip_fences(text) do
    case Regex.run(~r/```(?:bash|sh|shell)?\n?(.*?)```/s, text, capture: :all_but_first) do
      [command] -> String.trim(command)
      nil -> text
    end
  end

  defp strip_shell_prefix("$ " <> rest), do: rest
  defp strip_shell_prefix("$\t" <> rest), do: rest
  defp strip_shell_prefix(text), do: text
end
