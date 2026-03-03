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
  alias SkillToSandbox.Analysis.{CodeDependencyExtractor, DependencyRelevantFiles, LLMClient}
  alias SkillToSandbox.Skills.{CanonicalDeps, DependencyScanner, PackageValidator, Parser, Skill}

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
  9. If the skill's frontmatter includes "allowed-tools" with Bash(npx <package>:*) or Bash(<package>:*),
     you MUST add that package to runtime_deps.packages (npm) so it is installed in the container.
  10. VERSION EXTRACTION: When the skill or its template files contain CDN URLs with versions
      (e.g. cdnjs.cloudflare.com/ajax/libs/p5.js/1.7.0/p5.min.js), use that EXACT version in
      runtime_deps. Do not guess or use a different version.
  11. EVIDENCE-BASED PACKAGES: Only add a package to runtime_deps if there is evidence:
      - In manifests (package.json, requirements.txt, etc.)
      - In import/require statements in code files
      - In <script src="..."> CDN URLs in HTML
      The word "express" can mean "to express/convey" (verb) – do NOT add Express.js unless
      you see require('express'), import express, or explicit server/API usage.

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
    scanner_result = DependencyScanner.scan(skill.file_tree || %{})
    extracted = CodeDependencyExtractor.extract_all(skill.file_tree || %{})
    user_prompt = build_user_prompt(skill, scanner_result, extracted)

    Logger.info("[Analyzer] Starting analysis for skill ##{skill.id}: #{skill.name}")

    with {:ok, raw_response} <- LLMClient.chat(@system_prompt, user_prompt),
         {:ok, spec_map} <- extract_json(raw_response),
         {:ok, validated} <- validate_spec(spec_map),
         merged_scanner <- merge_scanner_deps(validated, scanner_result),
         merged <- merge_extracted_deps(merged_scanner, extracted),
         with_allowed <- ensure_allowed_tools(merged, skill.parsed_data || %{}),
         validated_packages <- maybe_validate_packages(with_allowed, scanner_result) do
      Logger.info("[Analyzer] Analysis successful for skill ##{skill.id}")

      Analysis.create_spec(
        Map.merge(validated_packages, %{
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

  @doc false
  def user_prompt_for_skill(%Skill{} = skill) do
    scanner_result = DependencyScanner.scan(skill.file_tree || %{})
    extracted = CodeDependencyExtractor.extract_all(skill.file_tree || %{})
    build_user_prompt(skill, scanner_result, extracted)
  end

  # -- Prompt construction --

  defp build_user_prompt(%Skill{} = skill, scanner_result, extracted) do
    parsed = skill.parsed_data || %{}

    tools = format_list(parsed["mentioned_tools"])
    frameworks = format_list(parsed["mentioned_frameworks"])
    deps = format_list(parsed["mentioned_dependencies"])
    name = skill.name || "Unknown"
    description = skill.description || parsed["description"] || "No description"

    scanner_section = format_scanner_section(scanner_result)
    extracted_section = format_extracted_section(extracted)
    directory_section = format_directory_section(skill)
    dependency_instruction = format_dependency_instruction(scanner_result)
    canonical_section = format_canonical_deps_section(parsed, scanner_result)
    allowed_tools_section = format_allowed_tools_section(parsed)

    """
    Here is the skill definition:

    Name: #{name}
    Description: #{description}
    Detected in documentation text (keyword matching – verify against actual code before adding):
    Tools: #{tools}
    Frameworks: #{frameworks}
    Dependencies: #{deps}
    Only add a package to runtime_deps if you also see evidence in code (import, require, script src, or manifest).
    #{scanner_section}#{extracted_section}#{directory_section}#{dependency_instruction}#{canonical_section}#{allowed_tools_section}

    Full skill content:
    ---
    #{skill.raw_content}
    ---
    #{additional_file_content(skill)}

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
      ],
      "post_install_commands": []
    }
    }
    """
  end

  defp format_list(nil), do: "(none detected)"
  defp format_list([]), do: "(none detected)"
  defp format_list(list) when is_list(list), do: Enum.join(list, ", ")
  defp format_list(_), do: "(none detected)"

  defp format_scanner_section(scanner) do
    npm = Map.get(scanner, :npm, %{})
    pip = Map.get(scanner, :pip, %{})
    pkg_path = Map.get(scanner, :package_json_path)
    req_path = Map.get(scanner, :requirements_path)
    pyproject_path = Map.get(scanner, :pyproject_path)

    has_npm = is_map(npm) and map_size(npm) > 0
    has_pip = is_map(pip) and map_size(pip) > 0

    if pkg_path || req_path || pyproject_path do
      lines = []

      lines =
        if pkg_path && has_npm do
          pkgs = Enum.map_join(npm, ", ", fn {k, v} -> "#{k}: #{v}" end)
          lines ++ ["Scanned package.json (#{pkg_path}): #{pkgs}"]
        else
          lines
        end

      lines =
        if (req_path || pyproject_path) && has_pip do
          pkgs = Enum.map_join(pip, ", ", fn {k, v} -> "#{k}#{if v, do: " #{v}", else: ""}" end)

          sources =
            [
              req_path && "requirements.txt (#{req_path})",
              pyproject_path && "pyproject.toml (#{pyproject_path})"
            ]
            |> Enum.reject(&is_nil/1)
            |> Enum.join(", ")

          lines ++ ["Scanned #{sources}: #{pkgs}"]
        else
          lines
        end

      if lines != [] do
        "\nScanned dependencies from skill file tree:\n" <> Enum.join(lines, "\n") <> "\n"
      else
        ""
      end
    else
      ""
    end
  end

  defp format_extracted_section(%{npm_packages: npm, pip_packages: pip}) do
    has_npm = is_map(npm) and map_size(npm) > 0
    has_pip = is_map(pip) and map_size(pip) > 0

    if has_npm or has_pip do
      lines = []

      lines =
        if has_npm do
          pkgs =
            Enum.map_join(npm, ", ", fn {k, v} ->
              if v, do: "#{k}: #{v}", else: "#{k}"
            end)

          lines ++ ["npm: #{pkgs}"]
        else
          lines
        end

      lines =
        if has_pip do
          pkgs =
            Enum.map_join(pip, ", ", fn {k, v} ->
              if v, do: "#{k}: #{v}", else: "#{k}"
            end)

          lines ++ ["pip: #{pkgs}"]
        else
          lines
        end

      "\nExtracted from code (CDN URLs and imports):\n" <>
        Enum.join(lines, "\n") <>
        "\nUse these exact packages and versions. You may add more if you see additional evidence.\n"
    else
      ""
    end
  end

  defp format_extracted_section(_), do: ""

  defp format_directory_section(%Skill{source_type: "directory", file_tree: file_tree})
       when is_map(file_tree) and map_size(file_tree) > 0 do
    file_list = Map.keys(file_tree) |> Enum.sort() |> Enum.join(", ")

    "\nThis skill has multiple files: #{file_list}\n" <>
      "The skill directory will be mounted at SKILL_PATH (/workspace/skill) in the container. " <>
      "Templates and references are available for the agent to use.\n"
  end

  defp format_directory_section(_), do: ""

  defp format_dependency_instruction(scanner) do
    pkg_path = Map.get(scanner, :package_json_path)
    req_path = Map.get(scanner, :requirements_path)
    pyproject_path = Map.get(scanner, :pyproject_path)

    has_manifest =
      (is_binary(pkg_path) and pkg_path != "") or
        (is_binary(req_path) and req_path != "") or
        (is_binary(pyproject_path) and pyproject_path != "")

    if has_manifest do
      "\nIMPORTANT: The skill includes package.json, requirements.txt, or pyproject.toml in its file tree. " <>
        "Use EXACTLY those dependencies in runtime_deps. Do NOT add or remove packages from the manifest. " <>
        "You may add system packages, tool configs, and post_install_commands (e.g. 'npx playwright install chromium') as needed.\n"
    else
      "\nIMPORTANT: No package.json or requirements.txt found. Only include packages you are CERTAIN exist on npm/PyPI. " <>
        "Use exact canonical names (e.g. framer-motion, tailwindcss). When unsure, OMIT the package.\n"
    end
  end

  defp format_canonical_deps_section(parsed, scanner) when is_map(parsed) do
    has_manifest =
      (Map.get(scanner, :package_json_path) || Map.get(scanner, :requirements_path) ||
         Map.get(scanner, :pyproject_path)) != nil

    if has_manifest do
      ""
    else
      mentioned = parsed["mentioned_dependencies"] || []
      canonical_npm = CanonicalDeps.to_canonical_packages(mentioned, "npm")
      canonical_pip = CanonicalDeps.to_canonical_packages(mentioned, "pip")

      names =
        (Map.keys(canonical_npm) ++ Map.keys(canonical_pip))
        |> Enum.uniq()
        |> Enum.join(", ")

      if names != "" do
        "\nSuggested canonical packages from skill text (use these exact names if including): #{names}\n"
      else
        ""
      end
    end
  end

  defp format_canonical_deps_section(_, _), do: ""

  defp format_allowed_tools_section(parsed) when is_map(parsed) do
    case get_in(parsed, ["frontmatter", "allowed-tools"]) do
      nil ->
        ""

      "" ->
        ""

      val when is_binary(val) and byte_size(val) > 0 ->
        "\nIMPORTANT: The skill's frontmatter specifies allowed-tools: #{val}\n" <>
          "These are CLI tools the skill requires. Extract any npm package names " <>
          "(e.g. 'agent-browser' from 'Bash(npx agent-browser:*)') and ADD them to runtime_deps.packages. " <>
          "They must be installed for the skill to work.\n"

      _ ->
        ""
    end
  end

  defp format_allowed_tools_section(_), do: ""

  defp additional_file_content(%Skill{source_type: "directory", file_tree: file_tree})
       when is_map(file_tree) and map_size(file_tree) > 0 do
    selected = DependencyRelevantFiles.select_files_for_llm(file_tree, 70_000)

    if selected == [] do
      ""
    else
      sections =
        Enum.map(selected, fn {path, content} ->
          "\n---\nFile: #{path}\n---\n#{content}"
        end)

      "\nAdditional files (templates, code, manifests):\n" <> Enum.join(sections, "\n")
    end
  end

  defp additional_file_content(_), do: ""

  # Merge Scanner's dependencies with LLM output. Scanner wins on conflicts.
  # Exposed for testing.
  @doc false
  def merge_scanner_deps(validated, %{
        npm: npm,
        pip: pip,
        package_json_path: pkg_path,
        requirements_path: req_path,
        pyproject_path: pyproject_path
      }) do
    runtime_deps = validated.runtime_deps || %{}
    manager = runtime_deps["manager"] || "npm"
    llm_packages = runtime_deps["packages"] || %{}

    has_npm = is_binary(pkg_path) and pkg_path != "" and is_map(npm) and map_size(npm) > 0

    has_pip =
      ((is_binary(req_path) and req_path != "") or
         (is_binary(pyproject_path) and pyproject_path != "")) and
        is_map(pip) and map_size(pip) > 0

    {merged_manager, merged_packages} =
      cond do
        has_npm and has_pip ->
          # Both found: prefer npm (Node-first for most skills)
          merged = Map.merge(llm_packages, npm)
          {"npm", merged}

        has_npm ->
          merged = Map.merge(llm_packages, npm)
          {"npm", merged}

        has_pip ->
          merged = Map.merge(llm_packages, pip)
          {"pip", merged}

        true ->
          {manager, llm_packages}
      end

    %{validated | runtime_deps: %{"manager" => merged_manager, "packages" => merged_packages}}
  end

  def merge_scanner_deps(validated, %{package_json_path: _, requirements_path: _} = scanner) do
    merge_scanner_deps(validated, Map.put_new(scanner, :pyproject_path, nil))
  end

  # Merges code-extracted deps into the spec. Extracted packages with versions override LLM;
  # extracted packages are always included (add if LLM omitted them).
  @doc false
  def merge_extracted_deps(merged, extracted)

  def merge_extracted_deps(merged, %{npm_packages: _, pip_packages: _} = extracted) do
    runtime_deps = merged.runtime_deps || merged[:runtime_deps] || %{}
    manager = runtime_deps["manager"] || "npm"
    packages = runtime_deps["packages"] || %{}

    extracted_map =
      case manager do
        "npm" -> Map.get(extracted, :npm_packages, %{})
        "pip" -> Map.get(extracted, :pip_packages, %{})
        _ -> %{}
      end

    merged_packages =
      Enum.reduce(extracted_map, packages, fn {pkg, version}, acc ->
        cond do
          not Map.has_key?(acc, pkg) ->
            Map.put(acc, pkg, version || "latest")

          version != nil and version != "" ->
            Map.put(acc, pkg, version)

          true ->
            acc
        end
      end)

    runtime_deps = Map.put(runtime_deps, "packages", merged_packages)
    %{merged | runtime_deps: runtime_deps}
  end

  def merge_extracted_deps(merged, _), do: merged

  defp ensure_allowed_tools(merged, parsed) do
    meta = parsed["frontmatter"] || parsed
    allowed = Parser.extract_allowed_tools_deps(meta)

    if allowed == [] do
      merged
    else
      runtime_deps = merged.runtime_deps || %{}
      manager = runtime_deps["manager"] || "npm"
      packages = runtime_deps["packages"] || %{}

      # Only add to npm; allowed-tools are npx packages
      new_packages =
        if manager == "npm" do
          Enum.reduce(allowed, packages, fn pkg, acc ->
            Map.put_new(acc, pkg, "latest")
          end)
        else
          # If manager is pip, we still need allowed-tools as npm - that would require dual manager.
          # For now, when manager is pip, allow-tools npm pkgs are added to packages anyway
          # (DockerfileBuilder would need to handle that). Plan said to add them. We'll add to packages.
          Enum.reduce(allowed, packages, fn pkg, acc ->
            Map.put_new(acc, pkg, "latest")
          end)
        end

      %{merged | runtime_deps: Map.put(runtime_deps, "packages", new_packages)}
    end
  end

  defp maybe_validate_packages(merged, scanner_result) do
    npm = Map.get(scanner_result, :npm, %{})
    pip = Map.get(scanner_result, :pip, %{})
    has_manifest_deps = (is_map(npm) and map_size(npm) > 0) or (is_map(pip) and map_size(pip) > 0)

    # When manifests provided deps, trust them (skip validation). When LLM-only, validate.
    if has_manifest_deps do
      merged
    else
      runtime_deps = merged.runtime_deps || %{}
      manager = runtime_deps["manager"] || "npm"
      packages = runtime_deps["packages"] || %{}

      case PackageValidator.validate_packages(manager, packages) do
        {:ok, valid_packages} ->
          new_runtime = Map.put(runtime_deps, "packages", valid_packages)
          %{merged | runtime_deps: new_runtime}

        {:ok, valid_packages, removed} ->
          Logger.info("[Analyzer] Stripped invalid packages: #{inspect(removed)}")
          new_runtime = Map.put(runtime_deps, "packages", valid_packages)
          %{merged | runtime_deps: new_runtime}
      end
    end
  end

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
    base = %{
      base_image: spec_map["base_image"],
      system_packages: spec_map["system_packages"],
      runtime_deps: spec_map["runtime_deps"],
      tool_configs: spec_map["tool_configs"],
      eval_goals: spec_map["eval_goals"]
    }

    base =
      if is_list(spec_map["post_install_commands"]) do
        Map.put(base, :post_install_commands, spec_map["post_install_commands"])
      else
        base
      end

    base =
      if is_binary(spec_map["skill_mount_path"]) and spec_map["skill_mount_path"] != "" do
        Map.put(base, :skill_mount_path, spec_map["skill_mount_path"])
      else
        base
      end

    base
  end
end
