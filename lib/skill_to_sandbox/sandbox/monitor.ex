defmodule SkillToSandbox.Sandbox.Monitor do
  @moduledoc """
  GenServer that monitors a running sandbox container.

  Responsibilities:
  - Streams container logs via a Docker `Port` and broadcasts lines via PubSub
  - Polls container health every 5 seconds via `docker inspect`
  - Updates the sandbox DB record on status changes
  - Provides a client API for container lifecycle operations (stop, restart, destroy)

  Each monitor process is registered in `SkillToSandbox.SandboxRegistry`
  by sandbox ID, allowing lookup from LiveViews and other callers.
  """
  use GenServer

  require Logger

  alias SkillToSandbox.Sandbox.Docker
  alias SkillToSandbox.Sandboxes

  @health_interval_ms 5_000
  @max_log_buffer 500

  defstruct [
    :sandbox_id,
    :container_id,
    :log_port,
    :status,
    log_buffer: []
  ]

  # -------------------------------------------------------------------
  # Client API
  # -------------------------------------------------------------------

  def start_link(%{sandbox_id: sandbox_id} = args) do
    GenServer.start_link(__MODULE__, args, name: via_tuple(sandbox_id))
  end

  @doc "Stop the monitored container."
  def stop_container(sandbox_id) do
    GenServer.call(via_tuple(sandbox_id), :stop_container, 30_000)
  end

  @doc "Restart the monitored container."
  def restart_container(sandbox_id) do
    GenServer.call(via_tuple(sandbox_id), :restart_container, 30_000)
  end

  @doc "Destroy (remove) the monitored container and stop the monitor."
  def destroy_container(sandbox_id) do
    GenServer.call(via_tuple(sandbox_id), :destroy_container, 30_000)
  end

  @doc "Get the current log buffer (last #{@max_log_buffer} lines)."
  def get_logs(sandbox_id) do
    GenServer.call(via_tuple(sandbox_id), :get_logs)
  end

  @doc "Get the current status of the monitored container."
  def get_status(sandbox_id) do
    GenServer.call(via_tuple(sandbox_id), :get_status)
  end

  @doc "Check if a monitor process is alive for the given sandbox_id."
  def alive?(sandbox_id) do
    case Registry.lookup(SkillToSandbox.SandboxRegistry, sandbox_id) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  defp via_tuple(sandbox_id) do
    {:via, Registry, {SkillToSandbox.SandboxRegistry, sandbox_id}}
  end

  # -------------------------------------------------------------------
  # Callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(%{sandbox_id: sandbox_id, container_id: container_id}) do
    Logger.info("[Monitor] Starting monitor for sandbox ##{sandbox_id} (#{truncate_id(container_id)})")

    state = %__MODULE__{
      sandbox_id: sandbox_id,
      container_id: container_id,
      status: "running",
      log_buffer: []
    }

    # Start log streaming
    state = start_log_streaming(state)

    # Schedule the first health check
    Process.send_after(self(), :health_check, @health_interval_ms)

    {:ok, state}
  end

  # -- Log port messages --

  @impl true
  def handle_info({port, {:data, data}}, %{log_port: port} = state) do
    lines =
      data
      |> String.split("\n")
      |> Enum.reject(&(&1 == ""))

    # Broadcast each line via PubSub
    for line <- lines do
      Phoenix.PubSub.broadcast(
        SkillToSandbox.PubSub,
        "sandbox:#{state.sandbox_id}",
        {:log_line, line}
      )
    end

    # Update buffer (keep last @max_log_buffer lines)
    new_buffer = (state.log_buffer ++ lines) |> Enum.take(-@max_log_buffer)

    {:noreply, %{state | log_buffer: new_buffer}}
  end

  # Port closed (container stopped or logs ended)
  def handle_info({port, {:exit_status, exit_code}}, %{log_port: port} = state) do
    Logger.info(
      "[Monitor] Log port closed for sandbox ##{state.sandbox_id} (exit: #{exit_code})"
    )

    {:noreply, %{state | log_port: nil}}
  end

  # Periodic health check
  def handle_info(:health_check, state) do
    new_status =
      case Docker.container_status(state.container_id) do
        {:ok, status} -> status
        {:error, _} -> "error"
      end

    state =
      if new_status != state.status do
        Logger.info(
          "[Monitor] Sandbox ##{state.sandbox_id} status: #{state.status} → #{new_status}"
        )

        # Update DB
        sandbox = Sandboxes.get_sandbox!(state.sandbox_id)
        {:ok, _} = Sandboxes.update_sandbox(sandbox, %{status: normalize_status(new_status)})

        # Broadcast status change
        Phoenix.PubSub.broadcast(
          SkillToSandbox.PubSub,
          "sandbox:#{state.sandbox_id}",
          {:status_change, new_status}
        )

        # Also broadcast to the global sandbox updates topic
        Phoenix.PubSub.broadcast(
          SkillToSandbox.PubSub,
          "sandboxes:updates",
          {:sandbox_status_change, state.sandbox_id, new_status}
        )

        %{state | status: new_status}
      else
        state
      end

    # Schedule next health check
    Process.send_after(self(), :health_check, @health_interval_ms)

    {:noreply, state}
  end

  # Catch-all for unexpected port messages
  def handle_info(msg, state) do
    Logger.debug("[Monitor] Unexpected message for sandbox ##{state.sandbox_id}: #{inspect(msg)}")
    {:noreply, state}
  end

  # -- Synchronous calls --

  @impl true
  def handle_call(:stop_container, _from, state) do
    Logger.info("[Monitor] Stopping container for sandbox ##{state.sandbox_id}")

    result = Docker.stop_container(state.container_id)

    state = close_log_port(state)

    new_status =
      case result do
        {:ok, _} -> "stopped"
        {:error, _} -> "error"
      end

    # Update DB and broadcast
    sandbox = Sandboxes.get_sandbox!(state.sandbox_id)
    {:ok, _} = Sandboxes.update_sandbox(sandbox, %{status: new_status})
    broadcast_status(state.sandbox_id, new_status)

    {:reply, result, %{state | status: new_status}}
  end

  def handle_call(:restart_container, _from, state) do
    Logger.info("[Monitor] Restarting container for sandbox ##{state.sandbox_id}")

    state = close_log_port(state)

    result = Docker.restart_container(state.container_id)

    {new_status, state} =
      case result do
        {:ok, _} ->
          # Restart log streaming after container comes back
          state = start_log_streaming(state)
          {"running", state}

        {:error, _} ->
          {"error", state}
      end

    sandbox = Sandboxes.get_sandbox!(state.sandbox_id)
    {:ok, _} = Sandboxes.update_sandbox(sandbox, %{status: new_status})
    broadcast_status(state.sandbox_id, new_status)

    {:reply, result, %{state | status: new_status, log_buffer: []}}
  end

  def handle_call(:destroy_container, _from, state) do
    Logger.info("[Monitor] Destroying container for sandbox ##{state.sandbox_id}")

    state = close_log_port(state)

    result = Docker.remove_container(state.container_id)

    # Update DB
    sandbox = Sandboxes.get_sandbox!(state.sandbox_id)
    {:ok, _} = Sandboxes.update_sandbox(sandbox, %{status: "stopped"})
    broadcast_status(state.sandbox_id, "stopped")

    # Stop the monitor process after destroying
    {:stop, :normal, result, %{state | status: "stopped"}}
  end

  def handle_call(:get_logs, _from, state) do
    {:reply, state.log_buffer, state}
  end

  def handle_call(:get_status, _from, state) do
    {:reply, state.status, state}
  end

  # -------------------------------------------------------------------
  # Cleanup on termination
  # -------------------------------------------------------------------

  @impl true
  def terminate(reason, state) do
    Logger.info("[Monitor] Monitor for sandbox ##{state.sandbox_id} terminating: #{inspect(reason)}")
    close_log_port(state)
    :ok
  end

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

  defp start_log_streaming(state) do
    case Docker.stream_logs(state.container_id) do
      {:ok, port} ->
        %{state | log_port: port}

      {:error, reason} ->
        Logger.warning(
          "[Monitor] Failed to start log streaming for sandbox ##{state.sandbox_id}: #{inspect(reason)}"
        )

        %{state | log_port: nil}
    end
  end

  defp close_log_port(%{log_port: nil} = state), do: state

  defp close_log_port(%{log_port: port} = state) do
    try do
      Port.close(port)
    catch
      _, _ -> :ok
    end

    %{state | log_port: nil}
  end

  defp broadcast_status(sandbox_id, status) do
    Phoenix.PubSub.broadcast(
      SkillToSandbox.PubSub,
      "sandbox:#{sandbox_id}",
      {:status_change, status}
    )

    Phoenix.PubSub.broadcast(
      SkillToSandbox.PubSub,
      "sandboxes:updates",
      {:sandbox_status_change, sandbox_id, status}
    )
  end

  defp normalize_status("running"), do: "running"
  defp normalize_status("exited"), do: "stopped"
  defp normalize_status("stopped"), do: "stopped"
  defp normalize_status("created"), do: "building"
  defp normalize_status("dead"), do: "error"
  defp normalize_status("removing"), do: "stopped"
  defp normalize_status(_), do: "error"

  defp truncate_id(id) when is_binary(id), do: String.slice(id, 0, 12)
  defp truncate_id(id), do: inspect(id)
end
