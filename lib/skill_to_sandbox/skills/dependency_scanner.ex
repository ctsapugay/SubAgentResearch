defmodule SkillToSandbox.Skills.DependencyScanner do
  @moduledoc """
  Scans a file tree for dependency files and extracts package information.

  Supports:
  - `package.json` — extracts `dependencies` and `devDependencies` (merged into npm)
  - `requirements.txt` — parses pip-style lines (package==version, package>=version, etc.)

  Returns a map suitable for the Analyzer to merge with LLM output.
  """

  @doc """
  Scans a file tree for dependency files and returns structured dependency info.

  Returns a map with keys:
  - `:npm` — map of package_name => version (from package.json)
  - `:pip` — map of package_name => version (from requirements.txt)
  - `:package_json_path` — path to package.json if found, nil otherwise
  - `:requirements_path` — path to requirements.txt if found, nil otherwise

  ## Examples

      file_tree = %{
        "package.json" => "{\"dependencies\": {\"react\": \"^18.0.0\"}}",
        "references/commands.md" => "# Commands"
      }
      DependencyScanner.scan(file_tree)
      # => %{npm: %{"react" => "^18.0.0"}, pip: %{}, package_json_path: "package.json", requirements_path: nil}

      file_tree = %{
        "SKILL.md" => "...",
        "requirements.txt" => "flask==3.0.0\\nrequests>=2.28.0"
      }
      DependencyScanner.scan(file_tree)
      # => %{npm: %{}, pip: %{"flask" => "3.0.0", "requests" => ">=2.28.0"}, ...}
  """
  @spec scan(file_tree :: %{String.t() => String.t()}) :: %{optional(atom()) => any()}
  def scan(file_tree) when is_map(file_tree) do
    npm = scan_npm(file_tree)
    pip = scan_pip(file_tree)
    package_json_path = find_file(file_tree, "package.json")
    requirements_path = find_file(file_tree, "requirements.txt")

    %{
      npm: npm,
      pip: pip,
      package_json_path: package_json_path,
      requirements_path: requirements_path
    }
  end

  def scan(_), do: %{npm: %{}, pip: %{}, package_json_path: nil, requirements_path: nil}

  defp find_file(file_tree, filename) do
    file_tree
    |> Map.keys()
    |> Enum.find(fn path ->
      path == filename or String.ends_with?(path, "/#{filename}")
    end)
  end

  defp scan_npm(file_tree) do
    case find_and_parse_package_json(file_tree) do
      {:ok, deps} -> deps
      _ -> %{}
    end
  end

  defp find_and_parse_package_json(file_tree) do
    content =
      file_tree
      |> Map.keys()
      |> Enum.find_value(fn path ->
        if Path.basename(path) == "package.json" do
          Map.get(file_tree, path)
        end
      end)

    if content do
      case Jason.decode(content) do
        {:ok, parsed} when is_map(parsed) ->
          deps = Map.get(parsed, "dependencies", %{}) |> extract_npm_versions()
          dev_deps = Map.get(parsed, "devDependencies", %{}) |> extract_npm_versions()
          {:ok, Map.merge(deps, dev_deps)}

        {:ok, _} ->
          {:ok, %{}}

        {:error, _} ->
          {:error, :invalid_json}
      end
    else
      {:error, :not_found}
    end
  end

  defp extract_npm_versions(deps) when is_map(deps) do
    deps
    |> Enum.map(fn {name, version} ->
      {name, to_string(version)}
    end)
    |> Map.new()
  end

  defp extract_npm_versions(_), do: %{}

  defp scan_pip(file_tree) do
    content =
      file_tree
      |> Map.keys()
      |> Enum.find_value(fn path ->
        if Path.basename(path) == "requirements.txt" do
          Map.get(file_tree, path)
        end
      end)

    if content do
      parse_requirements_txt(content)
    else
      %{}
    end
  end

  defp parse_requirements_txt(content) do
    content
    |> String.split(~r/\r?\n/, trim: false)
    |> Enum.reject(&skip_requirements_line?/1)
    |> Enum.map(&parse_requirements_line/1)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp strip_leading_equals(version) do
    String.trim_leading(version, "==")
  end

  defp skip_requirements_line?(line) do
    line = String.trim(line)
    line == "" or String.starts_with?(line, "#") or String.starts_with?(line, "-")
  end

  defp parse_requirements_line(line) do
    line = String.trim(line)

    # Match: package==version, package>=version, package<=version, package~=version, package
    case Regex.run(~r/^([a-zA-Z0-9_-]+)\s*([=<>~!]+.*)?$/, line) do
      [_, name, version] when is_binary(version) ->
        version = String.trim(version) |> strip_leading_equals()
        {name, version}

      [_, name] ->
        {name, nil}

      _ ->
        nil
    end
  end
end
