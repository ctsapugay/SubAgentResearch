defmodule SkillToSandbox.Repo.Migrations.AddSkillDirectorySupport do
  use Ecto.Migration

  def change do
    alter table(:skills) do
      add :source_type, :string, null: false, default: "file"
      add :source_root_url, :string
      add :file_tree, :map, default: %{}
    end
  end
end
