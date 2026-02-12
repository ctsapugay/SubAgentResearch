defmodule SkillToSandbox.Sandboxes do
  @moduledoc """
  Context module for managing sandbox containers.

  Provides functions for creating, reading, updating, and listing
  Docker sandbox containers. All database operations for sandboxes
  go through this module.
  """

  import Ecto.Query, warn: false
  alias SkillToSandbox.Repo
  alias SkillToSandbox.Sandbox.Sandbox

  @doc """
  Returns the list of all sandboxes, ordered by most recently created.
  """
  def list_sandboxes do
    Sandbox
    |> order_by(desc: :inserted_at)
    |> Repo.all()
    |> Repo.preload(sandbox_spec: :skill)
  end

  @doc """
  Gets a single sandbox. Raises `Ecto.NoResultsError` if not found.
  """
  def get_sandbox!(id) do
    Sandbox
    |> Repo.get!(id)
    |> Repo.preload(sandbox_spec: :skill)
  end

  @doc """
  Creates a sandbox.
  """
  def create_sandbox(attrs \\ %{}) do
    %Sandbox{}
    |> Sandbox.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a sandbox.
  """
  def update_sandbox(%Sandbox{} = sandbox, attrs) do
    sandbox
    |> Sandbox.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns all sandboxes for a given sandbox spec.
  """
  def sandboxes_for_spec(sandbox_spec_id) do
    Sandbox
    |> where(sandbox_spec_id: ^sandbox_spec_id)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns the total count of sandboxes.
  """
  def count_sandboxes do
    Repo.aggregate(Sandbox, :count)
  end

  @doc """
  Returns the count of sandboxes with a given status.
  """
  def count_sandboxes_by_status(status) do
    Sandbox
    |> where(status: ^status)
    |> Repo.aggregate(:count)
  end
end
