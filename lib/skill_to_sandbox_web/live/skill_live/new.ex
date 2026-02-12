defmodule SkillToSandboxWeb.SkillLive.New do
  @moduledoc """
  Form for creating a new skill via paste, file upload, or GitHub URL.

  All three modes run the parsed content through `Parser.parse/1` to extract
  structured data (tools, frameworks, dependencies, sections) which is stored
  alongside the raw content.
  """
  use SkillToSandboxWeb, :live_view

  alias SkillToSandbox.Skills
  alias SkillToSandbox.Skills.Parser

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
      |> allow_upload(:skill_file, accept: ~w(.md), max_entries: 1)

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
      create_skill_with_parser(socket, name, content, nil)
    end
  end

  @impl true
  def handle_event("save_upload", %{"name" => name}, socket) do
    uploaded_content =
      consume_uploaded_entries(socket, :skill_file, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    case uploaded_content do
      [content | _] ->
        create_skill_with_parser(socket, name, content, nil)

      [] ->
        {:noreply, assign(socket, :error, "Please select a file to upload.")}
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
           "Please provide a valid GitHub URL (e.g., https://github.com/org/repo/blob/main/SKILL.md)."
         )}

      true ->
        socket = assign(socket, :fetching, true)
        send(self(), {:fetch_url, name, url})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:fetch_url, name, url}, socket) do
    raw_url = to_raw_github_url(url)

    case Req.get(raw_url) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        socket = assign(socket, :fetching, false)
        create_skill_with_parser(socket, name, body, url)

      {:ok, %{status: status}} ->
        {:noreply,
         socket
         |> assign(:fetching, false)
         |> assign(
           :error,
           "Failed to fetch URL: GitHub returned HTTP #{status}. Check that the URL points to a valid file."
         )}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:fetching, false)
         |> assign(:error, "Failed to fetch URL: #{inspect(reason)}")}
    end
  end

  # -- Private helpers --

  defp create_skill_with_parser(socket, name, raw_content, source_url) do
    case Parser.parse(raw_content) do
      {:ok, parsed_data} ->
        # Use parsed name if the user didn't provide one
        skill_name =
          cond do
            String.trim(name) != "" -> String.trim(name)
            parsed_data["name"] -> parsed_data["name"]
            true -> "Unnamed Skill"
          end

        description = parsed_data["description"]

        attrs = %{
          name: skill_name,
          raw_content: raw_content,
          source_url: source_url,
          description: description,
          parsed_data: parsed_data
        }

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

  defp github_url?(url) do
    uri = URI.parse(url)
    uri.host in ["github.com", "raw.githubusercontent.com"] and uri.scheme in ["http", "https"]
  end

  defp to_raw_github_url(url) do
    uri = URI.parse(url)

    case uri.host do
      "raw.githubusercontent.com" ->
        # Already a raw URL
        url

      "github.com" ->
        # Convert github.com/.../blob/... to raw.githubusercontent.com/.../...
        path =
          uri.path
          |> String.replace(~r{/blob/}, "/", global: false)

        "https://raw.githubusercontent.com#{path}"

      _ ->
        url
    end
  end

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
            <label class="text-sm font-medium text-base-content/60 mb-1.5 block">SKILL.md File</label>
            <div
              class="glass-panel !border-dashed p-8 text-center"
              phx-drop-target={@uploads.skill_file.ref}
            >
              <.live_file_input
                upload={@uploads.skill_file}
                class="file-input file-input-bordered file-input-sm w-full max-w-xs bg-base-content/[0.03] border-base-content/10"
              />
              <p class="mt-2 text-xs text-base-content/30">Accepts .md files</p>
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
              placeholder="https://github.com/org/repo/blob/main/SKILL.md"
              class="input input-bordered w-full input-sm bg-base-content/[0.03] border-base-content/10 focus:border-primary/40"
            />
            <p class="text-xs text-base-content/30 mt-1.5">
              Direct link to a SKILL.md file on GitHub (will be converted to raw URL automatically)
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
