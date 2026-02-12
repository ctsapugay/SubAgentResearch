defmodule SkillToSandbox.Sandbox.DockerCheck do
  @moduledoc """
  Verifies Docker availability on the host machine.

  Provides both a strict `verify!/0` that raises on failure and
  a safe `available?/0` for status checks (e.g., on the dashboard).
  """

  @doc """
  Raises if Docker is not installed or the daemon is not running.
  """
  def verify! do
    case System.cmd("docker", ["info"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, _} -> raise "Docker is not available: #{output}"
    end
  end

  @doc """
  Returns `true` if Docker is installed and the daemon is running.
  """
  def available? do
    match?({_, 0}, System.cmd("docker", ["info"], stderr_to_stdout: true))
  rescue
    _ -> false
  end

  @doc """
  Returns the Docker version string, or `nil` if Docker is not available.
  """
  def version do
    case System.cmd("docker", ["version", "--format", "{{.Server.Version}}"],
           stderr_to_stdout: true) do
      {version, 0} -> String.trim(version)
      _ -> nil
    end
  rescue
    _ -> nil
  end
end
