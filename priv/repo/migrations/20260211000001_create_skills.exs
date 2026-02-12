defmodule SkillToSandbox.Repo.Migrations.CreateSkills do
  use Ecto.Migration

  def change do
    create table(:skills) do
      add :name, :string, null: false
      add :description, :text
      add :source_url, :string
      add :raw_content, :text, null: false
      add :parsed_data, :map, default: %{}

      timestamps(type: :utc_datetime)
    end
  end
end
