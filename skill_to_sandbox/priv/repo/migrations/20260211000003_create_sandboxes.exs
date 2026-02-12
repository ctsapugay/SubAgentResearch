defmodule SkillToSandbox.Repo.Migrations.CreateSandboxes do
  use Ecto.Migration

  def change do
    create table(:sandboxes) do
      add :sandbox_spec_id, references(:sandbox_specs, on_delete: :nilify_all), null: false
      add :container_id, :string
      add :image_id, :string
      add :status, :string, null: false, default: "building"
      add :port_mappings, :map, default: %{}
      add :error_message, :text

      timestamps(type: :utc_datetime)
    end

    create index(:sandboxes, [:sandbox_spec_id])
  end
end
