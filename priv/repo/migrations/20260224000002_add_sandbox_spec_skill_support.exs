defmodule SkillToSandbox.Repo.Migrations.AddSandboxSpecSkillSupport do
  use Ecto.Migration

  def change do
    alter table(:sandbox_specs) do
      add :skill_mount_path, :string, default: "/workspace/skill"
      add :post_install_commands, :map, default: []
    end
  end
end
