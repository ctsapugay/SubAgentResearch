defmodule SkillToSandbox.Integration.DependencyDetectionTest do
  @moduledoc """
  Integration tests for dependency detection (algorithmic-art case).

  Uses a fixture mimicking algorithmic-art: SKILL.md with "Express by creating" text
  (verb, not Express.js), templates/viewer.html with p5.js 1.7.0 CDN URL.

  The test bypasses the real LLM by using provider "test" (returns minimal spec).
  Extracted CDN packages (p5) are merged into the final spec. Express must NOT
  appear since there is no require('express') or import in code.
  """
  use SkillToSandbox.DataCase, async: false

  alias SkillToSandbox.Analysis.Analyzer
  alias SkillToSandbox.Skills

  @algorithmic_art_fixture %{
    "SKILL.md" => """
    ---
    name: algorithmic-art
    description: Express by creating generative art with p5.js
    ---

    # Algorithmic Art

    Express by creating generative art using p5.js in the browser.
    """,
    "templates/viewer.html" => """
    <!DOCTYPE html>
    <html>
    <head>
      <script src="https://cdnjs.cloudflare.com/ajax/libs/p5.js/1.7.0/p5.min.js"></script>
    </head>
    <body></body>
    </html>
    """
  }

  setup do
    # Use "test" provider so LLMClient returns canned JSON (no real API call)
    original = Application.get_env(:skill_to_sandbox, :llm, [])

    Application.put_env(:skill_to_sandbox, :llm,
      provider: "test",
      api_key: "test-key",
      model: "test"
    )

    on_exit(fn ->
      Application.put_env(:skill_to_sandbox, :llm, original)
    end)

    :ok
  end

  describe "algorithmic-art fixture" do
    test "p5 is present with version 1.7.0 or ^1.7.0, express is absent" do
      {:ok, skill} =
        Skills.create_skill(%{
          name: "algorithmic-art",
          description: "Express by creating generative art with p5.js",
          raw_content: @algorithmic_art_fixture["SKILL.md"],
          source_type: "directory",
          file_tree: @algorithmic_art_fixture,
          parsed_data: %{
            "name" => "algorithmic-art",
            "mentioned_tools" => ["web_search"],
            "mentioned_frameworks" => [],
            "mentioned_dependencies" => []
          }
        })

      assert {:ok, spec} = Analyzer.analyze(skill)

      packages = spec.runtime_deps["packages"] || %{}

      assert Map.has_key?(packages, "p5"),
             "Expected p5 in runtime_deps (from CDN URL). Got: #{inspect(packages)}"

      p5_version = packages["p5"]

      assert p5_version == "1.7.0" or p5_version == "^1.7.0",
             "Expected p5 version 1.7.0 or ^1.7.0, got: #{inspect(p5_version)}"

      refute Map.has_key?(packages, "express"),
             "Express must NOT be present (verb in prose, not Express.js). Got: #{inspect(packages)}"
    end
  end
end
