defmodule SkillToSandbox.Skills do
  @moduledoc """
  Context module for managing skills.

  Provides functions for creating, reading, updating, and deleting
  skill definitions. All database operations for skills go through
  this module.
  """

  import Ecto.Query, warn: false
  alias SkillToSandbox.Repo
  alias SkillToSandbox.Skills.Skill

  @doc """
  Returns the list of all skills, ordered by most recently created.
  """
  def list_skills do
    Skill
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single skill. Raises `Ecto.NoResultsError` if not found.
  """
  def get_skill!(id), do: Repo.get!(Skill, id)

  @doc """
  Creates a skill.

  ## Examples

      iex> create_skill(%{name: "frontend", raw_content: "..."})
      {:ok, %Skill{}}

  """
  def create_skill(attrs \\ %{}) do
    %Skill{}
    |> Skill.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a skill.
  """
  def update_skill(%Skill{} = skill, attrs) do
    skill
    |> Skill.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a skill.
  """
  def delete_skill(%Skill{} = skill) do
    Repo.delete(skill)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking skill changes.
  """
  def change_skill(%Skill{} = skill, attrs \\ %{}) do
    Skill.changeset(skill, attrs)
  end

  @doc """
  Returns the total count of skills.
  """
  def count_skills do
    Repo.aggregate(Skill, :count)
  end
end
