defmodule SkillToSandbox.Pipeline.Recovery do
  @moduledoc """
  Handles recovery of interrupted pipeline runs on application startup.

  On boot, queries for any pipeline runs in non-terminal states. For runs
  that can be safely resumed (e.g., stuck at "reviewing"), a Runner process
  is started. For runs in states that cannot be safely resumed (e.g.,
  mid-build), the run is marked as failed with an explanation.
  """

  require Logger

  alias SkillToSandbox.Pipelines
  alias SkillToSandbox.Pipeline.Supervisor, as: PipelineSupervisor

  @resumable_statuses ~w(reviewing)
  @restartable_statuses ~w(pending parsing analyzing)

  @doc """
  Check for interrupted pipeline runs and handle them.

  Called as a startup Task in the application supervision tree.
  """
  def recover_on_startup do
    # Small delay to ensure Repo and other services are ready
    Process.sleep(1_000)

    active_runs = Pipelines.active_runs()

    if active_runs == [] do
      Logger.debug("[Recovery] No interrupted pipeline runs found")
    else
      Logger.info("[Recovery] Found #{length(active_runs)} interrupted pipeline run(s)")

      Enum.each(active_runs, &recover_run/1)
    end

    :ok
  end

  defp recover_run(run) do
    cond do
      run.status in @resumable_statuses ->
        # Runs paused at "reviewing" can be safely resumed -- the user
        # just needs to approve the spec. Start a Runner in resume mode.
        Logger.info("[Recovery] Resuming run ##{run.id} (status: #{run.status})")
        PipelineSupervisor.resume_pipeline(run.id, run.skill_id)

      run.status in @restartable_statuses ->
        # Runs that were mid-processing can be restarted from the beginning.
        Logger.info("[Recovery] Restarting run ##{run.id} (status: #{run.status})")
        PipelineSupervisor.resume_pipeline(run.id, run.skill_id)

      run.status in ~w(building configuring) ->
        # Docker operations may have left partial state. Mark as failed
        # and let the user retry manually.
        Logger.info("[Recovery] Marking run ##{run.id} as failed (was: #{run.status})")

        Pipelines.update_run(run, %{
          status: "failed",
          error_message: "Interrupted by application restart during #{run.status}. Please retry.",
          completed_at: DateTime.utc_now()
        })

      true ->
        Logger.warning("[Recovery] Unexpected status for run ##{run.id}: #{run.status}")
    end
  end
end
