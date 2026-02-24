defmodule Mix.Tasks.SkillToSandbox.BackfillFileTree do
  @shortdoc "Backfill file_tree for existing skills (source_type=file)"
  use Mix.Task

  @moduledoc """
  Backfills the `file_tree` field for existing skills that have `raw_content`
  but empty or missing `file_tree`.

  For each such skill, sets `file_tree` to `%{"SKILL.md" => raw_content}` so
  that BuildContext and other modules can treat them consistently with
  directory skills.

  Run with: `mix skill_to_sandbox.backfill_file_tree`
  """

  def run(_args) do
    Mix.Task.run("app.start")

    alias SkillToSandbox.Repo
    alias SkillToSandbox.Skills.Skill

    skills =
      Skill
      |> Repo.all()
      |> Enum.filter(fn skill ->
        file_tree = skill.file_tree
        (file_tree == nil or file_tree == %{}) and is_binary(skill.raw_content) and skill.raw_content != ""
      end)

    count = length(skills)

    Enum.each(skills, fn skill ->
      Skill.changeset(skill, %{file_tree: %{"SKILL.md" => skill.raw_content}})
      |> Repo.update!()
    end)

    IO.puts("Backfilled file_tree for #{count} skill(s).")
  end
end
