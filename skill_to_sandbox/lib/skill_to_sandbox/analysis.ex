defmodule SkillToSandbox.Analysis do
  @moduledoc """
  Context module for managing sandbox specifications.

  Provides functions for creating, reading, updating, and approving
  sandbox specs produced by LLM analysis. All database operations for
  sandbox specs go through this module.
  """

  import Ecto.Query, warn: false
  alias SkillToSandbox.Repo
  alias SkillToSandbox.Analysis.SandboxSpec

  @doc """
  Creates a sandbox spec.
  """
  def create_spec(attrs \\ %{}) do
    %SandboxSpec{}
    |> SandboxSpec.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a single sandbox spec. Raises `Ecto.NoResultsError` if not found.
  """
  def get_spec!(id), do: Repo.get!(SandboxSpec, id)

  @doc """
  Updates a sandbox spec.
  """
  def update_spec(%SandboxSpec{} = spec, attrs) do
    spec
    |> SandboxSpec.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Approves a sandbox spec, setting its status to "approved".
  """
  def approve_spec(%SandboxSpec{} = spec) do
    update_spec(spec, %{status: "approved"})
  end

  @doc """
  Returns all sandbox specs for a given skill.
  """
  def specs_for_skill(skill_id) do
    SandboxSpec
    |> where(skill_id: ^skill_id)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking spec changes.
  """
  def change_spec(%SandboxSpec{} = spec, attrs \\ %{}) do
    SandboxSpec.changeset(spec, attrs)
  end
end
