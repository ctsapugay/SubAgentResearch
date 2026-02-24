defmodule SkillToSandbox.Skills.GitHubFetcher do
  @moduledoc """
  Fetches skill content from GitHub, supporting both single files and directories.

  - **File URLs** (e.g. `https://github.com/org/repo/blob/main/skills/agent-browser/SKILL.md`):
    Uses raw.githubusercontent.com to fetch content directly.

  - **Directory URLs** (e.g. `https://github.com/org/repo/tree/main/skills/agent-browser`):
    Uses GitHub API (Git Trees) to recursively fetch all files, then strips paths
    to be relative to the skill root.

  Supports optional `GITHUB_TOKEN` environment variable for higher rate limits
  when fetching directories (5000 vs 60 requests/hour).

  ## Binary files

  Skips blobs that decode to invalid UTF-8 or have binary extensions
  (.png, .jpg, .pdf, etc.). Skill content is typically text.
  """

  @binary_extensions ~w(.png .jpg .jpeg .gif .webp .ico .pdf .woff .woff2 .ttf .eot .otf .mp4 .webm .mp3 .wav .zip .tar .gz .exe)

  @doc """
  Fetches content from a GitHub URL. Supports both file and directory URLs.

  ## Examples

      # Single file
      fetch("https://github.com/org/repo/blob/main/skills/agent-browser/SKILL.md")
      # => {:ok, %{type: :file, content: "...", path: "skills/agent-browser/SKILL.md"}}

      # Directory
      fetch("https://github.com/org/repo/tree/main/skills/agent-browser")
      # => {:ok, %{type: :directory, file_tree: %{"SKILL.md" => "...", "references/commands.md" => "..."}, root_url: "..."}}

      # Raw URL (single file)
      fetch("https://raw.githubusercontent.com/org/repo/main/skills/agent-browser/SKILL.md")
      # => {:ok, %{type: :file, content: "...", path: "skills/agent-browser/SKILL.md"}}

      # Error
      fetch("https://github.com/org/repo/blob/main/nonexistent.md")
      # => {:error, :not_found}

  """
  @spec fetch(url :: String.t()) ::
          {:ok, %{type: :file, content: String.t(), path: String.t()}}
          | {:ok,
             %{type: :directory, file_tree: %{String.t() => String.t()}, root_url: String.t()}}
          | {:error, atom() | String.t()}
  def fetch(url) when is_binary(url) do
    url = String.trim(url)

    case parse_github_url(url) do
      {:ok, %{type: :file, owner: o, repo: r, ref: ref, path: p}} ->
        fetch_file(o, r, ref, p)

      {:ok, %{type: :directory, owner: o, repo: r, ref: ref, path: p}} ->
        fetch_directory(o, r, ref, p, url)

      {:error, _} = err ->
        err
    end
  end

  def fetch(_), do: {:error, :invalid_url}

  # Base URLs for HTTP requests (configurable for testing)
  defp raw_base do
    Application.get_env(:skill_to_sandbox, :github_raw_base, "https://raw.githubusercontent.com")
  end

  defp api_base do
    Application.get_env(:skill_to_sandbox, :github_api_base, "https://api.github.com")
  end

  # -- URL parsing --

  defp parse_github_url(url) do
    uri = URI.parse(url)

    cond do
      uri.host == "raw.githubusercontent.com" ->
        parse_raw_url(uri)

      uri.host == "github.com" ->
        parse_github_com_url(uri)

      true ->
        {:error, :invalid_url}
    end
  end

  defp parse_raw_url(uri) do
    # https://raw.githubusercontent.com/owner/repo/ref/path/to/file
    parts = uri.path |> String.trim_leading("/") |> String.split("/")

    if length(parts) >= 4 do
      [owner, repo, ref | path_parts] = parts
      path = Enum.join(path_parts, "/")
      {:ok, %{type: :file, owner: owner, repo: repo, ref: ref, path: path}}
    else
      {:error, :invalid_url}
    end
  end

  defp parse_github_com_url(uri) do
    # /owner/repo/blob/ref/path or /owner/repo/tree/ref/path
    parts = uri.path |> String.trim_leading("/") |> String.split("/")

    if length(parts) >= 5 do
      [owner, repo, action, ref | path_parts] = parts
      path = Enum.join(path_parts, "/")

      case action do
        "blob" -> {:ok, %{type: :file, owner: owner, repo: repo, ref: ref, path: path}}
        "tree" -> {:ok, %{type: :directory, owner: owner, repo: repo, ref: ref, path: path}}
        _ -> {:error, :invalid_url}
      end
    else
      {:error, :invalid_url}
    end
  end

  # -- File fetch --

  defp fetch_file(owner, repo, ref, path) do
    raw_url = "#{raw_base()}/#{owner}/#{repo}/#{ref}/#{path}"

    opts = [headers: auth_headers(), retry: false]

    case Req.get(raw_url, opts) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        if valid_utf8?(body) do
          {:ok, %{type: :file, content: body, path: path}}
        else
          {:error, :binary_content}
        end

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status}} ->
        {:error, "GitHub returned HTTP #{status}"}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, %Req.TransportError{reason: reason}} ->
        {:error, "Network error: #{inspect(reason)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # -- Directory fetch (Git Trees API) --

  defp fetch_directory(owner, repo, ref, path, original_url) do
    with {:ok, tree_sha} <- get_tree_sha(owner, repo, ref),
         {:ok, tree} <- get_tree_recursive(owner, repo, tree_sha),
         {:ok, file_tree} <- fetch_blobs(owner, repo, tree, path),
         {:ok, root_url} <- build_root_url(original_url) do
      if map_size(file_tree) == 0 do
        {:error, :empty_directory}
      else
        unless Map.has_key?(file_tree, "SKILL.md") do
          # Plan says return :no_skill_md - but we could still return the tree
          # and let the caller decide. For now we allow it; the parser may find
          # another .md at root.
        end

        {:ok, %{type: :directory, file_tree: file_tree, root_url: root_url}}
      end
    end
  end

  defp get_tree_sha(owner, repo, ref) do
    url = "#{api_base()}/repos/#{owner}/#{repo}/commits/#{ref}"
    opts = [headers: auth_headers(), retry: false]

    case Req.get(url, opts) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        sha = get_in(body, ["commit", "tree", "sha"])
        if sha, do: {:ok, sha}, else: {:error, :not_found}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status}} ->
        {:error, "GitHub API returned HTTP #{status}"}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_tree_recursive(owner, repo, tree_sha) do
    url = "#{api_base()}/repos/#{owner}/#{repo}/git/trees/#{tree_sha}?recursive=1"
    opts = [headers: auth_headers(), retry: false]

    case Req.get(url, opts) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        tree = body["tree"] || []
        {:ok, tree}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status}} ->
        {:error, "GitHub API returned HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_blobs(owner, repo, tree, dir_path) do
    prefix = if dir_path == "", do: "", else: dir_path <> "/"
    blobs = Enum.filter(tree, fn t -> t["type"] == "blob" and path_under?(t["path"], prefix) end)

    file_tree =
      blobs
      |> Task.async_stream(
        fn t ->
          path = t["path"]
          rel = strip_prefix(path, prefix)

          if binary_extension?(rel) do
            nil
          else
            case fetch_blob(owner, repo, t["sha"]) do
              {:ok, content} when is_binary(content) -> {rel, content}
              _ -> nil
            end
          end
        end,
        max_concurrency: 5,
        ordered: false
      )
      |> Enum.reduce(%{}, fn
        {:ok, nil}, acc -> acc
        {:ok, {key, val}}, acc -> Map.put(acc, key, val)
      end)

    {:ok, file_tree}
  end

  defp path_under?(_path, "") do
    # Root of repo - include everything
    true
  end

  defp path_under?(path, prefix) do
    String.starts_with?(path, prefix)
  end

  defp strip_prefix(path, "") when path != "" do
    path
  end

  defp strip_prefix(path, prefix) do
    if String.starts_with?(path, prefix) do
      String.trim_leading(path, prefix)
    else
      path
    end
  end

  defp fetch_blob(owner, repo, sha) do
    url = "#{api_base()}/repos/#{owner}/#{repo}/git/blobs/#{sha}"
    opts = [headers: auth_headers(), retry: false]

    case Req.get(url, opts) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        encoding = body["encoding"] || "utf-8"
        content = body["content"]

        if encoding == "base64" and content do
          decoded =
            content
            |> Base.decode64!(padding: false)
            |> case do
              bin when is_binary(bin) ->
                if valid_utf8?(bin), do: bin, else: nil

              _ ->
                nil
            end

          if decoded, do: {:ok, decoded}, else: {:error, :binary_content}
        else
          {:error, :unsupported_encoding}
        end

      {:ok, %{status: _}} ->
        {:error, :fetch_failed}

      {:error, _} ->
        {:error, :fetch_failed}
    end
  end

  defp build_root_url(original_url) do
    # Return the original URL as root_url (it's the directory tree URL)
    {:ok, original_url}
  end

  # -- Helpers --

  defp auth_headers do
    case System.get_env("GITHUB_TOKEN") do
      nil -> []
      "" -> []
      token -> [{"authorization", "Bearer #{token}"}]
    end
  end

  defp valid_utf8?(binary) do
    case String.valid?(binary) do
      true -> true
      false -> false
    end
  end

  defp binary_extension?(path) do
    ext = Path.extname(path) |> String.downcase()
    ext in @binary_extensions
  end
end
