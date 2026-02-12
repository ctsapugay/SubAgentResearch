defmodule SkillToSandbox.Pipeline.Supervisor do
  @moduledoc """
  DynamicSupervisor for Pipeline Runner GenServers.

  Each pipeline run gets its own Runner process, started as a child of this
  supervisor. The supervisor provides fault isolation -- if one pipeline run
  crashes, it doesn't affect others.

  ## Usage

      Pipeline.Supervisor.start_pipeline(skill_id)
  """
  use DynamicSupervisor

  alias SkillToSandbox.Pipelines
  alias SkillToSandbox.Pipeline.Runner

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a new pipeline run for the given skill.

  Creates a `PipelineRun` DB record, then starts a Runner GenServer
  to manage the pipeline lifecycle. Returns `{:ok, run}` on success.
  """
  def start_pipeline(skill_id) do
    {:ok, run} =
      Pipelines.create_run(%{
        skill_id: skill_id,
        status: "pending",
        current_step: 0,
        started_at: DateTime.utc_now()
      })

    case DynamicSupervisor.start_child(
           __MODULE__,
           {Runner, %{run_id: run.id, skill_id: skill_id}}
         ) do
      {:ok, _pid} ->
        {:ok, run}

      {:error, reason} ->
        # Mark the run as failed if we can't start the process
        Pipelines.update_run(run, %{
          status: "failed",
          error_message: "Failed to start pipeline process: #{inspect(reason)}",
          completed_at: DateTime.utc_now()
        })

        {:error, reason}
    end
  end

  @doc """
  Resume a pipeline run that was interrupted (e.g., after app restart).

  Starts a Runner GenServer in `:resume` mode, which reads the run's
  current state from the DB and continues from there.
  """
  def resume_pipeline(run_id, skill_id) do
    case DynamicSupervisor.start_child(
           __MODULE__,
           {Runner, %{run_id: run_id, skill_id: skill_id, resume: true}}
         ) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
