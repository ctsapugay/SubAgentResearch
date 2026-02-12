defmodule SkillToSandbox.Tools.Tool do
  @moduledoc """
  Behaviour defining the interface for sandbox tools.

  Each tool provides:
  - A unique name and human-readable description
  - A JSON Schema for its parameters (used in the tool manifest)
  - An `execute/1` function to run the tool
  - A shell script that gets copied into the container's `/tools/` directory
  """

  @doc "Unique tool name identifier (e.g., \"cli_execution\", \"web_search\")."
  @callback name() :: String.t()

  @doc "Human-readable description of what the tool does."
  @callback description() :: String.t()

  @doc "JSON Schema describing the tool's parameters (for the tool manifest)."
  @callback parameter_schema() :: map()

  @doc """
  Execute the tool with the given arguments.

  For container-scoped tools, `args` must include `"container_id"`.
  Returns `{:ok, output}` or `{:error, reason}`.
  """
  @callback execute(args :: map()) :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Returns shell script content to copy into the container's `/tools/` directory.

  The script should be self-contained and callable from the container.
  """
  @callback container_setup_script() :: String.t()
end
