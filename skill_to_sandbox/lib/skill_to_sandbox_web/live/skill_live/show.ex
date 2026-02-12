defmodule SkillToSandboxWeb.SkillLive.Show do
  @moduledoc """
  Displays a single skill's details, parsed data, and raw content.
  """
  use SkillToSandboxWeb, :live_view

  alias SkillToSandbox.Skills

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    skill = Skills.get_skill!(id)

    socket =
      socket
      |> assign(:page_title, skill.name)
      |> assign(:skill, skill)

    {:ok, socket}
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
            <a href={@skill.source_url} target="_blank" class="inline-flex items-center gap-1 text-xs text-accent hover:text-accent/80 mt-2 transition-colors">
              <.icon name="hero-arrow-top-right-on-square-micro" class="size-3" /> View on GitHub
            </a>
          <% end %>
        </div>
        <div class="flex gap-2 shrink-0">
          <button class="btn btn-primary btn-sm shadow-lg shadow-primary/20" disabled title="Pipeline not yet implemented">
            <.icon name="hero-play-micro" class="size-4" /> Build Sandbox
          </button>
          <button
            phx-click="delete"
            data-confirm="Are you sure you want to delete this skill?"
            class="btn btn-outline btn-sm border-error/20 text-error/60 hover:bg-error/10 hover:text-error hover:border-error/30"
          >
            <.icon name="hero-trash-micro" class="size-4" />
          </button>
        </div>
      </div>

      <div class="text-xs text-base-content/30">
        Uploaded {Calendar.strftime(@skill.inserted_at, "%B %d, %Y at %H:%M UTC")}
      </div>

      <%!-- Parsed Analysis --%>
      <div class="glass-panel overflow-hidden">
        <div class="px-5 py-3.5 border-b border-base-content/5">
          <h2 class="text-sm font-semibold flex items-center gap-2">
            <.icon name="hero-magnifying-glass-micro" class="size-4 text-accent" /> Parsed Analysis
          </h2>
        </div>
        <div class="p-5">
          <%= if @skill.parsed_data && @skill.parsed_data != %{} do %>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-5">
              <%= if tools = @skill.parsed_data["mentioned_tools"] do %>
                <div>
                  <h3 class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30 mb-2">Detected Tools</h3>
                  <div class="flex flex-wrap gap-1.5">
                    <%= for tool <- tools do %>
                      <span class="text-xs font-medium px-2.5 py-0.5 rounded-full bg-primary/10 text-primary">{tool}</span>
                    <% end %>
                  </div>
                </div>
              <% end %>
              <%= if frameworks = @skill.parsed_data["mentioned_frameworks"] do %>
                <div>
                  <h3 class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30 mb-2">Frameworks</h3>
                  <div class="flex flex-wrap gap-1.5">
                    <%= for fw <- frameworks do %>
                      <span class="text-xs font-medium px-2.5 py-0.5 rounded-full bg-accent/10 text-accent">{fw}</span>
                    <% end %>
                  </div>
                </div>
              <% end %>
              <%= if deps = @skill.parsed_data["mentioned_dependencies"] do %>
                <div>
                  <h3 class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30 mb-2">Dependencies</h3>
                  <div class="flex flex-wrap gap-1.5">
                    <%= for dep <- deps do %>
                      <span class="text-xs font-medium px-2.5 py-0.5 rounded-full bg-secondary/10 text-secondary">{dep}</span>
                    <% end %>
                  </div>
                </div>
              <% end %>
              <%= if sections = @skill.parsed_data["sections"] do %>
                <div>
                  <h3 class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30 mb-2">Sections</h3>
                  <ul class="space-y-0.5">
                    <%= for section <- sections do %>
                      <li class="text-sm text-base-content/50">{section}</li>
                    <% end %>
                  </ul>
                </div>
              <% end %>
            </div>
          <% else %>
            <p class="text-sm text-base-content/35">
              Parsed analysis will be available after the parser is implemented (Phase 2).
            </p>
          <% end %>
        </div>
      </div>

      <%!-- Raw Content --%>
      <div class="glass-panel overflow-hidden">
        <div class="px-5 py-3.5 border-b border-base-content/5">
          <h2 class="text-sm font-semibold flex items-center gap-2">
            <.icon name="hero-code-bracket-micro" class="size-4 text-accent" /> Raw Content
          </h2>
        </div>
        <div class="p-5 max-h-[28rem] overflow-y-auto">
          <pre class="text-[13px] leading-relaxed font-mono text-base-content/60 whitespace-pre-wrap">{@skill.raw_content}</pre>
        </div>
      </div>
    </div>
    """
  end
end
