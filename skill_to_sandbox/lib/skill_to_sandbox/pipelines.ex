defmodule SkillToSandbox.Pipelines do
  @moduledoc """
  Context module for managing pipeline runs.

  Provides functions for creating, reading, updating, and querying
  pipeline run records. Pipeline runs track the full lifecycle of
  a skill-to-sandbox conversion process.
  """

  import Ecto.Query, warn: false
  alias SkillToSandbox.Repo
  alias SkillToSandbox.Pipeline.PipelineRun

  @doc """
  Returns the list of all pipeline runs, ordered by most recently started.
  """
  def list_runs do
    PipelineRun
    |> order_by(desc: :started_at)
    |> Repo.all()
    |> Repo.preload(:skill)
  end

  @doc """
  Gets a single pipeline run. Raises `Ecto.NoResultsError` if not found.
  """
  def get_run!(id) do
    PipelineRun
    |> Repo.get!(id)
    |> Repo.preload([:skill, :sandbox_spec, :sandbox])
  end

  @doc """
  Creates a pipeline run.
  """
  def create_run(attrs \\ %{}) do
    %PipelineRun{}
    |> PipelineRun.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a pipeline run.
  """
  def update_run(%PipelineRun{} = run, attrs) do
    run
    |> PipelineRun.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns all pipeline runs that are not in a terminal state.
  Used for recovery on restart.
  """
  def active_runs do
    PipelineRun
    |> where([r], r.status not in ["ready", "failed"])
    |> Repo.all()
    |> Repo.preload(:skill)
  end

  @doc """
  Returns all pipeline runs for a given skill.
  """
  def runs_for_skill(skill_id) do
    PipelineRun
    |> where(skill_id: ^skill_id)
    |> order_by(desc: :started_at)
    |> Repo.all()
  end

  @doc """
  Returns the count of active (non-terminal) pipeline runs.
  """
  def count_active_runs do
    PipelineRun
    |> where([r], r.status not in ["ready", "failed"])
    |> Repo.aggregate(:count)
  end
end
