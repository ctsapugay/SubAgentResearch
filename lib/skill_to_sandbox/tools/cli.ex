defmodule SkillToSandbox.Tools.CLI do
  @moduledoc """
  CLI execution tool for sandbox containers.

  Executes shell commands inside a running Docker container via
  `docker exec`. Commands run under `/bin/bash -c` with a configurable
  timeout (default 30s, configurable via `:tools` app config).
  """

  @behaviour SkillToSandbox.Tools.Tool

  alias SkillToSandbox.Sandbox.Docker

  @impl true
  def name, do: "cli_execution"

  @impl true
  def description, do: "Execute a shell command in the sandbox environment"

  @impl true
  def parameter_schema do
    %{
      "type" => "object",
      "properties" => %{
        "command" => %{
          "type" => "string",
          "description" => "The shell command to execute"
        },
        "working_dir" => %{
          "type" => "string",
          "description" => "Working directory for command execution (default: /workspace)"
        }
      },
      "required" => ["command"]
    }
  end

  @impl true
  def execute(%{"command" => command, "container_id" => container_id} = args) do
    timeout = cli_timeout_ms()
    workdir = Map.get(args, "working_dir", "/workspace")

    Docker.exec_in_container(container_id, command,
      timeout: timeout,
      workdir: workdir
    )
  end

  def execute(_args) do
    {:error, "Missing required fields: 'command' and 'container_id'"}
  end

  @impl true
  def container_setup_script do
    """
    #!/bin/bash
    # CLI execution wrapper with timeout
    # Usage: cli_execution.sh <command>
    set -euo pipefail
    TIMEOUT="${CLI_TIMEOUT:-30}"
    WORKDIR="${WORKSPACE_DIR:-/workspace}"
    cd "$WORKDIR"
    timeout "$TIMEOUT" bash -c "$*" 2>&1
    """
  end

  defp cli_timeout_ms do
    Application.get_env(:skill_to_sandbox, :tools, [])
    |> Keyword.get(:cli_timeout_ms, 30_000)
  end
end
