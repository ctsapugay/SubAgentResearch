defmodule SkillToSandbox.Skills.Parser do
  @moduledoc """
  Parses SKILL.md content into a structured map.

  The parser operates in three stages:
  1. Extract YAML frontmatter (name, description, etc.)
  2. Keyword-based body analysis (tools, frameworks, dependencies)
  3. Assemble a unified parsed output map

  Returns `{:ok, map}` on success or `{:error, reason}` on failure.
  """

  # -- Tool keyword patterns --
  # Each entry: {regex_pattern, canonical_tool_name}
  @tool_patterns [
    {~r/web\s*search|search\s*the\s*web|web\s*browsing/i, "web_search"},
    {~r/file\s*writ(?:e|ing)|write\s*file|create\s*file|generate\s*code/i, "file_write"},
    {~r/file\s*read|read\s*file/i, "file_read"},
    {~r/\bbrowser\b|browsing|navigate/i, "browser"},
    {~r/\bterminal\b|command\s*line|\bCLI\b|\bshell\b|execute\s*command/i, "cli_execution"},
    {~r/code\s*execution|run\s*code|\bexecute\b/i, "code_execution"}
  ]

  # -- Framework/language keyword patterns --
  @framework_patterns [
    {~r/\bReact\b/, "React"},
    {~r/\bVue\b/, "Vue"},
    {~r/\bAngular\b/, "Angular"},
    {~r/\bSvelte\b/, "Svelte"},
    {~r/\bNext\.?js\b/i, "Next.js"},
    {~r/\bNuxt\b/i, "Nuxt"},
    {~r/\bNode(?:\.?js)?\b/, "Node.js"},
    {~r/\bnpm\b/, "npm"},
    {~r/\byarn\b/i, "yarn"},
    {~r/\bpnpm\b/, "pnpm"},
    {~r/\bbun\b/, "bun"},
    {~r/\bPython\b/, "Python"},
    {~r/\bpip\b/, "pip"},
    {~r/\bconda\b/, "conda"},
    {~r/\bTypeScript\b/, "TypeScript"},
    {~r/\bJavaScript\b|\bJS\b/, "JavaScript"},
    {~r/\bHTML\b/, "HTML"},
    {~r/\bCSS\b/, "CSS"},
    {~r/\bSCSS\b/, "SCSS"},
    {~r/\bSass\b/, "Sass"},
    {~r/\bTailwind\b/i, "Tailwind"},
    {~r/\bBootstrap\b/i, "Bootstrap"},
    {~r/\bMaterial\s*UI\b/i, "Material UI"},
    {~r/\bDjango\b/, "Django"},
    {~r/\bFlask\b/, "Flask"},
    {~r/\bFastAPI\b/, "FastAPI"},
    {~r/\bExpress\b/, "Express"}
  ]

  # -- Dependency patterns --
  # Matches phrases like "Motion library", "Framer Motion", or explicit
  # "library: X" / "package: X" references
  @dependency_patterns [
    {~r/\bMotion\s+library\b/i, "Motion"},
    {~r/\bFramer\s+Motion\b/i, "Framer Motion"},
    {~r/\bTailwind\s*CSS\b/i, "Tailwind CSS"},
    {~r/\bDaisyUI\b/i, "DaisyUI"},
    {~r/\bChakra\s*UI\b/i, "Chakra UI"},
    {~r/\bShadcn\b/i, "Shadcn"},
    {~r/\bAxios\b/, "Axios"},
    {~r/\bRedux\b/, "Redux"},
    {~r/\bZustand\b/, "Zustand"},
    {~r/\bJotai\b/, "Jotai"},
    {~r/\bVite\b/, "Vite"},
    {~r/\bWebpack\b/, "Webpack"},
    {~r/\bPostCSS\b/i, "PostCSS"},
    {~r/\bESLint\b/i, "ESLint"},
    {~r/\bPrettier\b/i, "Prettier"},
    {~r/\bJest\b/, "Jest"},
    {~r/\bVitest\b/, "Vitest"},
    {~r/\bPlaywright\b/, "Playwright"},
    {~r/\bCypress\b/, "Cypress"},
    {~r/\bStorybook\b/, "Storybook"},
    {~r/\bThree\.?js\b/i, "Three.js"},
    {~r/\bD3\.?js\b/i, "D3.js"},
    {~r/\bGSAP\b/, "GSAP"},
    {~r/\bLottie\b/, "Lottie"}
  ]

  @doc """
  Parses raw SKILL.md content into a structured map.

  Returns `{:ok, parsed_map}` on success, `{:error, reason}` on failure.

  ## Example

      {:ok, parsed} = Parser.parse(raw_content)
      parsed.name        # "frontend-design"
      parsed.sections    # ["Design Thinking", "Frontend Aesthetics Guidelines"]
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, atom() | String.t()}
  def parse(nil), do: {:error, :empty_content}
  def parse(""), do: {:error, :empty_content}

  def parse(content) when is_binary(content) do
    content = String.trim(content)

    if content == "" do
      {:error, :empty_content}
    else
      case extract_frontmatter(content) do
        {:ok, meta, body} ->
          parsed = assemble_output(meta, body, content)
          {:ok, parsed}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # -- Stage A: Frontmatter Extraction --

  defp extract_frontmatter(content) do
    case String.split(content, ~r/^---\s*$/m, parts: 3) do
      [before, yaml_str, body] when before == "" ->
        case YamlElixir.read_from_string(String.trim(yaml_str)) do
          {:ok, meta} when is_map(meta) ->
            {:ok, meta, body}

          {:ok, _} ->
            # YAML parsed but wasn't a map (e.g., just a scalar)
            {:ok, %{}, content}

          {:error, _} ->
            {:error, :invalid_frontmatter}
        end

      _ ->
        # No frontmatter found; treat entire content as body
        {:ok, %{}, content}
    end
  end

  # -- Stage B: Keyword-Based Body Analysis --

  defp extract_sections(body) do
    Regex.scan(~r/^\#{2,3}\s+(.+)$/m, body)
    |> Enum.map(fn [_, heading] -> String.trim(heading) end)
    |> Enum.uniq()
  end

  defp detect_tools(body) do
    @tool_patterns
    |> Enum.filter(fn {pattern, _name} -> Regex.match?(pattern, body) end)
    |> Enum.map(fn {_pattern, name} -> name end)
    |> Enum.uniq()
  end

  defp detect_frameworks(body) do
    @framework_patterns
    |> Enum.filter(fn {pattern, _name} -> Regex.match?(pattern, body) end)
    |> Enum.map(fn {_pattern, name} -> name end)
    |> Enum.uniq()
  end

  defp detect_dependencies(body) do
    # First, check known dependency patterns
    known =
      @dependency_patterns
      |> Enum.filter(fn {pattern, _name} -> Regex.match?(pattern, body) end)
      |> Enum.map(fn {_pattern, name} -> name end)

    # Also scan for "X library" or "X package" patterns not already caught
    library_mentions =
      Regex.scan(~r/\b([A-Z][a-z]+(?:\s[A-Z][a-z]+)*)\s+(?:library|package|framework)\b/, body)
      |> Enum.map(fn [_, name] -> String.trim(name) end)

    (known ++ library_mentions)
    |> Enum.uniq()
  end

  # -- Stage C: Assemble Output --

  defp assemble_output(meta, body, raw_content) do
    sections = extract_sections(body)
    mentioned_tools = detect_tools(body)
    mentioned_frameworks = detect_frameworks(body)
    mentioned_dependencies = detect_dependencies(body)

    name = meta["name"] || extract_first_heading(raw_content)
    description = meta["description"]

    %{
      "name" => name,
      "description" => description,
      "sections" => sections,
      "mentioned_tools" => mentioned_tools,
      "mentioned_frameworks" => mentioned_frameworks,
      "mentioned_dependencies" => mentioned_dependencies,
      "raw_guidelines" => String.trim(body),
      "frontmatter" => meta
    }
  end

  defp extract_first_heading(content) do
    case Regex.run(~r/^#\s+(.+)$/m, content) do
      [_, heading] -> String.trim(heading)
      _ -> nil
    end
  end
end
