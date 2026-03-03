defmodule SkillToSandbox.Integration.DependencyPipelineTest do
  @moduledoc """
  Integration tests for the dependency discovery pipeline.

  Verifies that DependencyScanner, Parser, and Analyzer merge logic work together
  to produce correct runtime_deps from various input configurations.
  """
  use SkillToSandbox.DataCase, async: false

  alias SkillToSandbox.Analysis.Analyzer
  alias SkillToSandbox.Skills.{DependencyScanner, Parser}

  describe "dependency discovery from file_tree" do
    test "package.json in file_tree yields correct npm deps in merge" do
      file_tree = %{
        "SKILL.md" => """
        ---
        name: frontend-skill
        ---
        # Frontend
        Uses React and Tailwind.
        """,
        "package.json" => """
        {"dependencies": {"react": "^18.0.0", "tailwindcss": "^3.4.0"}}
        """
      }

      scanner_result = DependencyScanner.scan(file_tree)
      assert scanner_result.npm["react"] == "^18.0.0"
      assert scanner_result.npm["tailwindcss"] == "^3.4.0"
      assert scanner_result.package_json_path == "package.json"

      {:ok, parsed} = Parser.parse_directory(file_tree)
      assert parsed["name"] == "frontend-skill"

      # Simulate LLM output and merge
      validated = %{
        base_image: "node:20-slim",
        system_packages: ["git", "curl"],
        runtime_deps: %{"manager" => "npm", "packages" => %{"react" => "^17.0.0"}},
        tool_configs: %{"cli" => %{}, "web_search" => %{}},
        eval_goals: List.duplicate("Goal", 5)
      }

      merged = Analyzer.merge_scanner_deps(validated, scanner_result)
      assert merged.runtime_deps["packages"]["react"] == "^18.0.0"
      assert merged.runtime_deps["packages"]["tailwindcss"] == "^3.4.0"
    end

    test "requirements.txt yields correct pip deps in merge" do
      file_tree = %{
        "SKILL.md" => "---\nname: api-skill\n---\n# API\nUses Flask.",
        "requirements.txt" => "flask==3.0.0\nrequests>=2.28.0"
      }

      scanner_result = DependencyScanner.scan(file_tree)
      assert scanner_result.pip["flask"] == "3.0.0"
      assert scanner_result.pip["requests"] == ">=2.28.0"

      validated = %{
        base_image: "python:3.11-slim",
        system_packages: ["git", "curl"],
        runtime_deps: %{"manager" => "pip", "packages" => %{}},
        tool_configs: %{"cli" => %{}, "web_search" => %{}},
        eval_goals: List.duplicate("Goal", 5)
      }

      merged = Analyzer.merge_scanner_deps(validated, scanner_result)
      assert merged.runtime_deps["manager"] == "pip"
      assert merged.runtime_deps["packages"]["flask"] == "3.0.0"
    end

    test "allowed-tools from frontmatter are extracted by Parser" do
      content = """
      ---
      name: agent-browser
      allowed-tools: Bash(npx agent-browser:*), Bash(playwright:*)
      ---
      # Agent Browser
      """

      {:ok, parsed} = Parser.parse(content)
      allowed = Parser.extract_allowed_tools_deps(parsed["frontmatter"])
      assert "agent-browser" in allowed
      assert "playwright" in allowed
    end

    test "pyproject.toml deps are merged into pip" do
      file_tree = %{
        "SKILL.md" => "# Python skill",
        "pyproject.toml" => """
        [project]
        name = "my-skill"
        dependencies = ["flask>=3.0", "requests>=2.28.0"]
        """
      }

      scanner_result = DependencyScanner.scan(file_tree)
      assert scanner_result.pip["flask"] == ">=3.0"
      assert scanner_result.pip["requests"] == ">=2.28.0"
      assert scanner_result.pyproject_path == "pyproject.toml"
    end
  end
end
