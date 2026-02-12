defmodule SkillToSandbox.Pipeline.PipelineRun do
  @moduledoc """
  Schema for pipeline run state persistence.

  Tracks the full lifecycle of a skill-to-sandbox conversion pipeline,
  including the current step, timing data, and error information.
  State is persisted so runs survive app restarts.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending parsing analyzing reviewing building configuring ready failed)

  schema "pipeline_runs" do
    field :status, :string, default: "pending"
    field :current_step, :integer, default: 0
    field :error_message, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :step_timings, :map, default: %{}

    belongs_to :skill, SkillToSandbox.Skills.Skill
    belongs_to :sandbox_spec, SkillToSandbox.Analysis.SandboxSpec
    belongs_to :sandbox, SkillToSandbox.Sandbox.Sandbox

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(skill_id status)a
  @optional_fields ~w(sandbox_spec_id sandbox_id current_step error_message started_at completed_at step_timings)a

  @doc false
  def changeset(pipeline_run, attrs) do
    pipeline_run
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:skill_id)
    |> foreign_key_constraint(:sandbox_spec_id)
    |> foreign_key_constraint(:sandbox_id)
  end
end
