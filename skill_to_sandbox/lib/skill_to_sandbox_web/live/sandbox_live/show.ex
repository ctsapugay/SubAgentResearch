defmodule SkillToSandboxWeb.SandboxLive.Show do
  @moduledoc """
  Single sandbox monitor view. Stub for Phase 1 -- will be fully
  implemented in Phase 6 with live log streaming and container controls.
  """
  use SkillToSandboxWeb, :live_view

  alias SkillToSandbox.Sandboxes

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    sandbox = Sandboxes.get_sandbox!(id)

    socket =
      socket
      |> assign(:page_title, "Sandbox ##{sandbox.id}")
      |> assign(:sandbox, sandbox)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <a href="/sandboxes" class="back-btn">
        <.icon name="hero-arrow-left-micro" class="size-3.5" /> Sandboxes
      </a>

      <h1 class="text-2xl font-semibold tracking-tight">Sandbox #{@sandbox.id}</h1>

      <%!-- Container Info --%>
      <div class="glass-panel overflow-hidden">
        <div class="px-5 py-3.5 border-b border-base-content/5">
          <h2 class="text-sm font-semibold text-base-content">Container Info</h2>
        </div>
        <div class="p-5 grid grid-cols-2 lg:grid-cols-4 gap-4">
          <div>
            <span class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30 block mb-1">Status</span>
            <span class="inline-flex items-center gap-1.5 text-sm font-medium">
              <span class={["size-1.5 rounded-full", status_dot(@sandbox.status)]} />
              {@sandbox.status}
            </span>
          </div>
          <div>
            <span class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30 block mb-1">Container</span>
            <span class="font-mono text-sm text-base-content/60">{@sandbox.container_id || "Not assigned"}</span>
          </div>
          <div>
            <span class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30 block mb-1">Image</span>
            <span class="font-mono text-sm text-base-content/60">{@sandbox.image_id || "Not assigned"}</span>
          </div>
          <div>
            <span class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30 block mb-1">Created</span>
            <span class="text-sm text-base-content/60">
              {Calendar.strftime(@sandbox.inserted_at, "%b %d, %Y %H:%M")}
            </span>
          </div>
        </div>
      </div>

      <%!-- Log Viewer Stub --%>
      <div class="glass-panel overflow-hidden">
        <div class="px-5 py-3.5 border-b border-base-content/5">
          <h2 class="text-sm font-semibold flex items-center gap-2 text-base-content">
            <.icon name="hero-command-line-micro" class="size-4 text-accent" /> Logs
          </h2>
        </div>
        <div class="h-56 flex items-center justify-center">
          <p class="text-sm text-base-content/25">Live log streaming available in Phase 6</p>
        </div>
      </div>

      <%!-- Controls Stub --%>
      <div class="glass-panel p-5">
        <h2 class="text-sm font-semibold text-base-content mb-3">Controls</h2>
        <div class="flex gap-2">
          <button class="btn btn-outline btn-sm border-base-content/10 text-base-content/50" disabled>Stop</button>
          <button class="btn btn-outline btn-sm border-base-content/10 text-base-content/50" disabled>Restart</button>
          <button class="btn btn-outline btn-sm border-error/20 text-error/50" disabled>Destroy</button>
        </div>
        <p class="text-xs text-base-content/25 mt-2">Container controls available in Phase 6</p>
      </div>
    </div>
    """
  end

  defp status_dot("running"), do: "bg-success"
  defp status_dot("building"), do: "bg-warning"
  defp status_dot("stopped"), do: "bg-base-content/30"
  defp status_dot("error"), do: "bg-error"
  defp status_dot(_), do: "bg-base-content/20"
end
