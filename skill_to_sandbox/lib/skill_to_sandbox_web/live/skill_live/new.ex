defmodule SkillToSandboxWeb.SkillLive.New do
  @moduledoc """
  Form for creating a new skill via paste, file upload, or GitHub URL.
  """
  use SkillToSandboxWeb, :live_view

  alias SkillToSandbox.Skills

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
      create_skill(socket, name, content, nil)
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
        create_skill(socket, name, content, nil)

      [] ->
        {:noreply, assign(socket, :error, "Please select a file to upload.")}
    end
  end

  @impl true
  def handle_event("save_url", %{"name" => _name, "url" => url}, socket) do
    if String.trim(url) == "" do
      {:noreply, assign(socket, :error, "URL cannot be empty.")}
    else
      {:noreply,
       socket
       |> assign(:error, "URL fetching will be available in Phase 2. Use paste or upload for now.")
      }
    end
  end

  defp create_skill(socket, name, raw_content, source_url) do
    skill_name =
      if String.trim(name) != "" do
        String.trim(name)
      else
        extract_name_from_content(raw_content) || "Unnamed Skill"
      end

    attrs = %{
      name: skill_name,
      raw_content: raw_content,
      source_url: source_url,
      description: extract_description_from_content(raw_content)
    }

    case Skills.create_skill(attrs) do
      {:ok, skill} ->
        {:noreply,
         socket
         |> put_flash(:info, "Skill \"#{skill.name}\" uploaded successfully!")
         |> redirect(to: "/skills/#{skill.id}")}

      {:error, changeset} ->
        errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
        {:noreply, assign(socket, :error, "Failed to save: #{inspect(errors)}")}
    end
  end

  defp extract_name_from_content(content) do
    cond do
      match = Regex.run(~r/^---\s*\n.*?name:\s*(.+?)\s*\n/s, content) ->
        Enum.at(match, 1)

      match = Regex.run(~r/^#\s+(.+)$/m, content) ->
        Enum.at(match, 1)

      true ->
        nil
    end
  end

  defp extract_description_from_content(content) do
    case Regex.run(~r/^---\s*\n.*?description:\s*(.+?)\s*\n/s, content) do
      [_, desc] -> desc
      _ -> nil
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
        <div class="glass-panel !border-error/20 flex items-center gap-2.5 px-4 py-3 text-sm text-error">
          <.icon name="hero-exclamation-circle-micro" class="size-4 shrink-0" />
          {@error}
        </div>
      <% end %>

      <%!-- Mode Tabs --%>
      <div class="glass-panel inline-flex p-1 gap-0.5">
        <button
          phx-click="switch_mode" phx-value-mode="paste"
          class={["px-4 py-1.5 rounded-lg text-sm font-medium transition-all",
            if(@input_mode == "paste", do: "bg-primary text-primary-content shadow-md shadow-primary/20", else: "text-base-content/50 hover:text-base-content")]}
        >
          Paste
        </button>
        <button
          phx-click="switch_mode" phx-value-mode="upload"
          class={["px-4 py-1.5 rounded-lg text-sm font-medium transition-all",
            if(@input_mode == "upload", do: "bg-primary text-primary-content shadow-md shadow-primary/20", else: "text-base-content/50 hover:text-base-content")]}
        >
          File Upload
        </button>
        <button
          phx-click="switch_mode" phx-value-mode="url"
          class={["px-4 py-1.5 rounded-lg text-sm font-medium transition-all",
            if(@input_mode == "url", do: "bg-primary text-primary-content shadow-md shadow-primary/20", else: "text-base-content/50 hover:text-base-content")]}
        >
          GitHub URL
        </button>
      </div>

      <%!-- Paste Mode --%>
      <%= if @input_mode == "paste" do %>
        <form phx-submit="save_paste" phx-change="validate" class="space-y-4">
          <div>
            <label class="text-sm font-medium text-base-content/60 mb-1.5 block">Skill Name</label>
            <input
              type="text" name="name" value={@name}
              placeholder="e.g., frontend-design (auto-detected if blank)"
              class="input input-bordered w-full input-sm bg-base-content/[0.03] border-base-content/10 focus:border-primary/40"
            />
          </div>
          <div>
            <label class="text-sm font-medium text-base-content/60 mb-1.5 block">SKILL.md Content</label>
            <textarea
              name="content" rows="14"
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
        <form phx-submit="save_upload" phx-change="validate" class="space-y-4">
          <div>
            <label class="text-sm font-medium text-base-content/60 mb-1.5 block">Skill Name</label>
            <input
              type="text" name="name" value={@name}
              placeholder="e.g., frontend-design (auto-detected if blank)"
              class="input input-bordered w-full input-sm bg-base-content/[0.03] border-base-content/10 focus:border-primary/40"
            />
          </div>
          <div>
            <label class="text-sm font-medium text-base-content/60 mb-1.5 block">SKILL.md File</label>
            <div
              class="glass-panel !border-dashed p-8 text-center"
              phx-drop-target={@uploads.skill_file.ref}
            >
              <.live_file_input upload={@uploads.skill_file} class="file-input file-input-bordered file-input-sm w-full max-w-xs bg-base-content/[0.03] border-base-content/10" />
              <p class="mt-2 text-xs text-base-content/30">Accepts .md files</p>
            </div>
            <%= for entry <- @uploads.skill_file.entries do %>
              <div class="flex items-center gap-2 mt-2">
                <span class="text-xs font-medium px-2.5 py-0.5 rounded-full bg-accent/10 text-accent">{entry.client_name}</span>
                <span class="text-xs text-base-content/35">{Float.round(entry.client_size / 1024, 1)} KB</span>
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
        <form phx-submit="save_url" phx-change="validate" class="space-y-4">
          <div>
            <label class="text-sm font-medium text-base-content/60 mb-1.5 block">Skill Name</label>
            <input
              type="text" name="name" value={@name}
              placeholder="e.g., frontend-design (auto-detected if blank)"
              class="input input-bordered w-full input-sm bg-base-content/[0.03] border-base-content/10 focus:border-primary/40"
            />
          </div>
          <div>
            <label class="text-sm font-medium text-base-content/60 mb-1.5 block">GitHub URL</label>
            <input
              type="url" name="url" value={@url}
              placeholder="https://github.com/org/repo/blob/main/SKILL.md"
              class="input input-bordered w-full input-sm bg-base-content/[0.03] border-base-content/10 focus:border-primary/40"
            />
            <p class="text-xs text-base-content/30 mt-1.5">Direct link to a SKILL.md file on GitHub</p>
          </div>
          <button type="submit" class="btn btn-primary btn-sm shadow-lg shadow-primary/20">
            Fetch & Upload
          </button>
        </form>
      <% end %>
    </div>
    """
  end
end
