defmodule SkillToSandbox.Skills.DependencyScanner do
  @moduledoc """
  Scans a file tree for dependency files and extracts package information.

  Supports:
  - `package.json` — extracts `dependencies` and `devDependencies` (merged into npm)
  - `requirements.txt` — parses pip-style lines (package==version, package>=version, etc.)
  - `pyproject.toml` — extracts [project] dependencies (PEP 621)

  Returns a map suitable for the Analyzer to merge with LLM output.
  """

  @doc """
  Scans a file tree for dependency files and returns structured dependency info.

  Returns a map with keys:
  - `:npm` — map of package_name => version (from package.json)
  - `:pip` — map of package_name => version (from requirements.txt, pyproject.toml)
  - `:package_json_path` — path to package.json if found, nil otherwise
  - `:requirements_path` — path to requirements.txt if found, nil otherwise
  - `:pyproject_path` — path to pyproject.toml if found, nil otherwise

  ## Examples

      file_tree = %{
        "package.json" => "{\"dependencies\": {\"react\": \"^18.0.0\"}}",
        "references/commands.md" => "# Commands"
      }
      DependencyScanner.scan(file_tree)
      # => %{npm: %{"react" => "^18.0.0"}, pip: %{}, package_json_path: "package.json", ...}

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
    pyproject_path = find_file(file_tree, "pyproject.toml")

    # Merge pyproject deps into pip (pyproject wins on conflicts for same package)
    pip =
      case scan_pyproject(file_tree) do
        {:ok, pyproject_deps} when map_size(pyproject_deps) > 0 ->
          Map.merge(pip, pyproject_deps)

        _ ->
          pip
      end

    %{
      npm: npm,
      pip: pip,
      package_json_path: package_json_path,
      requirements_path: requirements_path,
      pyproject_path: pyproject_path
    }
  end

  def scan(_),
    do: %{npm: %{}, pip: %{}, package_json_path: nil, requirements_path: nil, pyproject_path: nil}

  defp find_file(file_tree, filename) do
    file_tree
    |> Map.keys()
    |> Enum.filter(fn path ->
      path == filename or String.ends_with?(path, "/#{filename}")
    end)
    |> Enum.sort_by(&String.length/1)
    |> List.first()
  end

  defp scan_npm(file_tree) do
    case find_and_parse_package_json(file_tree) do
      {:ok, deps, _primary_path} -> deps
      _ -> %{}
    end
  end

  defp find_and_parse_package_json(file_tree) do
    paths =
      file_tree
      |> Map.keys()
      |> Enum.filter(fn path -> Path.basename(path) == "package.json" end)
      |> Enum.sort_by(fn p -> {-String.length(p), p} end)

    if paths == [] do
      {:error, :not_found}
    else
      primary_path = List.last(paths)

      # Merge deps: root (shallowest path) wins on conflicts. Paths sorted longest-first,
      # so shallowest is last. Merge in order so shallowest overwrites.
      merged =
        paths
        |> Enum.map(fn path -> Map.get(file_tree, path) end)
        |> Enum.map(fn content ->
          case content && Jason.decode(content) do
            {:ok, %{} = parsed} ->
              deps = Map.get(parsed, "dependencies", %{}) |> extract_npm_versions()
              dev_deps = Map.get(parsed, "devDependencies", %{}) |> extract_npm_versions()
              Map.merge(deps, dev_deps)

            _ ->
              %{}
          end
        end)
        |> Enum.reduce(%{}, fn elem, acc -> Map.merge(acc, elem) end)

      {:ok, merged, primary_path}
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
    requirements_path = find_file(file_tree, "requirements.txt")

    if requirements_path do
      content = Map.get(file_tree, requirements_path)

      parse_requirements_txt(
        content,
        file_tree,
        Path.dirname(requirements_path),
        MapSet.new([requirements_path])
      )
    else
      %{}
    end
  end

  defp parse_requirements_txt(content, file_tree, base_dir, seen) when is_binary(content) do
    content
    |> String.split(~r/\r?\n/, trim: false)
    |> Enum.flat_map(&process_requirements_line(&1, file_tree, base_dir, seen))
    |> Map.new()
  end

  defp process_requirements_line(line, file_tree, base_dir, seen) do
    line = String.trim(line)

    cond do
      line == "" or String.starts_with?(line, "#") ->
        []

      # -r other.txt: include referenced file (skip if already seen to avoid cycles)
      String.match?(line, ~r/^-r\s+/i) ->
        path = line |> String.replace(~r/^-r\s+/i, "") |> String.trim()
        included_path = resolve_requirements_path(path, base_dir, file_tree)
        content = included_path && Map.get(file_tree, included_path)

        if content && !MapSet.member?(seen, included_path) do
          included_base = Path.dirname(included_path)
          new_seen = MapSet.put(seen, included_path)

          parse_requirements_txt(content, file_tree, included_base, new_seen)
          |> Map.to_list()
        else
          []
        end

      # -e (editable) and -c (constraints): skip
      String.starts_with?(line, "-e") or String.starts_with?(line, "-c") ->
        []

      true ->
        case parse_requirements_line(line) do
          {name, version} -> [{name, version}]
          nil -> []
        end
    end
  end

  defp resolve_requirements_path(path, base_dir, file_tree) do
    candidates = [
      path,
      if(base_dir in ["", "."], do: path, else: Path.join(base_dir, path))
    ]

    Enum.find(candidates, fn p -> Map.has_key?(file_tree, p) end) ||
      file_tree
      |> Map.keys()
      |> Enum.find(fn p -> Path.basename(p) == Path.basename(path) end)
  end

  defp strip_leading_equals(version) do
    String.trim_leading(version, "==")
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

  # -- pyproject.toml (PEP 621) --

  defp scan_pyproject(file_tree) do
    content =
      file_tree
      |> Map.keys()
      |> Enum.find_value(fn path ->
        if Path.basename(path) == "pyproject.toml" do
          Map.get(file_tree, path)
        end
      end)

    if content do
      {:ok, parse_pyproject_deps(content)}
    else
      {:error, :not_found}
    end
  end

  # Parses [project] dependencies = ["flask>=3.0", "requests", ...]
  defp parse_pyproject_deps(content) do
    case Regex.run(~r/dependencies\s*=\s*\[([\s\S]*?)\]/m, content) do
      [_, array_body] ->
        Regex.scan(~r/["']([^"']+)["']/, array_body)
        |> Enum.map(fn [_, spec] -> parse_pyproject_dep_spec(spec) end)
        |> Enum.reject(&is_nil/1)
        |> Map.new()

      _ ->
        %{}
    end
  end

  # Parse PEP 508 spec: "flask>=3.0", "requests", "package[extra]>=1.0"
  defp parse_pyproject_dep_spec(spec) when is_binary(spec) do
    spec = spec |> String.trim() |> String.trim("\"") |> String.trim("'")

    if spec == "" or String.starts_with?(spec, "#") do
      nil
    else
      # Extract package name (before [ or any version specifier)
      name =
        spec
        |> String.split([" ", "[", ">=", "==", "!=", "~=", "<=", ">", "<"])
        |> List.first()
        |> String.trim()

      if name != "" do
        # Extract version if present (e.g. ">=3.0" from "flask>=3.0")
        version =
          case Regex.run(~r/(?:>=|==|!=|~=|<=|>|<)\s*[\w.*]+/, spec) do
            [match] -> String.trim(match)
            _ -> nil
          end

        {name, version}
      else
        nil
      end
    end
  end
end
