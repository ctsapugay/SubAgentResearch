defmodule SkillToSandboxWeb.SkillLive.Show do
  @moduledoc """
  Displays a single skill's details, parsed analysis, and raw content.

  After Phase 2, the parsed analysis section shows detected tools,
  frameworks, dependencies, and sections extracted by the Parser module.
  Phase 3 adds the "Analyze" button that triggers LLM analysis and
  redirects to the pipeline spec review page.
  """
  use SkillToSandboxWeb, :live_view

  alias SkillToSandbox.Skills
  alias SkillToSandbox.Pipeline.Supervisor, as: PipelineSupervisor

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    skill = Skills.get_skill!(id)

    socket =
      socket
      |> assign(:page_title, skill.name)
      |> assign(:skill, skill)
      |> assign(:analyzing, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("analyze", _params, socket) do
    skill = socket.assigns.skill

    # Prevent double-clicks
    if socket.assigns.analyzing do
      {:noreply, socket}
    else
      socket = assign(socket, :analyzing, true)

      # Start a pipeline run via the Pipeline Supervisor (GenServer-backed)
      case PipelineSupervisor.start_pipeline(skill.id) do
        {:ok, run} ->
          {:noreply,
           socket
           |> put_flash(:info, "Pipeline started — parsing and analyzing your skill...")
           |> push_navigate(to: "/skills/#{skill.id}/pipeline?run=#{run.id}")}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:analyzing, false)
           |> put_flash(:error, "Failed to start pipeline: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def handle_event("delete", _params, socket) do
    {:ok, _} = Skills.delete_skill(socket.assigns.skill)

    {:noreply,
     socket
     |> put_flash(:info, "Skill deleted.")
     |> redirect(to: "/skills")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <a href="/skills" class="back-btn">
        <.icon name="hero-arrow-left-micro" class="size-3.5" /> Skills
      </a>

      <%!-- Header --%>
      <div class="flex items-start justify-between">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight">{@skill.name}</h1>
          <p class="text-sm text-base-content/45 mt-0.5">
            {@skill.description || "No description available"}
          </p>
          <%= if @skill.source_url do %>
            <a
              href={@skill.source_url}
              target="_blank"
              class="inline-flex items-center gap-1 text-xs text-accent hover:text-accent/80 mt-2 transition-colors"
            >
              <.icon name="hero-arrow-top-right-on-square-micro" class="size-3" /> View on GitHub
            </a>
          <% end %>
        </div>
        <div class="flex gap-2 shrink-0">
          <button
            id="analyze-skill-btn"
            phx-click="analyze"
            disabled={@analyzing}
            class={[
              "btn btn-primary btn-sm shadow-lg shadow-primary/20",
              @analyzing && "opacity-60 cursor-wait"
            ]}
          >
            <%= if @analyzing do %>
              <.icon name="hero-arrow-path" class="size-4 animate-spin" /> Analyzing...
            <% else %>
              <.icon name="hero-sparkles-micro" class="size-4" /> Analyze & Build
            <% end %>
          </button>
          <button
            id="delete-skill-btn"
            phx-click="delete"
            data-confirm="Are you sure you want to delete this skill?"
            class="btn btn-outline btn-xs border-error/20 text-error/60 hover:bg-error/10 hover:text-error hover:border-error/30"
          >
            <.icon name="hero-trash-micro" class="size-4" />
          </button>
        </div>
      </div>

      <div class="text-xs text-base-content/30">
        Uploaded {Calendar.strftime(@skill.inserted_at, "%B %d, %Y at %H:%M UTC")}
      </div>

      <%!-- Parsed Analysis --%>
      <div id="parsed-analysis" class="glass-panel overflow-hidden">
        <div class="px-5 py-3.5 border-b border-base-content/5">
          <h2 class="text-sm font-semibold flex items-center gap-2">
            <.icon name="hero-magnifying-glass-micro" class="size-4 text-accent" /> Parsed Analysis
          </h2>
        </div>
        <div class="p-5">
          <%= if has_parsed_data?(@skill) do %>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
              <%!-- Detected Tools --%>
              <%= if tools = get_parsed_list(@skill, "mentioned_tools") do %>
                <div>
                  <h3 class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30 mb-2.5">
                    Detected Tools
                  </h3>
                  <div class="flex flex-wrap gap-1.5">
                    <%= for tool <- tools do %>
                      <span class={["text-xs font-medium px-2.5 py-1 rounded-full", tool_color(tool)]}>
                        {format_tool_name(tool)}
                      </span>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%!-- Frameworks & Languages --%>
              <%= if frameworks = get_parsed_list(@skill, "mentioned_frameworks") do %>
                <div>
                  <h3 class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30 mb-2.5">
                    Frameworks & Languages
                  </h3>
                  <div class="flex flex-wrap gap-1.5">
                    <%= for fw <- frameworks do %>
                      <span class="text-xs font-medium px-2.5 py-1 rounded-full bg-accent/10 text-accent">
                        {fw}
                      </span>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%!-- Dependencies --%>
              <%= if deps = get_parsed_list(@skill, "mentioned_dependencies") do %>
                <div>
                  <h3 class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30 mb-2.5">
                    Dependencies
                  </h3>
                  <div class="flex flex-wrap gap-1.5">
                    <%= for dep <- deps do %>
                      <span class="text-xs font-medium px-2.5 py-1 rounded-full bg-secondary/10 text-secondary">
                        {dep}
                      </span>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <%!-- Document Sections --%>
              <%= if sections = get_parsed_list(@skill, "sections") do %>
                <div>
                  <h3 class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30 mb-2.5">
                    Document Sections
                  </h3>
                  <ul class="space-y-1">
                    <%= for section <- sections do %>
                      <li class="text-sm text-base-content/50 flex items-center gap-1.5">
                        <span class="w-1 h-1 rounded-full bg-base-content/20 shrink-0"></span>
                        {section}
                      </li>
                    <% end %>
                  </ul>
                </div>
              <% end %>
            </div>

            <%!-- Frontmatter metadata --%>
            <%= if fm = @skill.parsed_data["frontmatter"] do %>
              <%= if map_size(fm) > 0 do %>
                <div class="mt-6 pt-5 border-t border-base-content/5">
                  <h3 class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30 mb-2.5">
                    Frontmatter
                  </h3>
                  <div class="grid grid-cols-2 md:grid-cols-3 gap-3">
                    <%= for {key, value} <- fm do %>
                      <div class="text-sm">
                        <span class="text-base-content/30 font-mono text-xs">{key}:</span>
                        <span class="text-base-content/60 ml-1">
                          {truncate(to_string(value), 60)}
                        </span>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>
            <% end %>
          <% else %>
            <div class="flex flex-col items-center text-center py-8 px-6">
              <span class="size-10 rounded-xl bg-base-content/5 flex items-center justify-center mb-3">
                <.icon name="hero-magnifying-glass" class="size-5 text-base-content/20" />
              </span>
              <p class="text-sm text-base-content/35">
                No parsed analysis available. This skill may have been uploaded before the parser was implemented.
              </p>
              <p class="text-xs text-base-content/25 mt-1">
                Re-upload the skill to generate parsed analysis.
              </p>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Raw Content --%>
      <div id="raw-content" class="glass-panel overflow-hidden">
        <div class="px-5 py-3.5 border-b border-base-content/5 flex items-center justify-between">
          <h2 class="text-sm font-semibold flex items-center gap-2">
            <.icon name="hero-code-bracket-micro" class="size-4 text-accent" /> Raw Content
          </h2>
          <span class="text-xs text-base-content/25">{String.length(@skill.raw_content)} chars</span>
        </div>
        <div class="p-5 max-h-[28rem] overflow-y-auto">
          <pre class="text-[13px] leading-relaxed font-mono text-base-content/60 whitespace-pre-wrap">{@skill.raw_content}</pre>
        </div>
      </div>
    </div>
    """
  end

  # -- Template helpers --

  defp has_parsed_data?(skill) do
    skill.parsed_data && skill.parsed_data != %{} &&
      (get_parsed_list(skill, "mentioned_tools") != nil ||
         get_parsed_list(skill, "mentioned_frameworks") != nil ||
         get_parsed_list(skill, "mentioned_dependencies") != nil ||
         get_parsed_list(skill, "sections") != nil)
  end

  defp get_parsed_list(skill, key) do
    case skill.parsed_data[key] do
      list when is_list(list) and list != [] -> list
      _ -> nil
    end
  end

  defp format_tool_name(tool) do
    tool
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp tool_color("web_search"), do: "bg-blue-500/10 text-blue-400"
  defp tool_color("file_write"), do: "bg-green-500/10 text-green-400"
  defp tool_color("file_read"), do: "bg-emerald-500/10 text-emerald-400"
  defp tool_color("browser"), do: "bg-purple-500/10 text-purple-400"
  defp tool_color("cli_execution"), do: "bg-orange-500/10 text-orange-400"
  defp tool_color("code_execution"), do: "bg-amber-500/10 text-amber-400"
  defp tool_color(_), do: "bg-primary/10 text-primary"

  defp truncate(str, max_length) do
    if String.length(str) > max_length do
      String.slice(str, 0, max_length) <> "..."
    else
      str
    end
  end
end
