defmodule SkillToSandbox.Analysis.DependencyRelevantFiles do
  @moduledoc """
  Selects which files from a skill's file tree are relevant for dependency detection
  and suitable to send to the LLM. Prioritizes manifests, then files with imports/CDN URLs,
  then other code and HTML files.
  """

  # Paths/segments to exclude (e.g. node_modules/file.js)
  @excluded_path_segments ~w(node_modules vendor dist build)

  # Extensions that can contain dependency evidence
  @relevant_extensions ~w(.html .htm .js .ts .tsx .jsx .mjs .cjs .py .rb .go .rs .json .md)

  # Manifest filenames (basename matches)
  @manifest_basenames ~w(
    package.json package-lock.json yarn.lock pnpm-lock.yaml
    requirements.txt pyproject.toml Pipfile Pipfile.lock
    Cargo.toml go.mod Gemfile Gemfile.lock
  )

  # Patterns for import/CDN detection (pre-scan)
  @import_pattern ~r/require\s*\(|import\s+|<script\s+src\s*=\s*["']/i

  @doc """
  Returns true if the path is relevant for dependency detection.

  Includes: .html, .htm, .js, .ts, .tsx, .jsx, .mjs, .cjs, .py, .rb, .go, .rs, .json,
  .md (for backward compat with references/*.md), and manifest filenames.
  Excludes: node_modules/, vendor/, dist/, build/, LICENSE*
  """
  def dependency_relevant?(path) when is_binary(path) do
    not excluded_path?(path) and (manifest_file?(path) or relevant_extension?(path))
  end

  def dependency_relevant?(_), do: false

  @doc """
  Returns true if the path points to a manifest file.

  Manifest files: package.json, package-lock.json, yarn.lock, pnpm-lock.yaml,
  requirements.txt, requirements*.txt, pyproject.toml, Pipfile, Cargo.toml,
  go.mod, Gemfile, Gemfile.lock, etc.
  """
  def manifest_file?(path) when is_binary(path) do
    basename = Path.basename(path)
    basename in @manifest_basenames or String.match?(basename, ~r/^requirements.*\.txt$/i)
  end

  def manifest_file?(_), do: false

  @doc """
  Selects files from the file tree for LLM analysis, respecting a character budget.

  Priority order:
  1. Manifest files (full content)
  2. Files with require(, import , <script src= (pre-scan content)
  3. Other code/HTML files

  Excludes SKILL.md (sent separately as raw_content).
  Truncates long code files to first 5000 chars (imports at top).
  Returns [{path, content}, ...] until budget exhausted.
  """
  def select_files_for_llm(file_tree, budget_in_chars \\ 70_000)

  def select_files_for_llm(file_tree, budget_in_chars)
      when is_map(file_tree) and is_integer(budget_in_chars) and budget_in_chars > 0 do
    files =
      file_tree
      |> Enum.reject(fn {path, _} -> path == "SKILL.md" end)
      |> Enum.filter(fn {path, _} -> dependency_relevant?(path) end)
      |> Enum.sort_by(fn {path, content} -> priority(path, content) end, :asc)
      |> Enum.reduce({[], budget_in_chars}, fn {path, content}, {acc, remaining} ->
        if remaining <= 0 do
          {acc, 0}
        else
          {truncated_content, truncated?} = truncate_content(path, content)

          final_content =
            if truncated?, do: truncated_content <> "\n[truncated]", else: truncated_content

          used = String.length(final_content)
          {acc ++ [{path, final_content}], remaining - used}
        end
      end)

    elem(files, 0)
  end

  def select_files_for_llm(_, _), do: []

  # -- Helpers --

  defp excluded_path?(path) do
    path_segments = String.split(path, "/")
    basename = Path.basename(path)

    Enum.any?(@excluded_path_segments, &(&1 in path_segments)) or
      String.starts_with?(String.downcase(basename), "license")
  end

  defp relevant_extension?(path) do
    ext = Path.extname(path)
    ext in @relevant_extensions
  end

  # Lower number = higher priority. 1=manifests, 2=imports, 3=other
  defp priority(path, content) do
    cond do
      manifest_file?(path) -> 1
      has_import_pattern?(content) -> 2
      true -> 3
    end
  end

  defp has_import_pattern?(content) when is_binary(content) do
    Regex.match?(@import_pattern, content)
  end

  defp has_import_pattern?(_), do: false

  defp truncate_content(path, content) do
    if manifest_file?(path) do
      {content, false}
    else
      max_chars = 5_000

      if String.length(content) > max_chars do
        {String.slice(content, 0, max_chars), true}
      else
        {content, false}
      end
    end
  end
end
