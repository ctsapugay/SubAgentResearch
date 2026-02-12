defmodule SkillToSandbox.Sandbox.Docker do
  @moduledoc """
  Wrapper around Docker CLI commands.

  All Docker operations are executed via `System.cmd/3`, wrapped in `Task`
  with `Task.yield/2` + `Task.shutdown/2` for timeout control (since
  `System.cmd/3` does not have a native timeout option).

  Functions return `{:ok, output}` on success or `{:error, reason}` on failure.
  """

  require Logger

  @build_timeout_ms 300_000
  @run_timeout_ms 60_000
  @cmd_timeout_ms 30_000

  # -------------------------------------------------------------------
  # Image operations
  # -------------------------------------------------------------------

  @doc """
  Build a Docker image from a build context directory.

  ## Options

    * `:timeout` - timeout in ms (default: #{@build_timeout_ms})
  """
  def build_image(context_dir, tag, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @build_timeout_ms)

    Logger.info("[Docker] Building image #{tag} from #{context_dir}")

    run_with_timeout(
      fn ->
        System.cmd("docker", ["build", "-t", tag, context_dir], stderr_to_stdout: true)
      end,
      timeout
    )
  end

  @doc """
  Remove a Docker image by tag or ID.
  """
  def remove_image(image_tag) do
    run_with_timeout(
      fn ->
        System.cmd("docker", ["rmi", "-f", image_tag], stderr_to_stdout: true)
      end,
      @cmd_timeout_ms
    )
  end

  # -------------------------------------------------------------------
  # Container lifecycle
  # -------------------------------------------------------------------

  @doc """
  Run a new container from an image in detached mode.

  ## Options

    * `:ports` - list of `{host_port, container_port}` tuples
    * `:memory` - memory limit (default: `"2g"`)
    * `:cpus` - CPU limit (default: `"2"`)
    * `:timeout` - timeout in ms (default: #{@run_timeout_ms})
  """
  def run_container(image_tag, name, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @run_timeout_ms)

    args =
      ["run", "-d", "--name", name] ++
        host_gateway_args() ++
        resource_limit_args(opts) ++
        port_mapping_args(Keyword.get(opts, :ports, [])) ++
        [image_tag]

    Logger.info("[Docker] Starting container #{name} from #{image_tag}")

    run_with_timeout(
      fn -> System.cmd("docker", args, stderr_to_stdout: true) end,
      timeout
    )
  end

  @doc """
  Execute a command inside a running container.

  ## Options

    * `:timeout` - timeout in ms (default: #{@cmd_timeout_ms})
    * `:workdir` - working directory inside the container
  """
  def exec_in_container(container_id, command, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @cmd_timeout_ms)
    workdir = Keyword.get(opts, :workdir)

    args =
      ["exec"] ++
        if(workdir, do: ["-w", workdir], else: []) ++
        [container_id, "/bin/bash", "-c", command]

    run_with_timeout(
      fn -> System.cmd("docker", args, stderr_to_stdout: true) end,
      timeout
    )
  end

  @doc """
  Stop a running container (with 10s grace period by default).
  """
  def stop_container(container_id, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @cmd_timeout_ms)

    Logger.info("[Docker] Stopping container #{truncate_id(container_id)}")

    run_with_timeout(
      fn -> System.cmd("docker", ["stop", container_id], stderr_to_stdout: true) end,
      timeout
    )
  end

  @doc """
  Forcefully remove a container (running or stopped).
  """
  def remove_container(container_id) do
    Logger.info("[Docker] Removing container #{truncate_id(container_id)}")

    run_with_timeout(
      fn -> System.cmd("docker", ["rm", "-f", container_id], stderr_to_stdout: true) end,
      @cmd_timeout_ms
    )
  end

  @doc """
  Restart a stopped or running container.
  """
  def restart_container(container_id) do
    Logger.info("[Docker] Restarting container #{truncate_id(container_id)}")

    run_with_timeout(
      fn -> System.cmd("docker", ["restart", container_id], stderr_to_stdout: true) end,
      @cmd_timeout_ms
    )
  end

  # -------------------------------------------------------------------
  # Inspection
  # -------------------------------------------------------------------

  @doc """
  Get the status of a container (e.g., "running", "exited", "created").
  """
  def container_status(container_id) do
    case System.cmd(
           "docker",
           ["inspect", container_id, "--format", "{{.State.Status}}"],
           stderr_to_stdout: true
         ) do
      {status, 0} -> {:ok, String.trim(status)}
      {err, _} -> {:error, String.trim(err)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Get the image ID for a container.
  """
  def container_image_id(container_id) do
    case System.cmd(
           "docker",
           ["inspect", container_id, "--format", "{{.Image}}"],
           stderr_to_stdout: true
         ) do
      {image_id, 0} -> {:ok, String.trim(image_id)}
      {err, _} -> {:error, String.trim(err)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  # -------------------------------------------------------------------
  # Log streaming
  # -------------------------------------------------------------------

  @doc """
  Open a Port that streams container logs. Sends `{port, {:data, data}}`
  messages to the calling process.

  Returns `{:ok, port}` on success.
  """
  def stream_logs(container_id) do
    docker_path = System.find_executable("docker")

    if docker_path do
      port =
        Port.open(
          {:spawn_executable, docker_path},
          [
            :binary,
            :exit_status,
            :use_stdio,
            :stderr_to_stdout,
            args: ["logs", "--follow", "--tail", "100", container_id]
          ]
        )

      {:ok, port}
    else
      {:error, "docker executable not found"}
    end
  end

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

  defp run_with_timeout(fun, timeout_ms) do
    task = Task.async(fun)

    case Task.yield(task, timeout_ms) || Task.shutdown(task) do
      {:ok, {output, 0}} ->
        {:ok, String.trim(output)}

      {:ok, {output, code}} ->
        {:error, "Docker exited with code #{code}: #{String.trim(output)}"}

      nil ->
        {:error, :timeout}

      {:exit, reason} ->
        {:error, "Docker task crashed: #{inspect(reason)}"}
    end
  end

  defp host_gateway_args do
    case :os.type() do
      {:unix, :linux} -> ["--add-host=host.docker.internal:host-gateway"]
      # Docker Desktop on Mac/Windows provides host.docker.internal automatically
      _ -> []
    end
  end

  defp resource_limit_args(opts) do
    memory = Keyword.get(opts, :memory, "2g")
    cpus = Keyword.get(opts, :cpus, "2")
    ["--memory=#{memory}", "--cpus=#{cpus}"]
  end

  defp port_mapping_args(ports) do
    Enum.flat_map(ports, fn {host, container} -> ["-p", "#{host}:#{container}"] end)
  end

  defp truncate_id(id) when is_binary(id), do: String.slice(id, 0, 12)
  defp truncate_id(id), do: inspect(id)
end
