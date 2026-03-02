defmodule SkillToSandbox.Skills.DependencyScannerTest do
  use ExUnit.Case, async: true

  alias SkillToSandbox.Skills.DependencyScanner

  describe "scan/1" do
    test "returns empty maps when file_tree is empty" do
      result = DependencyScanner.scan(%{})

      assert result.npm == %{}
      assert result.pip == %{}
      assert result.package_json_path == nil
      assert result.requirements_path == nil
      assert result.pyproject_path == nil
    end

    test "returns empty maps when file_tree is nil" do
      result = DependencyScanner.scan(nil)

      assert result.npm == %{}
      assert result.pip == %{}
    end

    test "extracts npm dependencies from package.json at root" do
      file_tree = %{
        "package.json" => """
        {
          "name": "my-skill",
          "dependencies": {
            "react": "^18.0.0",
            "agent-browser": "latest"
          }
        }
        """
      }

      result = DependencyScanner.scan(file_tree)

      assert result.npm == %{"react" => "^18.0.0", "agent-browser" => "latest"}
      assert result.package_json_path == "package.json"
      assert result.pip == %{}
      assert result.requirements_path == nil
    end

    test "extracts npm devDependencies and merges with dependencies" do
      file_tree = %{
        "package.json" => """
        {
          "dependencies": {"react": "^18.0.0"},
          "devDependencies": {"vitest": "^1.0.0", "eslint": "8.0.0"}
        }
        """
      }

      result = DependencyScanner.scan(file_tree)

      assert result.npm["react"] == "^18.0.0"
      assert result.npm["vitest"] == "^1.0.0"
      assert result.npm["eslint"] == "8.0.0"
    end

    test "finds package.json in subdirectory" do
      file_tree = %{
        "SKILL.md" => "# Skill",
        "skill/package.json" => """
        {"dependencies": {"playwright": "^1.40.0"}}
        """
      }

      result = DependencyScanner.scan(file_tree)

      assert result.npm == %{"playwright" => "^1.40.0"}
      assert result.package_json_path == "skill/package.json"
    end

    test "extracts pip dependencies from requirements.txt" do
      file_tree = %{
        "requirements.txt" => """
        flask==3.0.0
        requests>=2.28.0
        django>=4.0,<5.0
        """
      }

      result = DependencyScanner.scan(file_tree)

      assert result.pip["flask"] == "3.0.0"
      assert result.pip["requests"] == ">=2.28.0"
      assert result.pip["django"] == ">=4.0,<5.0"
      assert result.requirements_path == "requirements.txt"
    end

    test "skips comments and empty lines in requirements.txt" do
      file_tree = %{
        "requirements.txt" => """
        # This is a comment
        flask==3.0.0

        requests>=2.28.0
        # Another comment
        """
      }

      result = DependencyScanner.scan(file_tree)

      assert result.pip == %{"flask" => "3.0.0", "requests" => ">=2.28.0"}
    end

    test "handles package without version in requirements.txt" do
      file_tree = %{
        "requirements.txt" => "requests\nflask==3.0.0"
      }

      result = DependencyScanner.scan(file_tree)

      assert result.pip["requests"] == nil
      assert result.pip["flask"] == "3.0.0"
    end

    test "handles both package.json and requirements.txt in same tree" do
      file_tree = %{
        "package.json" => """
        {"dependencies": {"react": "^18.0.0"}}
        """,
        "requirements.txt" => "flask==3.0.0",
        "SKILL.md" => "# Full-stack skill"
      }

      result = DependencyScanner.scan(file_tree)

      assert result.npm == %{"react" => "^18.0.0"}
      assert result.pip == %{"flask" => "3.0.0"}
      assert result.package_json_path == "package.json"
      assert result.requirements_path == "requirements.txt"
    end

    test "handles invalid package.json gracefully" do
      file_tree = %{
        "package.json" => "not valid json {"
      }

      result = DependencyScanner.scan(file_tree)

      assert result.npm == %{}
      assert result.package_json_path == "package.json"
    end

    test "handles package.json with no dependencies" do
      file_tree = %{
        "package.json" => """
        {"name": "empty-skill", "version": "1.0.0"}
        """
      }

      result = DependencyScanner.scan(file_tree)

      assert result.npm == %{}
    end

    test "finds _repo_root/package.json (agent-browser style)" do
      file_tree = %{
        "SKILL.md" => "# Agent Browser",
        "_repo_root/package.json" => """
        {"dependencies": {"agent-browser": "latest", "playwright-core": "^1.40.0"}}
        """
      }

      result = DependencyScanner.scan(file_tree)

      assert result.npm["agent-browser"] == "latest"
      assert result.npm["playwright-core"] == "^1.40.0"
      assert result.package_json_path == "_repo_root/package.json"
    end

    test "extracts pip dependencies from pyproject.toml" do
      file_tree = %{
        "pyproject.toml" => """
        [project]
        name = "my-skill"
        dependencies = [
          "flask>=3.0",
          "requests>=2.28.0"
        ]
        """
      }

      result = DependencyScanner.scan(file_tree)

      assert result.pip["flask"] == ">=3.0"
      assert result.pip["requests"] == ">=2.28.0"
      assert result.pyproject_path == "pyproject.toml"
    end

    test "merges pyproject deps with requirements.txt" do
      file_tree = %{
        "requirements.txt" => "flask==3.0.0",
        "pyproject.toml" => """
        [project]
        dependencies = ["requests>=2.28.0"]
        """
      }

      result = DependencyScanner.scan(file_tree)

      assert result.pip["flask"] == "3.0.0"
      assert result.pip["requests"] == ">=2.28.0"
    end

    test "follows -r include in requirements.txt" do
      file_tree = %{
        "requirements.txt" => """
        flask==3.0.0
        -r requirements-dev.txt
        """,
        "requirements-dev.txt" => "pytest>=7.0.0"
      }

      result = DependencyScanner.scan(file_tree)

      assert result.pip["flask"] == "3.0.0"
      assert result.pip["pytest"] == ">=7.0.0"
    end

    test "skips -e and -c lines in requirements.txt" do
      file_tree = %{
        "requirements.txt" => """
        flask==3.0.0
        -e ./local-pkg
        -c constraints.txt
        """
      }

      result = DependencyScanner.scan(file_tree)

      assert result.pip == %{"flask" => "3.0.0"}
    end

    test "merges multiple package.json with root winning on conflicts" do
      file_tree = %{
        "package.json" => """
        {"dependencies": {"react": "^19.0.0", "root-only": "1.0"}}
        """,
        "packages/ui/package.json" => """
        {"dependencies": {"react": "^18.0.0", "ui-pkg": "2.0"}}
        """
      }

      result = DependencyScanner.scan(file_tree)

      assert result.npm["react"] == "^19.0.0"
      assert result.npm["root-only"] == "1.0"
      assert result.npm["ui-pkg"] == "2.0"
      assert result.package_json_path == "package.json"
    end
  end
end
