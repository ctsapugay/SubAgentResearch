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
    field :source_type, :string, default: "file"
    field :source_root_url, :string
    field :file_tree, :map, default: %{}

    has_many :sandbox_specs, SkillToSandbox.Analysis.SandboxSpec
    has_many :pipeline_runs, SkillToSandbox.Pipeline.PipelineRun

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(name raw_content)a
  @optional_fields ~w(description source_url parsed_data source_type source_root_url file_tree)a

  @doc false
  def changeset(skill, attrs) do
    skill
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:raw_content, min: 1)
    |> validate_inclusion(:source_type, ["file", "directory"])
    |> validate_directory_file_tree()
  end

  defp validate_directory_file_tree(changeset) do
    source_type = get_field(changeset, :source_type) || get_change(changeset, :source_type) || "file"
    file_tree = get_field(changeset, :file_tree) || get_change(changeset, :file_tree)

    if source_type == "directory" do
      if is_map(file_tree) and map_size(file_tree || %{}) > 0 do
        changeset
      else
        add_error(changeset, :file_tree, "must be a non-empty map when source_type is directory")
      end
    else
      changeset
    end
  end
end
