defmodule SkillToSandboxWeb.DashboardLive do
  @moduledoc """
  Dashboard overview page showing system status and counts.
  """
  use SkillToSandboxWeb, :live_view

  alias SkillToSandbox.Skills
  alias SkillToSandbox.Sandboxes
  alias SkillToSandbox.Pipelines
  alias SkillToSandbox.Sandbox.DockerCheck

  @impl true
  def mount(_params, _session, socket) do
    docker_available = DockerCheck.available?()
    docker_version = if docker_available, do: DockerCheck.version(), else: nil

    socket =
      socket
      |> assign(:page_title, "Dashboard")
      |> assign(:skill_count, Skills.count_skills())
      |> assign(:sandbox_count, Sandboxes.count_sandboxes())
      |> assign(:running_sandbox_count, Sandboxes.count_sandboxes_by_status("running"))
      |> assign(:active_pipeline_count, Pipelines.count_active_runs())
      |> assign(:docker_available, docker_available)
      |> assign(:docker_version, docker_version)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <%!-- Hero --%>
      <div class="relative overflow-hidden glass-panel p-8 sm:p-10 glow-primary">
        <div class="relative z-10">
          <h1 class="text-3xl font-bold tracking-tight text-base-content">
            Welcome back
          </h1>
          <p class="text-base text-base-content/50 mt-2 max-w-lg leading-relaxed">
            Upload a skill definition, run the analysis pipeline, and spin up
            a sandboxed Docker environment -- all from here.
          </p>
          <div class="flex gap-3 mt-6">
            <a href="/skills/new" class="btn btn-primary btn-sm shadow-lg shadow-primary/25">
              <.icon name="hero-plus-micro" class="size-4" /> Upload Skill
            </a>
            <a href="/skills" class="btn btn-outline btn-sm border-base-content/15 text-base-content/70 hover:bg-base-content/5 hover:border-base-content/25">
              <.icon name="hero-folder-open-micro" class="size-4" /> Browse Skills
            </a>
          </div>
        </div>
        <%!-- Decorative glowing orbs --%>
        <div class="absolute -top-16 -right-16 size-48 rounded-full bg-primary/8 blur-2xl" />
        <div class="absolute -bottom-10 right-16 size-32 rounded-full bg-accent/8 blur-2xl" />
        <div class="absolute top-8 right-32 size-16 rounded-full bg-secondary/10 blur-xl" />
      </div>

      <%!-- Stats Grid --%>
      <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <a href="/skills" class="glass-panel glass-panel-hover p-5 block group">
          <div class="flex items-center justify-between mb-4">
            <span class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30">Skills</span>
            <span class="size-9 rounded-xl bg-primary/10 flex items-center justify-center group-hover:bg-primary/20 transition-colors">
              <.icon name="hero-document-text-micro" class="size-4 text-primary" />
            </span>
          </div>
          <p class="text-3xl font-bold stat-value text-base-content">{@skill_count}</p>
          <p class="text-xs text-base-content/35 mt-1.5">uploaded</p>
        </a>

        <div class="glass-panel p-5">
          <div class="flex items-center justify-between mb-4">
            <span class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30">Pipelines</span>
            <span class="size-9 rounded-xl bg-secondary/10 flex items-center justify-center">
              <.icon name="hero-arrow-path-micro" class="size-4 text-secondary" />
            </span>
          </div>
          <p class="text-3xl font-bold stat-value text-base-content">{@active_pipeline_count}</p>
          <p class="text-xs text-base-content/35 mt-1.5">active</p>
        </div>

        <a href="/sandboxes" class="glass-panel glass-panel-hover p-5 block group">
          <div class="flex items-center justify-between mb-4">
            <span class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30">Sandboxes</span>
            <span class="size-9 rounded-xl bg-accent/10 flex items-center justify-center group-hover:bg-accent/20 transition-colors">
              <.icon name="hero-server-micro" class="size-4 text-accent" />
            </span>
          </div>
          <p class="text-3xl font-bold stat-value text-base-content">{@sandbox_count}</p>
          <p class="text-xs text-base-content/35 mt-1.5">total</p>
        </a>

        <a href="/sandboxes" class="glass-panel glass-panel-hover p-5 block group">
          <div class="flex items-center justify-between mb-4">
            <span class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30">Running</span>
            <span class="size-9 rounded-xl bg-success/10 flex items-center justify-center group-hover:bg-success/20 transition-colors">
              <.icon name="hero-play-micro" class="size-4 text-success" />
            </span>
          </div>
          <p class="text-3xl font-bold stat-value text-base-content">{@running_sandbox_count}</p>
          <p class="text-xs text-base-content/35 mt-1.5">containers</p>
        </a>
      </div>

      <%!-- Docker + How it works --%>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <%!-- Docker Status --%>
        <div class={[
          "glass-panel p-5 flex items-start gap-4",
          if(@docker_available, do: "glow-accent", else: "")
        ]}>
          <span class={[
            "size-10 rounded-xl flex items-center justify-center shrink-0",
            if(@docker_available, do: "bg-success/15", else: "bg-warning/15")
          ]}>
            <.icon
              name={if(@docker_available, do: "hero-check-circle", else: "hero-exclamation-triangle")}
              class={["size-5", if(@docker_available, do: "text-success", else: "text-warning")]}
            />
          </span>
          <div>
            <h3 class="text-sm font-semibold text-base-content">
              Docker {if @docker_available, do: "Connected", else: "Unavailable"}
            </h3>
            <p class="text-sm text-base-content/45 mt-0.5">
              <%= if @docker_available do %>
                Engine v{@docker_version} is running and ready to build sandboxes.
              <% else %>
                Start Docker Desktop to enable sandbox building.
              <% end %>
            </p>
          </div>
        </div>

        <%!-- How it works --%>
        <div class="glass-panel p-5">
          <h3 class="text-sm font-semibold text-base-content mb-3">How it works</h3>
          <ol class="space-y-2.5">
            <li class="flex items-start gap-3">
              <span class="size-6 rounded-full bg-primary/15 flex items-center justify-center shrink-0 mt-0.5 text-[11px] font-bold text-primary">1</span>
              <span class="text-sm text-base-content/55">Upload a SKILL.md definition file</span>
            </li>
            <li class="flex items-start gap-3">
              <span class="size-6 rounded-full bg-primary/15 flex items-center justify-center shrink-0 mt-0.5 text-[11px] font-bold text-primary">2</span>
              <span class="text-sm text-base-content/55">LLM analyzes it into a sandbox spec</span>
            </li>
            <li class="flex items-start gap-3">
              <span class="size-6 rounded-full bg-primary/15 flex items-center justify-center shrink-0 mt-0.5 text-[11px] font-bold text-primary">3</span>
              <span class="text-sm text-base-content/55">Review, approve, and build a Docker container</span>
            </li>
          </ol>
        </div>
      </div>
    </div>
    """
  end
end
