defmodule SkillToSandbox.Analysis.Analyzer do
  @moduledoc """
  Analyzes a parsed skill definition using an LLM to produce a structured
  sandbox specification (SandboxSpec).

  The analyzer:
  1. Constructs a detailed prompt from the skill's parsed data + raw content
  2. Sends it to the LLM via `LLMClient`
  3. Extracts and validates the JSON response
  4. Creates a `SandboxSpec` record in the database with status "draft"
  """

  require Logger

  alias SkillToSandbox.Analysis
  alias SkillToSandbox.Analysis.LLMClient
  alias SkillToSandbox.Skills.Skill

  @system_prompt """
  You are an expert DevOps and software environment engineer specializing in
  containerized development environments. Given a skill/subagent definition for
  an AI coding assistant, you must produce a precise sandbox specification as JSON.

  The sandbox must contain EVERYTHING needed for an AI agent to execute this skill
  inside a Docker container, including:
  - The correct base Docker image
  - All OS-level packages (installed via apt-get)
  - All language-specific dependencies (installed via npm, pip, etc.)
  - Tool configurations for a CLI execution tool and a web search tool
  - 8-12 diverse evaluation goals that exercise the skill at varying difficulty levels

  IMPORTANT RULES:
  1. Choose the SMALLEST appropriate base image (prefer -slim variants)
  2. Only include packages that are actually needed for the skill
  3. Evaluation goals should be concrete, actionable tasks (not vague descriptions)
  4. Evaluation goals should span easy/medium/hard difficulty
  5. Always include git and curl in system_packages (universally useful)
  6. For web/frontend skills, include a browser or headless browser if the skill mentions browser usage
  7. CRITICAL: Only include packages that ACTUALLY EXIST on the package registry (npm, PyPI).
     Use the EXACT canonical package name as published. Common mistakes to avoid:
     - Use "motion" or "framer-motion", NOT "use-motion" or "react-motion-library"
     - Use "tailwindcss", NOT "tailwind"
     - Use "@types/react", NOT "react-types"
     - When unsure about an exact package name, OMIT it rather than guess
  8. For version specifiers, use realistic ranges (e.g. "^18.0.0" for React, "^3.0.0" for Tailwind)

  You MUST respond with ONLY a valid JSON object, no markdown fences, no explanation.
  """

  @required_keys ~w(base_image system_packages runtime_deps tool_configs eval_goals)

  @doc """
  Analyze a skill and produce a sandbox specification.

  Takes a `%Skill{}` struct (with `parsed_data` and `raw_content` populated),
  calls the LLM, validates the response, and creates a `SandboxSpec` record.

  Returns `{:ok, %SandboxSpec{}}` on success or `{:error, reason}` on failure.
  """
  def analyze(%Skill{} = skill) do
    user_prompt = build_user_prompt(skill)

    Logger.info("[Analyzer] Starting analysis for skill ##{skill.id}: #{skill.name}")

    with {:ok, raw_response} <- LLMClient.chat(@system_prompt, user_prompt),
         {:ok, spec_map} <- extract_json(raw_response),
         {:ok, validated} <- validate_spec(spec_map) do
      Logger.info("[Analyzer] Analysis successful for skill ##{skill.id}")

      Analysis.create_spec(
        Map.merge(validated, %{
          skill_id: skill.id,
          status: "draft"
        })
      )
    else
      {:error, reason} ->
        Logger.error("[Analyzer] Analysis failed for skill ##{skill.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Extract and parse JSON from a raw LLM response string.

  Handles responses that may be wrapped in markdown code fences.
  Returns `{:ok, map}` or `{:error, reason}`.
  """
  def extract_json(raw_text) when is_binary(raw_text) do
    cleaned =
      raw_text
      |> String.trim()
      |> strip_markdown_fences()
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, map} when is_map(map) ->
        {:ok, map}

      {:ok, _other} ->
        {:error, "LLM response was valid JSON but not a JSON object"}

      {:error, %Jason.DecodeError{} = err} ->
        Logger.warning("[Analyzer] JSON parse failed: #{Exception.message(err)}")
        Logger.debug("[Analyzer] Raw response: #{String.slice(raw_text, 0, 500)}")
        {:error, "Failed to parse LLM response as JSON: #{Exception.message(err)}"}
    end
  end

  def extract_json(_), do: {:error, "Expected a string response from LLM"}

  @doc """
  Validate that a decoded spec map has all required fields with correct types.

  Returns `{:ok, normalized_map}` or `{:error, reason}`.
  """
  def validate_spec(spec_map) when is_map(spec_map) do
    with :ok <- check_required_keys(spec_map),
         :ok <- check_base_image(spec_map),
         :ok <- check_system_packages(spec_map),
         :ok <- check_runtime_deps(spec_map),
         :ok <- check_tool_configs(spec_map),
         :ok <- check_eval_goals(spec_map) do
      {:ok, normalize_spec(spec_map)}
    end
  end

  def validate_spec(_), do: {:error, "Spec must be a map"}

  # -- Prompt construction --

  defp build_user_prompt(%Skill{} = skill) do
    parsed = skill.parsed_data || %{}

    tools = format_list(parsed["mentioned_tools"])
    frameworks = format_list(parsed["mentioned_frameworks"])
    deps = format_list(parsed["mentioned_dependencies"])
    name = skill.name || "Unknown"
    description = skill.description || parsed["description"] || "No description"

    """
    Here is the skill definition:

    Name: #{name}
    Description: #{description}
    Detected tools: #{tools}
    Detected frameworks: #{frameworks}
    Detected dependencies: #{deps}

    Full skill content:
    ---
    #{skill.raw_content}
    ---

    Produce a JSON object matching this exact structure:
    {
      "base_image": "node:20-slim",
      "system_packages": ["git", "curl", "..."],
      "runtime_deps": {
        "manager": "npm",
        "packages": {"react": "^18.0.0", "...": "..."}
      },
      "tool_configs": {
        "cli": {
          "shell": "/bin/bash",
          "working_dir": "/workspace",
          "path_additions": [],
          "timeout_seconds": 30
        },
        "web_search": {
          "enabled": true,
          "description": "Search the web for information relevant to the task"
        }
      },
      "eval_goals": [
        "Easy: ...",
        "Easy: ...",
        "Medium: ...",
        "Medium: ...",
        "Medium: ...",
        "Hard: ...",
        "Hard: ...",
        "Hard: ..."
      ]
    }
    """
  end

  defp format_list(nil), do: "(none detected)"
  defp format_list([]), do: "(none detected)"
  defp format_list(list) when is_list(list), do: Enum.join(list, ", ")
  defp format_list(_), do: "(none detected)"

  # -- Markdown fence stripping --

  defp strip_markdown_fences(text) do
    # Remove opening ```json or ``` and closing ```
    text
    |> String.replace(~r/\A```(?:json)?\s*\n?/i, "")
    |> String.replace(~r/\n?```\s*\z/, "")
  end

  # -- Validation helpers --

  defp check_required_keys(spec_map) do
    missing = Enum.reject(@required_keys, &Map.has_key?(spec_map, &1))

    if missing == [] do
      :ok
    else
      {:error, "Missing required fields: #{Enum.join(missing, ", ")}"}
    end
  end

  defp check_base_image(%{"base_image" => img}) when is_binary(img) and img != "", do: :ok
  defp check_base_image(_), do: {:error, "base_image must be a non-empty string"}

  defp check_system_packages(%{"system_packages" => pkgs}) when is_list(pkgs) do
    if Enum.all?(pkgs, &is_binary/1) do
      :ok
    else
      {:error, "system_packages must be a list of strings"}
    end
  end

  defp check_system_packages(_), do: {:error, "system_packages must be a list of strings"}

  defp check_runtime_deps(%{"runtime_deps" => deps}) when is_map(deps) do
    cond do
      not is_binary(deps["manager"]) ->
        {:error, "runtime_deps.manager must be a string (e.g., \"npm\", \"pip\")"}

      not is_map(deps["packages"]) ->
        {:error, "runtime_deps.packages must be a map of package_name => version"}

      true ->
        :ok
    end
  end

  defp check_runtime_deps(_), do: {:error, "runtime_deps must be a map with manager and packages"}

  defp check_tool_configs(%{"tool_configs" => configs}) when is_map(configs) do
    cond do
      not is_map(configs["cli"]) ->
        {:error, "tool_configs.cli must be a map"}

      not is_map(configs["web_search"]) ->
        {:error, "tool_configs.web_search must be a map"}

      true ->
        :ok
    end
  end

  defp check_tool_configs(_), do: {:error, "tool_configs must be a map with cli and web_search"}

  defp check_eval_goals(%{"eval_goals" => goals}) when is_list(goals) do
    cond do
      length(goals) < 5 ->
        {:error, "eval_goals must contain at least 5 items, got #{length(goals)}"}

      not Enum.all?(goals, &is_binary/1) ->
        {:error, "eval_goals must be a list of strings"}

      true ->
        :ok
    end
  end

  defp check_eval_goals(_), do: {:error, "eval_goals must be a list of at least 5 strings"}

  # -- Normalize spec map into schema-compatible attrs --

  defp normalize_spec(spec_map) do
    %{
      base_image: spec_map["base_image"],
      system_packages: spec_map["system_packages"],
      runtime_deps: spec_map["runtime_deps"],
      tool_configs: spec_map["tool_configs"],
      eval_goals: spec_map["eval_goals"]
    }
  end
end
