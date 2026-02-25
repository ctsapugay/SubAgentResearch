defmodule SkillToSandboxWeb.SkillLive.New do
  @moduledoc """
  Form for creating a new skill via paste, file upload, or GitHub URL.

  - **Paste:** Single SKILL.md content; uses `Parser.parse/1`
  - **File upload:** .md (single file) or .zip (skill directory with SKILL.md)
  - **GitHub URL:** File (blob) or directory (tree); uses `GitHubFetcher.fetch/1`

  Directory skills use `Parser.parse_directory/1` to merge tools, frameworks,
  and dependencies from all .md and .sh files in the tree.
  """
  use SkillToSandboxWeb, :live_view

  alias SkillToSandbox.Skills
  alias SkillToSandbox.Skills.Parser
  alias SkillToSandbox.Skills.GitHubFetcher

  @max_zip_total_bytes 10 * 1024 * 1024
  @max_zip_file_count 200

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Upload Skill")
      |> assign(:input_mode, "paste")
      |> assign(:name, "")
      |> assign(:content, "")
      |> assign(:url, "")
      |> assign(:error, nil)
      |> assign(:fetching, false)
      |> allow_upload(:skill_file, accept: ~w(.md .zip), max_entries: 1)

    {:ok, socket}
  end

  @impl true
  def handle_event("switch_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :input_mode, mode)}
  end

  @impl true
  def handle_event("validate", params, socket) do
    socket =
      socket
      |> assign(:name, params["name"] || "")
      |> assign(:content, params["content"] || "")
      |> assign(:url, params["url"] || "")

    {:noreply, socket}
  end

  @impl true
  def handle_event("save_paste", %{"name" => name, "content" => content}, socket) do
    if String.trim(content) == "" do
      {:noreply, assign(socket, :error, "Content cannot be empty.")}
    else
      create_skill_with_parser(socket, name, %{raw_content: content, source_url: nil})
    end
  end

  @impl true
  def handle_event("save_upload", %{"name" => name}, socket) do
    uploaded =
      consume_uploaded_entries(socket, :skill_file, fn %{path: path, client_name: client_name},
                                                       _entry ->
        ext = Path.extname(client_name) |> String.downcase()
        {:ok, {path, ext}}
      end)

    case uploaded do
      [{path, ".md"} | _] ->
        content = File.read!(path)
        create_skill_with_parser(socket, name, %{raw_content: content, source_url: nil})

      [{path, ".zip"} | _] ->
        case extract_zip_to_file_tree(path) do
          {:ok, file_tree} ->
            create_skill_with_parser(socket, name, %{file_tree: file_tree, source_root_url: nil})

          {:error, msg} ->
            {:noreply, assign(socket, :error, msg)}
        end

      [] ->
        {:noreply, assign(socket, :error, "Please select a file to upload.")}

      [{_, ext} | _] ->
        {:noreply, assign(socket, :error, "Unsupported file type: #{ext}")}
    end
  end

  @impl true
  def handle_event("save_url", %{"name" => name, "url" => url}, socket) do
    url = String.trim(url)

    cond do
      url == "" ->
        {:noreply, assign(socket, :error, "URL cannot be empty.")}

      not github_url?(url) ->
        {:noreply,
         assign(
           socket,
           :error,
           "Please provide a valid GitHub URL (file: .../blob/main/SKILL.md or directory: .../tree/main/skills/agent-browser)."
         )}

      true ->
        socket = assign(socket, :fetching, true)
        send(self(), {:fetch_url, name, url})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:fetch_url, name, url}, socket) do
    case GitHubFetcher.fetch(url) do
      {:ok, %{type: :file, content: content}} ->
        socket = assign(socket, :fetching, false)
        create_skill_with_parser(socket, name, %{raw_content: content, source_url: url})

      {:ok, %{type: :directory, file_tree: file_tree, root_url: root_url}} ->
        socket = assign(socket, :fetching, false)

        create_skill_with_parser(socket, name, %{
          file_tree: file_tree,
          source_root_url: root_url
        })

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:fetching, false)
         |> assign(:error, "URL not found. Check that the file or directory exists on GitHub.")}

      {:error, :invalid_url} ->
        {:noreply,
         socket
         |> assign(:fetching, false)
         |> assign(:error, "Invalid GitHub URL. Use blob (file) or tree (directory) URLs.")}

      {:error, :empty_directory} ->
        {:noreply,
         socket
         |> assign(:fetching, false)
         |> assign(:error, "The directory is empty.")}

      {:error, reason} when is_atom(reason) ->
        {:noreply,
         socket
         |> assign(:fetching, false)
         |> assign(:error, "Failed to fetch: #{humanize_error(reason)}")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:fetching, false)
         |> assign(:error, "Failed to fetch: #{reason}")}
    end
  end

  # -- Private helpers --

  defp create_skill_with_parser(socket, name, %{file_tree: file_tree} = opts)
       when is_map(file_tree) and map_size(file_tree) > 0 do
    case Parser.parse_directory(file_tree) do
      {:ok, parsed_data} ->
        raw_content = Map.get(file_tree, "SKILL.md") || primary_md_content(file_tree)

        do_create_skill(socket, name, parsed_data, raw_content, %{
          source_type: "directory",
          source_root_url: opts[:source_root_url],
          file_tree: file_tree
        })

      {:error, :no_skill_md} ->
        {:noreply,
         assign(socket, :error, "Directory must contain SKILL.md or a .md file at root.")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Parse error: #{inspect(reason)}")}
    end
  end

  defp create_skill_with_parser(socket, name, %{raw_content: raw_content} = opts)
       when is_binary(raw_content) and byte_size(raw_content) > 0 do
    case Parser.parse(raw_content) do
      {:ok, parsed_data} ->
        file_tree = %{"SKILL.md" => raw_content}

        do_create_skill(socket, name, parsed_data, raw_content, %{
          source_type: "file",
          source_url: opts[:source_url],
          file_tree: file_tree
        })

      {:error, :empty_content} ->
        {:noreply, assign(socket, :error, "Content cannot be empty.")}

      {:error, :invalid_frontmatter} ->
        {:noreply,
         assign(
           socket,
           :error,
           "Invalid YAML frontmatter. Check the --- delimiters and YAML syntax."
         )}

      {:error, reason} ->
        {:noreply, assign(socket, :error, "Parse error: #{inspect(reason)}")}
    end
  end

  defp create_skill_with_parser(socket, _name, _opts) do
    {:noreply, assign(socket, :error, "Content cannot be empty.")}
  end

  defp do_create_skill(socket, name, parsed_data, raw_content, extra_attrs) do
    skill_name =
      cond do
        String.trim(name) != "" -> String.trim(name)
        parsed_data["name"] -> parsed_data["name"]
        true -> "Unnamed Skill"
      end

    attrs =
      %{
        name: skill_name,
        raw_content: raw_content,
        description: parsed_data["description"],
        parsed_data: parsed_data
      }
      |> Map.merge(extra_attrs)

    case Skills.create_skill(attrs) do
      {:ok, skill} ->
        {:noreply,
         socket
         |> put_flash(:info, "Skill \"#{skill.name}\" uploaded and parsed successfully!")
         |> redirect(to: "/skills/#{skill.id}")}

      {:error, changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
        {:noreply, assign(socket, :error, "Failed to save: #{inspect(errors)}")}
    end
  end

  defp primary_md_content(file_tree) do
    file_tree
    |> Map.keys()
    |> Enum.filter(&String.ends_with?(&1, ".md"))
    |> Enum.sort()
    |> List.first()
    |> case do
      nil -> ""
      key -> Map.get(file_tree, key, "")
    end
  end

  defp extract_zip_to_file_tree(zip_path) do
    temp_dir = Path.join(System.tmp_dir!(), "skill_zip_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(temp_dir)

    try do
      case :zip.unzip(String.to_charlist(zip_path), [{:cwd, String.to_charlist(temp_dir)}]) do
        {:ok, _file_list} ->
          build_file_tree_from_dir(temp_dir, @max_zip_total_bytes, @max_zip_file_count)

        {:error, reason} ->
          {:error, "ZIP extraction failed: #{inspect(reason)}"}
      end
    after
      File.rm_rf!(temp_dir)
    end
  end

  defp build_file_tree_from_dir(dir, max_bytes, max_files) do
    expanded_dir = Path.expand(dir)

    result =
      dir
      |> Path.join("**")
      |> Path.wildcard()
      |> Enum.reject(&File.dir?/1)
      |> Enum.reduce_while({%{}, 0, 0}, fn full_path, {acc, bytes, count} ->
        if count >= max_files do
          {:halt, {:error, "ZIP contains more than #{max_files} files."}}
        else
          rel_path = Path.relative_to(full_path, expanded_dir)
          normalized = Path.expand(Path.join(expanded_dir, rel_path))

          unless String.starts_with?(normalized, expanded_dir) do
            {:halt, {:error, "Invalid path in ZIP (path traversal detected)."}}
          else
            content = File.read!(full_path)

            unless String.valid?(content) do
              # Skip binary files
              {:cont, {acc, bytes, count}}
            else
              new_bytes = bytes + byte_size(content)

              if new_bytes > max_bytes do
                {:halt,
                 {:error, "ZIP total size exceeds #{div(max_bytes, 1024 * 1024)}MB limit."}}
              else
                # Normalize path to use forward slashes
                key = rel_path |> Path.split() |> Enum.join("/")
                {:cont, {Map.put(acc, key, content), new_bytes, count + 1}}
              end
            end
          end
        end
      end)

    case result do
      {:error, msg} -> {:error, msg}
      {file_tree, _bytes, _count} -> find_skill_root_and_build_tree(file_tree)
    end
  end

  defp find_skill_root_and_build_tree(file_tree) do
    # Find SKILL.md (shallowest wins)
    skill_md_path =
      file_tree
      |> Map.keys()
      |> Enum.filter(&String.ends_with?(&1, "SKILL.md"))
      |> Enum.sort_by(&String.length/1)
      |> List.first()

    if skill_md_path do
      root = Path.dirname(skill_md_path)
      root_prefix = if root in [".", ""], do: "", else: root <> "/"

      result =
        file_tree
        |> Enum.filter(fn {path, _} ->
          root_prefix == "" or String.starts_with?(path, root_prefix)
        end)
        |> Enum.map(fn {path, content} ->
          rel = if root_prefix == "", do: path, else: String.trim_leading(path, root_prefix)
          {rel, content}
        end)
        |> Map.new()

      {:ok, result}
    else
      {:error, "ZIP must contain SKILL.md."}
    end
  end

  defp github_url?(url) do
    uri = URI.parse(url)

    cond do
      uri.host == "raw.githubusercontent.com" and uri.scheme in ["http", "https"] ->
        true

      uri.host == "github.com" and uri.scheme in ["http", "https"] ->
        # Accept both file (blob) and directory (tree) URLs
        uri.path =~ ~r{/(?:blob|tree)/}

      true ->
        false
    end
  end

  defp humanize_error(:rate_limited),
    do: "GitHub rate limit exceeded. Try again later or set GITHUB_TOKEN."

  defp humanize_error(:timeout), do: "Request timed out."
  defp humanize_error(:binary_content), do: "File contains binary content."
  defp humanize_error(reason), do: inspect(reason)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 max-w-2xl">
      <a href="/skills" class="back-btn">
        <.icon name="hero-arrow-left-micro" class="size-3.5" /> Skills
      </a>

      <div>
        <h1 class="text-2xl font-semibold tracking-tight">Upload Skill</h1>
        <p class="text-sm text-base-content/45 mt-0.5">
          Add a SKILL.md definition via paste, file upload, or GitHub URL.
        </p>
      </div>

      <%!-- Error --%>
      <%= if @error do %>
        <div
          id="upload-error"
          class="glass-panel !border-error/20 flex items-center gap-2.5 px-4 py-3 text-sm text-error"
        >
          <.icon name="hero-exclamation-circle-micro" class="size-4 shrink-0" />
          {@error}
        </div>
      <% end %>

      <%!-- Mode Tabs --%>
      <div class="glass-panel inline-flex p-1 gap-0.5">
        <button
          phx-click="switch_mode"
          phx-value-mode="paste"
          class={[
            "px-4 py-1.5 rounded-lg text-sm font-medium transition-all",
            if(@input_mode == "paste",
              do: "bg-primary text-primary-content shadow-md shadow-primary/20",
              else: "text-base-content/50 hover:text-base-content"
            )
          ]}
        >
          Paste
        </button>
        <button
          phx-click="switch_mode"
          phx-value-mode="upload"
          class={[
            "px-4 py-1.5 rounded-lg text-sm font-medium transition-all",
            if(@input_mode == "upload",
              do: "bg-primary text-primary-content shadow-md shadow-primary/20",
              else: "text-base-content/50 hover:text-base-content"
            )
          ]}
        >
          File Upload
        </button>
        <button
          phx-click="switch_mode"
          phx-value-mode="url"
          class={[
            "px-4 py-1.5 rounded-lg text-sm font-medium transition-all",
            if(@input_mode == "url",
              do: "bg-primary text-primary-content shadow-md shadow-primary/20",
              else: "text-base-content/50 hover:text-base-content"
            )
          ]}
        >
          GitHub URL
        </button>
      </div>

      <%!-- Paste Mode --%>
      <%= if @input_mode == "paste" do %>
        <form id="paste-form" phx-submit="save_paste" phx-change="validate" class="space-y-4">
          <div>
            <label class="text-sm font-medium text-base-content/60 mb-1.5 block">Skill Name</label>
            <input
              type="text"
              name="name"
              value={@name}
              placeholder="e.g., frontend-design (auto-detected from frontmatter if blank)"
              class="input input-bordered w-full input-sm bg-base-content/[0.03] border-base-content/10 focus:border-primary/40"
            />
          </div>
          <div>
            <label class="text-sm font-medium text-base-content/60 mb-1.5 block">
              SKILL.md Content
            </label>
            <textarea
              name="content"
              rows="14"
              placeholder="Paste your SKILL.md content here..."
              class="textarea textarea-bordered w-full font-mono text-[13px] leading-relaxed bg-base-content/[0.03] border-base-content/10 focus:border-primary/40"
            >{@content}</textarea>
          </div>
          <button type="submit" class="btn btn-primary btn-sm shadow-lg shadow-primary/20">
            Upload Skill
          </button>
        </form>
      <% end %>

      <%!-- Upload Mode --%>
      <%= if @input_mode == "upload" do %>
        <form id="upload-form" phx-submit="save_upload" phx-change="validate" class="space-y-4">
          <div>
            <label class="text-sm font-medium text-base-content/60 mb-1.5 block">Skill Name</label>
            <input
              type="text"
              name="name"
              value={@name}
              placeholder="e.g., frontend-design (auto-detected from frontmatter if blank)"
              class="input input-bordered w-full input-sm bg-base-content/[0.03] border-base-content/10 focus:border-primary/40"
            />
          </div>
          <div>
            <label class="text-sm font-medium text-base-content/60 mb-1.5 block">
              Skill File or ZIP
            </label>
            <div
              class="glass-panel !border-dashed p-8 text-center"
              phx-drop-target={@uploads.skill_file.ref}
            >
              <.live_file_input
                upload={@uploads.skill_file}
                class="file-input file-input-bordered file-input-sm w-full max-w-xs bg-base-content/[0.03] border-base-content/10"
              />
              <p class="mt-2 text-xs text-base-content/30">Accepts .md or .zip (skill directory)</p>
            </div>
            <%= for entry <- @uploads.skill_file.entries do %>
              <div class="flex items-center gap-2 mt-2">
                <span class="text-xs font-medium px-2.5 py-0.5 rounded-full bg-accent/10 text-accent">
                  {entry.client_name}
                </span>
                <span class="text-xs text-base-content/35">
                  {Float.round(entry.client_size / 1024, 1)} KB
                </span>
              </div>
            <% end %>
          </div>
          <button type="submit" class="btn btn-primary btn-sm shadow-lg shadow-primary/20">
            Upload Skill
          </button>
        </form>
      <% end %>

      <%!-- URL Mode --%>
      <%= if @input_mode == "url" do %>
        <form id="url-form" phx-submit="save_url" phx-change="validate" class="space-y-4">
          <div>
            <label class="text-sm font-medium text-base-content/60 mb-1.5 block">Skill Name</label>
            <input
              type="text"
              name="name"
              value={@name}
              placeholder="e.g., frontend-design (auto-detected from frontmatter if blank)"
              class="input input-bordered w-full input-sm bg-base-content/[0.03] border-base-content/10 focus:border-primary/40"
            />
          </div>
          <div>
            <label class="text-sm font-medium text-base-content/60 mb-1.5 block">GitHub URL</label>
            <input
              type="url"
              name="url"
              value={@url}
              placeholder="https://github.com/org/repo/blob/main/SKILL.md or .../tree/main/skills/agent-browser"
              class="input input-bordered w-full input-sm bg-base-content/[0.03] border-base-content/10 focus:border-primary/40"
            />
            <p class="text-xs text-base-content/30 mt-1.5">
              GitHub file (blob) or directory (tree) URL. Directories are fetched recursively.
            </p>
          </div>
          <button
            type="submit"
            class="btn btn-primary btn-sm shadow-lg shadow-primary/20"
            disabled={@fetching}
          >
            <%= if @fetching do %>
              <span class="loading loading-spinner loading-xs"></span> Fetching...
            <% else %>
              Fetch & Upload
            <% end %>
          </button>
        </form>
      <% end %>
    </div>
    """
  end
end
