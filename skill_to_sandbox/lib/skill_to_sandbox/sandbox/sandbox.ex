defmodule SkillToSandbox.Sandbox.Sandbox do
  @moduledoc """
  Schema for running Docker sandbox containers.

  Tracks the container lifecycle, including its Docker container ID,
  image ID, status, port mappings, and any error information.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(building running stopped error)

  schema "sandboxes" do
    field :container_id, :string
    field :image_id, :string
    field :status, :string, default: "building"
    field :port_mappings, :map, default: %{}
    field :error_message, :string

    belongs_to :sandbox_spec, SkillToSandbox.Analysis.SandboxSpec

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(sandbox_spec_id status)a
  @optional_fields ~w(container_id image_id port_mappings error_message)a

  @doc false
  def changeset(sandbox, attrs) do
    sandbox
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:sandbox_spec_id)
  end
end
