defmodule SkillToSandbox.EctoTypes.JsonData do
  @moduledoc """
  Custom Ecto type for JSON columns that can hold either maps or lists.

  Ecto's built-in `:map` type only accepts maps through `cast/1`. This type
  accepts both maps and lists, which is needed for fields like `system_packages`
  (a list) and `eval_goals` (a list) stored as JSON in SQLite.
  """
  use Ecto.Type

  @impl true
  def type, do: :map

  @impl true
  def cast(data) when is_map(data), do: {:ok, data}
  def cast(data) when is_list(data), do: {:ok, data}
  def cast(_), do: :error

  @impl true
  def load(nil), do: {:ok, nil}
  def load(data) when is_map(data) or is_list(data), do: {:ok, data}
  def load(_), do: :error

  @impl true
  def dump(nil), do: {:ok, nil}
  def dump(data) when is_map(data) or is_list(data), do: {:ok, data}
  def dump(_), do: :error

  @impl true
  def equal?(a, b), do: a == b
end
