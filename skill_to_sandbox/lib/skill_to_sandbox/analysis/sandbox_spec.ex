defmodule SkillToSandbox.Analysis.SandboxSpec do
  @moduledoc """
  Schema for sandbox specifications produced by LLM analysis.

  A sandbox spec contains all information needed to build a Docker
  container for a skill: base image, packages, dependencies, tool
  configurations, and evaluation goals.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(draft approved building built failed)

  schema "sandbox_specs" do
    field :base_image, :string
    field :system_packages, :map, default: %{}
    field :runtime_deps, :map, default: %{}
    field :tool_configs, :map, default: %{}
    field :eval_goals, :map, default: %{}
    field :dockerfile_content, :string
    field :status, :string, default: "draft"

    belongs_to :skill, SkillToSandbox.Skills.Skill
    has_many :sandboxes, SkillToSandbox.Sandbox.Sandbox, foreign_key: :sandbox_spec_id

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(skill_id base_image status)a
  @optional_fields ~w(system_packages runtime_deps tool_configs eval_goals dockerfile_content)a

  @doc false
  def changeset(sandbox_spec, attrs) do
    sandbox_spec
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:skill_id)
  end
end
