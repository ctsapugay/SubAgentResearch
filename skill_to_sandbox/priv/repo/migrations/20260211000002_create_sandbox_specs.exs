defmodule SkillToSandbox.Repo.Migrations.CreateSandboxSpecs do
  use Ecto.Migration

  def change do
    create table(:sandbox_specs) do
      add :skill_id, references(:skills, on_delete: :delete_all), null: false
      add :base_image, :string, null: false
      add :system_packages, :map, default: %{}
      add :runtime_deps, :map, default: %{}
      add :tool_configs, :map, default: %{}
      add :eval_goals, :map, default: %{}
      add :dockerfile_content, :text
      add :status, :string, null: false, default: "draft"

      timestamps(type: :utc_datetime)
    end

    create index(:sandbox_specs, [:skill_id])
  end
end
