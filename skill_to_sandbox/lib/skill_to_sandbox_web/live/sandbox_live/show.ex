defmodule SkillToSandboxWeb.SandboxLive.Show do
  @moduledoc """
  Single sandbox monitor view with live log streaming, status updates,
  and container lifecycle controls (stop, restart, destroy).

  Subscribes to `"sandbox:<id>"` PubSub topic for real-time log lines
  and status changes from the Sandbox Monitor GenServer.
  """
  use SkillToSandboxWeb, :live_view

  alias SkillToSandbox.Sandboxes
  alias SkillToSandbox.Analysis
  alias SkillToSandbox.Sandbox.Monitor

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    sandbox = Sandboxes.get_sandbox!(id)

    # Load the associated spec for eval goals
    spec =
      if sandbox.sandbox_spec_id do
        Analysis.get_spec!(sandbox.sandbox_spec_id)
      else
        nil
      end

    # Subscribe to sandbox PubSub topic for real-time updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(SkillToSandbox.PubSub, "sandbox:#{sandbox.id}")

      # Ensure monitor is running if container is running
      ensure_monitor_started(sandbox)
    end

    # Get initial logs from monitor if it's running
    initial_logs =
      if Monitor.alive?(sandbox.id) do
        Monitor.get_logs(sandbox.id)
      else
        []
      end

    socket =
      socket
      |> assign(:page_title, "Sandbox ##{sandbox.id}")
      |> assign(:sandbox, sandbox)
      |> assign(:spec, spec)
      |> assign(:status, sandbox.status)
      |> assign(:logs_count, length(initial_logs))
      |> assign(:monitor_alive, Monitor.alive?(sandbox.id))
      |> assign(:action_in_progress, nil)
      |> stream(:logs, initial_logs |> Enum.with_index() |> Enum.map(fn {line, i} -> %{id: "log-#{i}", text: line} end))

    {:ok, socket}
  end

  # -- PubSub handlers --

  @impl true
  def handle_info({:log_line, line}, socket) do
    log_entry = %{id: "log-#{System.unique_integer([:positive])}", text: line}
    logs_count = socket.assigns.logs_count + 1

    socket =
      socket
      |> stream_insert(:logs, log_entry)
      |> assign(:logs_count, logs_count)

    # Prune old entries if we exceed the max
    # (streams handle this via the DOM, but we track count for display)
    {:noreply, socket}
  end

  def handle_info({:status_change, new_status}, socket) do
    sandbox = Sandboxes.get_sandbox!(socket.assigns.sandbox.id)

    socket =
      socket
      |> assign(:sandbox, sandbox)
      |> assign(:status, new_status)
      |> assign(:monitor_alive, Monitor.alive?(sandbox.id))

    {:noreply, socket}
  end

  # -- Container control events --

  @impl true
  def handle_event("stop_container", _params, socket) do
    sandbox = socket.assigns.sandbox
    socket = assign(socket, :action_in_progress, :stopping)

    if Monitor.alive?(sandbox.id) do
      case Monitor.stop_container(sandbox.id) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:action_in_progress, nil)
           |> assign(:status, "stopped")
           |> put_flash(:info, "Container stopped successfully.")}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:action_in_progress, nil)
           |> put_flash(:error, "Failed to stop container: #{inspect(reason)}")}
      end
    else
      # No monitor — call Docker directly
      case SkillToSandbox.Sandbox.Docker.stop_container(sandbox.container_id) do
        {:ok, _} ->
          updated_sandbox = Sandboxes.get_sandbox!(sandbox.id)
          {:ok, _} = Sandboxes.update_sandbox(updated_sandbox, %{status: "stopped"})

          {:noreply,
           socket
           |> assign(:action_in_progress, nil)
           |> assign(:status, "stopped")
           |> assign(:sandbox, Sandboxes.get_sandbox!(sandbox.id))
           |> put_flash(:info, "Container stopped successfully.")}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:action_in_progress, nil)
           |> put_flash(:error, "Failed to stop container: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def handle_event("restart_container", _params, socket) do
    sandbox = socket.assigns.sandbox
    socket = assign(socket, :action_in_progress, :restarting)

    if Monitor.alive?(sandbox.id) do
      case Monitor.restart_container(sandbox.id) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:action_in_progress, nil)
           |> assign(:status, "running")
           |> stream(:logs, [], reset: true)
           |> assign(:logs_count, 0)
           |> put_flash(:info, "Container restarted successfully.")}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:action_in_progress, nil)
           |> put_flash(:error, "Failed to restart container: #{inspect(reason)}")}
      end
    else
      case SkillToSandbox.Sandbox.Docker.restart_container(sandbox.container_id) do
        {:ok, _} ->
          # Start a new monitor
          ensure_monitor_started(sandbox)
          updated_sandbox = Sandboxes.get_sandbox!(sandbox.id)
          {:ok, _} = Sandboxes.update_sandbox(updated_sandbox, %{status: "running"})

          {:noreply,
           socket
           |> assign(:action_in_progress, nil)
           |> assign(:status, "running")
           |> assign(:sandbox, Sandboxes.get_sandbox!(sandbox.id))
           |> assign(:monitor_alive, Monitor.alive?(sandbox.id))
           |> stream(:logs, [], reset: true)
           |> assign(:logs_count, 0)
           |> put_flash(:info, "Container restarted successfully.")}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:action_in_progress, nil)
           |> put_flash(:error, "Failed to restart container: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def handle_event("destroy_container", _params, socket) do
    sandbox = socket.assigns.sandbox
    socket = assign(socket, :action_in_progress, :destroying)

    if Monitor.alive?(sandbox.id) do
      Monitor.destroy_container(sandbox.id)
    else
      SkillToSandbox.Sandbox.Docker.remove_container(sandbox.container_id)
    end

    updated_sandbox = Sandboxes.get_sandbox!(sandbox.id)
    {:ok, _} = Sandboxes.update_sandbox(updated_sandbox, %{status: "stopped"})

    {:noreply,
     socket
     |> assign(:action_in_progress, nil)
     |> assign(:status, "stopped")
     |> assign(:sandbox, Sandboxes.get_sandbox!(sandbox.id))
     |> assign(:monitor_alive, false)
     |> put_flash(:info, "Container destroyed.")}
  end

  # -- Render --

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <a href="/sandboxes" class="back-btn">
          <.icon name="hero-arrow-left-micro" class="size-3.5" /> Sandboxes
        </a>

        <div class="flex items-start justify-between">
          <div>
            <h1 class="text-2xl font-semibold tracking-tight">Sandbox #{@sandbox.id}</h1>
            <p class="text-sm text-base-content/45 mt-0.5">
              <%= if @sandbox.sandbox_spec && @sandbox.sandbox_spec.skill do %>
                Skill: {@sandbox.sandbox_spec.skill.name}
              <% else %>
                Container monitor
              <% end %>
            </p>
          </div>
          <span class={[
            "inline-flex items-center gap-2 text-sm font-medium px-3 py-1.5 rounded-full",
            status_badge_class(@status)
          ]}>
            <span class={["size-2 rounded-full", status_dot(@status)]} />
            {@status}
          </span>
        </div>

        <%!-- Container Info --%>
        <div class="glass-panel overflow-hidden">
          <div class="px-5 py-3.5 border-b border-base-content/5">
            <h2 class="text-sm font-semibold text-base-content flex items-center gap-2">
              <.icon name="hero-server-micro" class="size-4 text-accent" /> Container Info
            </h2>
          </div>
          <div class="p-5 grid grid-cols-2 lg:grid-cols-4 gap-4">
            <div>
              <span class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30 block mb-1">
                Container ID
              </span>
              <span class="font-mono text-sm text-base-content/60">
                {truncate_id(@sandbox.container_id)}
              </span>
            </div>
            <div>
              <span class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30 block mb-1">
                Image
              </span>
              <span class="font-mono text-sm text-base-content/60">
                {@sandbox.image_id || "N/A"}
              </span>
            </div>
            <div>
              <span class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30 block mb-1">
                Uptime
              </span>
              <span class="text-sm text-base-content/60">
                {uptime(@sandbox.inserted_at)}
              </span>
            </div>
            <div>
              <span class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30 block mb-1">
                Monitor
              </span>
              <span class={[
                "inline-flex items-center gap-1.5 text-sm font-medium",
                if(@monitor_alive, do: "text-success", else: "text-base-content/30")
              ]}>
                <span class={[
                  "size-1.5 rounded-full",
                  if(@monitor_alive, do: "bg-success", else: "bg-base-content/20")
                ]} />
                {if @monitor_alive, do: "Active", else: "Inactive"}
              </span>
            </div>
          </div>
        </div>

        <%!-- Controls --%>
        <div class="glass-panel p-5">
          <div class="flex items-center justify-between">
            <h2 class="text-sm font-semibold text-base-content flex items-center gap-2">
              <.icon name="hero-cog-6-tooth-micro" class="size-4 text-base-content/40" /> Controls
            </h2>
            <div class="flex gap-2">
              <button
                id="stop-container-btn"
                phx-click="stop_container"
                disabled={@status != "running" || @action_in_progress != nil}
                class={[
                  "btn btn-outline btn-sm border-base-content/15 text-base-content/70 hover:bg-base-content/5 hover:border-base-content/25 transition-all",
                  (@status != "running" || @action_in_progress != nil) && "opacity-40 cursor-not-allowed"
                ]}
              >
                <%= if @action_in_progress == :stopping do %>
                  <.icon name="hero-arrow-path" class="size-4 animate-spin" /> Stopping...
                <% else %>
                  <.icon name="hero-stop-micro" class="size-4" /> Stop
                <% end %>
              </button>
              <button
                id="restart-container-btn"
                phx-click="restart_container"
                disabled={@status not in ["running", "stopped"] || @action_in_progress != nil}
                class={[
                  "btn btn-outline btn-sm border-base-content/15 text-base-content/70 hover:bg-base-content/5 hover:border-base-content/25 transition-all",
                  (@status not in ["running", "stopped"] || @action_in_progress != nil) && "opacity-40 cursor-not-allowed"
                ]}
              >
                <%= if @action_in_progress == :restarting do %>
                  <.icon name="hero-arrow-path" class="size-4 animate-spin" /> Restarting...
                <% else %>
                  <.icon name="hero-arrow-path-micro" class="size-4" /> Restart
                <% end %>
              </button>
              <button
                id="destroy-container-btn"
                phx-click="destroy_container"
                disabled={@action_in_progress != nil}
                data-confirm="Are you sure you want to destroy this container? This cannot be undone."
                class={[
                  "btn btn-outline btn-sm border-error/30 text-error/70 hover:bg-error/10 hover:border-error/40 transition-all",
                  @action_in_progress != nil && "opacity-40 cursor-not-allowed"
                ]}
              >
                <%= if @action_in_progress == :destroying do %>
                  <.icon name="hero-arrow-path" class="size-4 animate-spin" /> Destroying...
                <% else %>
                  <.icon name="hero-trash-micro" class="size-4" /> Destroy
                <% end %>
              </button>
            </div>
          </div>
        </div>

        <%!-- Log Viewer --%>
        <div class="glass-panel overflow-hidden">
          <div class="px-5 py-3.5 border-b border-base-content/5 flex items-center justify-between">
            <h2 class="text-sm font-semibold flex items-center gap-2 text-base-content">
              <.icon name="hero-command-line-micro" class="size-4 text-accent" /> Logs
            </h2>
            <div class="flex items-center gap-3">
              <span class="text-[10px] font-mono text-base-content/25">
                {@logs_count} lines
              </span>
              <%= if @status == "running" do %>
                <span class="inline-flex items-center gap-1 text-[10px] font-medium text-success/70">
                  <span class="size-1.5 rounded-full bg-success animate-pulse" />
                  streaming
                </span>
              <% end %>
            </div>
          </div>
          <div
            id="log-viewer"
            phx-hook="AutoScroll"
            phx-update="stream"
            class="h-96 overflow-y-auto font-mono text-xs leading-relaxed bg-black/20 p-4 space-y-0"
          >
            <div class="hidden only:flex items-center justify-center h-full">
              <p class="text-sm text-base-content/20">
                <%= if @status == "running" do %>
                  Waiting for log output...
                <% else %>
                  No logs available. Container is {@status}.
                <% end %>
              </p>
            </div>
            <div :for={{id, log} <- @streams.logs} id={id} class="py-0.5 text-base-content/60 break-all hover:text-base-content/80 hover:bg-base-content/[0.03] -mx-1 px-1 rounded transition-colors">
              {log.text}
            </div>
          </div>
        </div>

        <%!-- Eval Goals --%>
        <%= if @spec && @spec.eval_goals && @spec.eval_goals != [] do %>
          <div class="glass-panel overflow-hidden">
            <div class="px-5 py-3.5 border-b border-base-content/5">
              <h2 class="text-sm font-semibold flex items-center gap-2 text-base-content">
                <.icon name="hero-clipboard-document-list-micro" class="size-4 text-warning" />
                Evaluation Goals
                <span class="text-[10px] font-normal text-base-content/30 ml-1">
                  ({length(@spec.eval_goals)})
                </span>
              </h2>
            </div>
            <div class="p-5">
              <div class="space-y-2">
                <%= for {goal, idx} <- Enum.with_index(@spec.eval_goals) do %>
                  <div class="flex items-start gap-3 group">
                    <span class="text-[10px] font-mono text-base-content/20 mt-1 w-5 text-right shrink-0">
                      {idx + 1}.
                    </span>
                    <div class="flex items-start gap-2 flex-1">
                      <span class={[
                        "text-[10px] font-bold mt-0.5 px-1.5 py-0.5 rounded shrink-0",
                        goal_difficulty_class(goal)
                      ]}>
                        {goal_difficulty_label(goal)}
                      </span>
                      <span class="text-sm text-base-content/60">{goal}</span>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- Error Info --%>
        <%= if @sandbox.error_message do %>
          <div class="glass-panel p-5">
            <h2 class="text-sm font-semibold text-error flex items-center gap-2 mb-2">
              <.icon name="hero-exclamation-triangle-micro" class="size-4" /> Error Details
            </h2>
            <pre class="text-xs font-mono text-error/60 whitespace-pre-wrap bg-error/5 rounded-lg p-3 border border-error/10">
              {@sandbox.error_message}
            </pre>
          </div>
        <% end %>
    </div>
    """
  end

  # -- Private helpers --

  defp ensure_monitor_started(sandbox) do
    if sandbox.status == "running" && sandbox.container_id && !Monitor.alive?(sandbox.id) do
      DynamicSupervisor.start_child(
        SkillToSandbox.SandboxMonitorSupervisor,
        {Monitor, %{sandbox_id: sandbox.id, container_id: sandbox.container_id}}
      )
    end
  end

  defp uptime(inserted_at) do
    diff = DateTime.diff(DateTime.utc_now(), inserted_at, :second)

    cond do
      diff < 60 -> "#{diff}s"
      diff < 3600 -> "#{div(diff, 60)}m #{rem(diff, 60)}s"
      diff < 86400 -> "#{div(diff, 3600)}h #{div(rem(diff, 3600), 60)}m"
      true -> "#{div(diff, 86400)}d #{div(rem(diff, 86400), 3600)}h"
    end
  end

  defp truncate_id(nil), do: "N/A"
  defp truncate_id(id) when byte_size(id) > 12, do: String.slice(id, 0, 12) <> "..."
  defp truncate_id(id), do: id

  defp status_dot("running"), do: "bg-success"
  defp status_dot("building"), do: "bg-warning"
  defp status_dot("stopped"), do: "bg-base-content/30"
  defp status_dot("error"), do: "bg-error"
  defp status_dot(_), do: "bg-base-content/20"

  defp status_badge_class("running"), do: "bg-success/10 text-success border border-success/20"
  defp status_badge_class("building"), do: "bg-warning/10 text-warning border border-warning/20"
  defp status_badge_class("stopped"), do: "bg-base-content/5 text-base-content/40 border border-base-content/10"
  defp status_badge_class("error"), do: "bg-error/10 text-error border border-error/20"
  defp status_badge_class(_), do: "bg-base-content/5 text-base-content/40 border border-base-content/10"

  defp goal_difficulty_class(goal) do
    cond do
      String.starts_with?(goal, "Easy") -> "bg-success/15 text-success"
      String.starts_with?(goal, "Medium") -> "bg-warning/15 text-warning"
      String.starts_with?(goal, "Hard") -> "bg-error/15 text-error"
      true -> "bg-base-content/10 text-base-content/40"
    end
  end

  defp goal_difficulty_label(goal) do
    cond do
      String.starts_with?(goal, "Easy") -> "EASY"
      String.starts_with?(goal, "Medium") -> "MED"
      String.starts_with?(goal, "Hard") -> "HARD"
      true -> "?"
    end
  end
end
