defmodule SkillToSandbox.Agent.PromptBuilder do
  @moduledoc """
  Builds skill-specific agent system prompts.

  Takes the base agent instructions and appends the skill's `allowed-tools`
  invocation style so the LLM knows the exact command prefix to use for each
  tool (e.g. "npx agent-browser" rather than bare "agent-browser").
  """

  @base_instructions """
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
  Build a system prompt for a skill's agent loop.

  Accepts `parsed_data` — the map stored in `skill.parsed_data` after parsing.
  Extracts `allowed-tools` from `parsed_data["frontmatter"]` and appends
  explicit invocation instructions to the base prompt.

  ## Examples

      iex> PromptBuilder.build(%{"frontmatter" => %{"allowed-tools" => "Bash(npx agent-browser:*)"}})
      # Returns base instructions + "This skill's tools:\\n  - agent-browser → invoke as: npx agent-browser <subcommand>\\n"

      iex> PromptBuilder.build(%{})
      # Returns base instructions only (no allowed-tools found)
  """
  @spec build(map()) :: String.t()
  def build(parsed_data) when is_map(parsed_data) do
    case allowed_tools_section(parsed_data) do
      "" -> @base_instructions
      section -> @base_instructions <> "\n" <> section
    end
  end

  def build(_), do: @base_instructions

  # -- Private --

  defp allowed_tools_section(parsed_data) do
    frontmatter = Map.get(parsed_data, "frontmatter") || %{}
    raw = Map.get(frontmatter, "allowed-tools") || ""
    tools = parse_invocations(raw)

    if tools == [] do
      ""
    else
      lines =
        Enum.map(tools, fn {pkg, invocation} ->
          "  - #{pkg} → invoke as: #{invocation} <subcommand>"
        end)

      "This skill's tools (use these exact invocation styles):\n" <>
        Enum.join(lines, "\n") <> "\n"
    end
  end

  # Returns [{package_name, full_invocation_string}] sorted by package name.
  # Prefers "npx pkg" over bare "pkg" when both appear.
  defp parse_invocations(raw) when is_binary(raw) do
    npx =
      Regex.scan(~r/Bash\(npx\s+([a-zA-Z0-9@\/\-]+)[^)]*\)/i, raw)
      |> Enum.map(fn [_, pkg] -> {pkg, "npx #{pkg}"} end)
      |> Map.new()

    bare =
      Regex.scan(~r/Bash\(([a-zA-Z0-9@\/\-][a-zA-Z0-9@\/\-]*)[^)]*\)/i, raw)
      |> Enum.map(fn [_, pkg] -> {pkg, pkg} end)
      |> Enum.reject(fn {pkg, _} -> Map.has_key?(npx, pkg) end)
      |> Map.new()

    Map.merge(bare, npx)
    |> Enum.sort_by(fn {pkg, _} -> pkg end)
  end

  defp parse_invocations(_), do: []
end
