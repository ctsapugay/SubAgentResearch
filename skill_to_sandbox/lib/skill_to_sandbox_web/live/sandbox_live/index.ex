defmodule SkillToSandboxWeb.SandboxLive.Index do
  @moduledoc """
  Lists all sandbox containers with real-time status updates,
  container info, and action buttons (stop, destroy).

  Subscribes to `"sandboxes:updates"` PubSub topic for global
  status change broadcasts from Sandbox Monitor processes.
  """
  use SkillToSandboxWeb, :live_view

  alias SkillToSandbox.Sandboxes
  alias SkillToSandbox.Sandbox.Monitor

  @impl true
  def mount(_params, _session, socket) do
    sandboxes = Sandboxes.list_sandboxes()

    # Subscribe for real-time updates across all sandboxes
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SkillToSandbox.PubSub, "sandboxes:updates")
    end

    socket =
      socket
      |> assign(:page_title, "Sandboxes")
      |> assign(:sandboxes_empty?, sandboxes == [])
      |> stream(:sandboxes, sandboxes)

    {:ok, socket}
  end

  # -- PubSub handler: real-time sandbox status changes --

  @impl true
  def handle_info({:sandbox_status_change, sandbox_id, _new_status}, socket) do
    # Reload the changed sandbox and re-insert into the stream
    sandbox = Sandboxes.get_sandbox!(sandbox_id)
    {:noreply, stream_insert(socket, :sandboxes, sandbox)}
  rescue
    Ecto.NoResultsError ->
      {:noreply, socket}
  end

  # -- Container action events --

  @impl true
  def handle_event("stop_sandbox", %{"id" => id_str}, socket) do
    sandbox_id = String.to_integer(id_str)
    sandbox = Sandboxes.get_sandbox!(sandbox_id)

    result =
      if Monitor.alive?(sandbox_id) do
        Monitor.stop_container(sandbox_id)
      else
        SkillToSandbox.Sandbox.Docker.stop_container(sandbox.container_id)
      end

    case result do
      {:ok, _} ->
        updated = Sandboxes.get_sandbox!(sandbox_id)
        {:ok, _} = Sandboxes.update_sandbox(updated, %{status: "stopped"})
        refreshed = Sandboxes.get_sandbox!(sandbox_id)

        {:noreply,
         socket
         |> stream_insert(:sandboxes, refreshed)
         |> put_flash(:info, "Container stopped.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to stop: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("destroy_sandbox", %{"id" => id_str}, socket) do
    sandbox_id = String.to_integer(id_str)
    sandbox = Sandboxes.get_sandbox!(sandbox_id)

    if Monitor.alive?(sandbox_id) do
      Monitor.destroy_container(sandbox_id)
    else
      SkillToSandbox.Sandbox.Docker.remove_container(sandbox.container_id)
    end

    updated = Sandboxes.get_sandbox!(sandbox_id)
    {:ok, _} = Sandboxes.update_sandbox(updated, %{status: "stopped"})
    refreshed = Sandboxes.get_sandbox!(sandbox_id)

    {:noreply,
     socket
     |> stream_insert(:sandboxes, refreshed)
     |> put_flash(:info, "Container destroyed.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <a href="/" class="back-btn">
          <.icon name="hero-arrow-left-micro" class="size-3.5" /> Dashboard
        </a>

        <div>
          <h1 class="text-2xl font-semibold tracking-tight">Sandboxes</h1>
          <p class="text-sm text-base-content/45 mt-0.5">
            Docker containers running skill environments
          </p>
        </div>

        <div id="sandboxes-table" phx-update="stream">
          <%!-- Empty state: shown only when this is the sole child --%>
          <div class={[
            "glass-panel",
            if(@sandboxes_empty?, do: "", else: "hidden")
          ]}>
            <div class="flex flex-col items-center text-center py-16 px-6">
              <span class="size-14 rounded-2xl bg-base-content/5 flex items-center justify-center mb-4">
                <.icon name="hero-server" class="size-7 text-base-content/20" />
              </span>
              <h3 class="text-base font-semibold text-base-content">No sandboxes yet</h3>
              <p class="text-sm text-base-content/45 mt-1 max-w-sm">
                Sandboxes are created when you run the pipeline on a skill.
              </p>
              <a href="/skills" class="btn btn-primary btn-sm mt-5 shadow-lg shadow-primary/20">
                View Skills
              </a>
            </div>
          </div>

          <%!-- Sandbox cards --%>
          <div
            :for={{id, sandbox} <- @streams.sandboxes}
            id={id}
            class="glass-panel glass-panel-hover p-5 mb-4"
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-4 min-w-0">
                <%!-- Status icon --%>
                <span class={[
                  "size-10 rounded-xl flex items-center justify-center shrink-0",
                  status_icon_bg(sandbox.status)
                ]}>
                  <.icon
                    name={status_icon_name(sandbox.status)}
                    class={["size-5", status_icon_color(sandbox.status)]}
                  />
                </span>

                <div class="min-w-0">
                  <div class="flex items-center gap-2">
                    <a
                      href={"/sandboxes/#{sandbox.id}"}
                      class="text-sm font-semibold text-base-content hover:text-primary transition-colors"
                    >
                      Sandbox #{sandbox.id}
                    </a>
                    <span class={[
                      "inline-flex items-center gap-1 text-[10px] font-semibold px-2 py-0.5 rounded-full uppercase tracking-wide",
                      status_badge_class(sandbox.status)
                    ]}>
                      <span class={["size-1.5 rounded-full", status_dot(sandbox.status)]} />
                      {sandbox.status}
                    </span>
                  </div>
                  <div class="flex items-center gap-3 mt-1">
                    <%= if sandbox.sandbox_spec && sandbox.sandbox_spec.skill do %>
                      <a
                        href={"/skills/#{sandbox.sandbox_spec.skill.id}"}
                        class="text-xs text-primary/60 hover:text-primary transition-colors"
                      >
                        {sandbox.sandbox_spec.skill.name}
                      </a>
                      <span class="text-base-content/10">|</span>
                    <% end %>
                    <span class="text-xs font-mono text-base-content/30">
                      {truncate_id(sandbox.container_id)}
                    </span>
                    <span class="text-base-content/10">|</span>
                    <span class="text-xs text-base-content/30">
                      {Calendar.strftime(sandbox.inserted_at, "%b %d, %Y %H:%M")}
                    </span>
                  </div>
                </div>
              </div>

              <%!-- Actions --%>
              <div class="flex items-center gap-2 shrink-0">
                <a
                  href={"/sandboxes/#{sandbox.id}"}
                  class="btn btn-outline btn-xs border-base-content/10 text-base-content/60 hover:bg-base-content/5 hover:border-base-content/20 transition-all"
                >
                  <.icon name="hero-eye-micro" class="size-3.5" /> Monitor
                </a>
                <%= if sandbox.status == "running" do %>
                  <button
                    phx-click="stop_sandbox"
                    phx-value-id={sandbox.id}
                    class="btn btn-outline btn-xs border-warning/20 text-warning/70 hover:bg-warning/10 hover:border-warning/30 transition-all"
                  >
                    <.icon name="hero-stop-micro" class="size-3.5" /> Stop
                  </button>
                <% end %>
                <button
                  phx-click="destroy_sandbox"
                  phx-value-id={sandbox.id}
                  data-confirm="Destroy this container? This cannot be undone."
                  class="btn btn-outline btn-xs border-error/20 text-error/60 hover:bg-error/10 hover:border-error/30 transition-all"
                >
                  <.icon name="hero-trash-micro" class="size-3.5" />
                </button>
              </div>
            </div>
          </div>
        </div>
    </div>
    """
  end

  # -- Private helpers --

  defp status_dot("running"), do: "bg-success"
  defp status_dot("building"), do: "bg-warning"
  defp status_dot("stopped"), do: "bg-base-content/30"
  defp status_dot("error"), do: "bg-error"
  defp status_dot(_), do: "bg-base-content/20"

  defp status_badge_class("running"), do: "bg-success/10 text-success"
  defp status_badge_class("building"), do: "bg-warning/10 text-warning"
  defp status_badge_class("stopped"), do: "bg-base-content/5 text-base-content/35"
  defp status_badge_class("error"), do: "bg-error/10 text-error"
  defp status_badge_class(_), do: "bg-base-content/5 text-base-content/35"

  defp status_icon_bg("running"), do: "bg-success/15"
  defp status_icon_bg("building"), do: "bg-warning/15"
  defp status_icon_bg("stopped"), do: "bg-base-content/5"
  defp status_icon_bg("error"), do: "bg-error/15"
  defp status_icon_bg(_), do: "bg-base-content/5"

  defp status_icon_name("running"), do: "hero-play"
  defp status_icon_name("building"), do: "hero-arrow-path"
  defp status_icon_name("stopped"), do: "hero-stop"
  defp status_icon_name("error"), do: "hero-exclamation-triangle"
  defp status_icon_name(_), do: "hero-question-mark-circle"

  defp status_icon_color("running"), do: "text-success"
  defp status_icon_color("building"), do: "text-warning animate-spin"
  defp status_icon_color("stopped"), do: "text-base-content/25"
  defp status_icon_color("error"), do: "text-error"
  defp status_icon_color(_), do: "text-base-content/25"

  defp truncate_id(nil), do: "--"
  defp truncate_id(id) when byte_size(id) > 12, do: String.slice(id, 0, 12) <> "..."
  defp truncate_id(id), do: id
end
