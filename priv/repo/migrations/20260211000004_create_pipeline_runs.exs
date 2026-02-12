defmodule SkillToSandbox.Repo.Migrations.CreatePipelineRuns do
  use Ecto.Migration

  def change do
    create table(:pipeline_runs) do
      add :skill_id, references(:skills, on_delete: :delete_all), null: false
      add :sandbox_spec_id, references(:sandbox_specs, on_delete: :nilify_all)
      add :sandbox_id, references(:sandboxes, on_delete: :nilify_all)
      add :status, :string, null: false, default: "pending"
      add :current_step, :integer, default: 0
      add :error_message, :text
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :step_timings, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:pipeline_runs, [:skill_id])
    create index(:pipeline_runs, [:status])
  end
end
