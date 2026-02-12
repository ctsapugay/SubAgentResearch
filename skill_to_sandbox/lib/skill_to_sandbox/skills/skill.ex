defmodule SkillToSandbox.Skills.Skill do
  @moduledoc """
  Schema for skill definitions parsed from SKILL.md files.

  A skill represents a specialized AI agent capability, including
  its raw content, parsed metadata, and source information.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "skills" do
    field :name, :string
    field :description, :string
    field :source_url, :string
    field :raw_content, :string
    field :parsed_data, :map, default: %{}

    has_many :sandbox_specs, SkillToSandbox.Analysis.SandboxSpec
    has_many :pipeline_runs, SkillToSandbox.Pipeline.PipelineRun

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(name raw_content)a
  @optional_fields ~w(description source_url parsed_data)a

  @doc false
  def changeset(skill, attrs) do
    skill
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 255)
  end
end
