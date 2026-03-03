defmodule SkillToSandbox.Analysis.DependencyRelevantFilesTest do
  @moduledoc """
  Tests for DependencyRelevantFiles: file selection for dependency detection.
  """
  use ExUnit.Case, async: true

  alias SkillToSandbox.Analysis.DependencyRelevantFiles

  describe "dependency_relevant?/1" do
    test "returns true for .html" do
      assert DependencyRelevantFiles.dependency_relevant?("templates/viewer.html")
    end

    test "returns true for .js" do
      assert DependencyRelevantFiles.dependency_relevant?("scripts/main.js")
    end

    test "returns true for .ts" do
      assert DependencyRelevantFiles.dependency_relevant?("src/app.ts")
    end

    test "returns true for .py" do
      assert DependencyRelevantFiles.dependency_relevant?("main.py")
    end

    test "returns true for package.json" do
      assert DependencyRelevantFiles.dependency_relevant?("package.json")
    end

    test "returns true for requirements.txt" do
      assert DependencyRelevantFiles.dependency_relevant?("requirements.txt")
    end

    test "returns false for node_modules/x.js" do
      refute DependencyRelevantFiles.dependency_relevant?("node_modules/lodash/index.js")
    end

    test "returns false for LICENSE.txt" do
      refute DependencyRelevantFiles.dependency_relevant?("LICENSE.txt")
    end

    test "returns false for plain .txt files" do
      refute DependencyRelevantFiles.dependency_relevant?("notes.txt")
    end

    test "returns false for nil" do
      refute DependencyRelevantFiles.dependency_relevant?(nil)
    end
  end

  describe "manifest_file?/1" do
    test "returns true for package.json" do
      assert DependencyRelevantFiles.manifest_file?("package.json")
    end

    test "returns true for requirements.txt" do
      assert DependencyRelevantFiles.manifest_file?("requirements.txt")
    end

    test "returns true for pyproject.toml" do
      assert DependencyRelevantFiles.manifest_file?("pyproject.toml")
    end

    test "returns false for README.md" do
      refute DependencyRelevantFiles.manifest_file?("README.md")
    end

    test "returns false for nil" do
      refute DependencyRelevantFiles.manifest_file?(nil)
    end
  end

  describe "select_files_for_llm/2" do
    test "excludes SKILL.md" do
      file_tree = %{
        "SKILL.md" => "Skill content",
        "package.json" => "{}",
        "templates/viewer.html" => "<html></html>"
      }

      selected = DependencyRelevantFiles.select_files_for_llm(file_tree, 50_000)

      paths = Enum.map(selected, &elem(&1, 0))
      refute "SKILL.md" in paths
    end

    test "returns files in priority order (manifests first)" do
      file_tree = %{
        "SKILL.md" => "Skill content",
        "templates/viewer.html" => "<script src='x'></script>",
        "package.json" => "{}",
        "scripts/app.js" => "const x = 1;"
      }

      selected = DependencyRelevantFiles.select_files_for_llm(file_tree, 50_000)

      paths = Enum.map(selected, &elem(&1, 0))

      # package.json (manifest) should come before viewer.html and app.js
      pkg_idx = Enum.find_index(paths, &(&1 == "package.json"))
      html_idx = Enum.find_index(paths, &(&1 == "templates/viewer.html"))
      js_idx = Enum.find_index(paths, &(&1 == "scripts/app.js"))

      assert pkg_idx < html_idx
      assert pkg_idx < js_idx
    end

    test "respects budget when files fit" do
      file_tree = %{
        "package.json" => "{}",
        "a.js" => String.duplicate("x", 50),
        "b.js" => String.duplicate("y", 50)
      }

      budget = 200
      selected = DependencyRelevantFiles.select_files_for_llm(file_tree, budget)

      total_chars =
        selected
        |> Enum.map(fn {_, content} -> String.length(content) end)
        |> Enum.sum()

      assert total_chars <= budget
    end

    test "adds [truncated] for long non-manifest files" do
      long_content = String.duplicate("x", 10_000)

      file_tree = %{
        "scripts/app.js" => long_content
      }

      selected = DependencyRelevantFiles.select_files_for_llm(file_tree, 100_000)

      assert [{"scripts/app.js", content}] = selected
      assert content =~ "[truncated]"
    end
  end
end
