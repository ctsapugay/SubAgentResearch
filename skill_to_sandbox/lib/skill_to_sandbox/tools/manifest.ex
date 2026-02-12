defmodule SkillToSandbox.Tools.Manifest do
  @moduledoc """
  Generates a tool manifest JSON file.

  The manifest describes all available tools in a machine-readable format
  and is placed at `/workspace/tool_manifest.json` inside the container.
  Downstream systems (Task 1.2's synthetic data generation) use this to
  discover and invoke tools.
  """

  @tools [SkillToSandbox.Tools.CLI, SkillToSandbox.Tools.WebSearch]

  @doc """
  Generate the tool manifest as a JSON string (pretty-printed).
  """
  def generate do
    manifest_map()
    |> Jason.encode!(pretty: true)
  end

  @doc """
  Return the manifest as an Elixir map (useful for tests and inspection).
  """
  def manifest_map do
    %{
      "version" => "1.0",
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "tools" =>
        Enum.map(@tools, fn tool ->
          %{
            "name" => tool.name(),
            "description" => tool.description(),
            "parameters" => tool.parameter_schema(),
            "invocation" => %{
              "type" => "shell_script",
              "path" => "/tools/#{tool.name()}.sh"
            }
          }
        end)
    }
  end

  @doc """
  Returns the list of tool modules registered in the manifest.
  """
  def tool_modules, do: @tools
end
