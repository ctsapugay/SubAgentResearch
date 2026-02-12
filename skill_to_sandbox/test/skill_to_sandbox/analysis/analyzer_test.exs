defmodule SkillToSandbox.Analysis.AnalyzerTest do
  use SkillToSandbox.DataCase, async: false

  alias SkillToSandbox.Analysis.Analyzer
  alias SkillToSandbox.Skills

  # -- Valid JSON fixtures --

  @valid_spec_json """
  {
    "base_image": "node:20-slim",
    "system_packages": ["git", "curl", "build-essential"],
    "runtime_deps": {
      "manager": "npm",
      "packages": {"react": "^18.0.0", "react-dom": "^18.0.0", "tailwindcss": "^3.4.0"}
    },
    "tool_configs": {
      "cli": {
        "shell": "/bin/bash",
        "working_dir": "/workspace",
        "path_additions": [],
        "timeout_seconds": 30
      },
      "web_search": {
        "enabled": true,
        "description": "Search the web for design inspiration and documentation"
      }
    },
    "eval_goals": [
      "Easy: Create a simple HTML page with a centered heading and styled button",
      "Easy: Build a responsive navigation bar using CSS Flexbox",
      "Medium: Create a React component with state management for a todo list",
      "Medium: Build a responsive card grid layout with hover animations using Tailwind CSS",
      "Medium: Implement a dark/light theme toggle using CSS custom properties",
      "Hard: Build a multi-step form wizard with validation and animated transitions",
      "Hard: Create a responsive dashboard layout with charts placeholder and real-time data simulation",
      "Hard: Implement an accessible modal system with focus trapping and keyboard navigation"
    ]
  }
  """

  # -- extract_json/1 tests --

  describe "extract_json/1" do
    test "parses valid JSON successfully" do
      assert {:ok, map} = Analyzer.extract_json(@valid_spec_json)
      assert map["base_image"] == "node:20-slim"
      assert is_list(map["system_packages"])
      assert is_list(map["eval_goals"])
    end

    test "strips markdown ```json fences" do
      fenced = "```json\n#{@valid_spec_json}\n```"
      assert {:ok, map} = Analyzer.extract_json(fenced)
      assert map["base_image"] == "node:20-slim"
    end

    test "strips markdown ``` fences without language tag" do
      fenced = "```\n#{@valid_spec_json}\n```"
      assert {:ok, map} = Analyzer.extract_json(fenced)
      assert map["base_image"] == "node:20-slim"
    end

    test "strips markdown ```JSON fences (case-insensitive)" do
      fenced = "```JSON\n#{@valid_spec_json}\n```"
      assert {:ok, map} = Analyzer.extract_json(fenced)
      assert map["base_image"] == "node:20-slim"
    end

    test "returns error for invalid JSON" do
      assert {:error, msg} = Analyzer.extract_json("{invalid json here")
      assert msg =~ "Failed to parse"
    end

    test "returns error for non-object JSON" do
      assert {:error, msg} = Analyzer.extract_json("[1, 2, 3]")
      assert msg =~ "not a JSON object"
    end

    test "returns error for empty string" do
      assert {:error, _} = Analyzer.extract_json("")
    end

    test "returns error for non-string input" do
      assert {:error, _} = Analyzer.extract_json(nil)
      assert {:error, _} = Analyzer.extract_json(42)
    end

    test "handles JSON with leading/trailing whitespace" do
      padded = "  \n\n  #{@valid_spec_json}  \n\n  "
      assert {:ok, map} = Analyzer.extract_json(padded)
      assert map["base_image"] == "node:20-slim"
    end
  end

  # -- validate_spec/1 tests --

  describe "validate_spec/1" do
    setup do
      {:ok, spec} = Jason.decode(@valid_spec_json)
      %{spec: spec}
    end

    test "validates a complete spec successfully", %{spec: spec} do
      assert {:ok, normalized} = Analyzer.validate_spec(spec)
      assert normalized.base_image == "node:20-slim"
      assert is_list(normalized.system_packages)
      assert is_map(normalized.runtime_deps)
      assert is_map(normalized.tool_configs)
      assert is_list(normalized.eval_goals)
    end

    test "returns error for missing base_image", %{spec: spec} do
      spec = Map.delete(spec, "base_image")
      assert {:error, msg} = Analyzer.validate_spec(spec)
      assert msg =~ "Missing required fields"
      assert msg =~ "base_image"
    end

    test "returns error for missing system_packages", %{spec: spec} do
      spec = Map.delete(spec, "system_packages")
      assert {:error, msg} = Analyzer.validate_spec(spec)
      assert msg =~ "Missing required fields"
    end

    test "returns error for missing runtime_deps", %{spec: spec} do
      spec = Map.delete(spec, "runtime_deps")
      assert {:error, msg} = Analyzer.validate_spec(spec)
      assert msg =~ "Missing required fields"
    end

    test "returns error for missing tool_configs", %{spec: spec} do
      spec = Map.delete(spec, "tool_configs")
      assert {:error, msg} = Analyzer.validate_spec(spec)
      assert msg =~ "Missing required fields"
    end

    test "returns error for missing eval_goals", %{spec: spec} do
      spec = Map.delete(spec, "eval_goals")
      assert {:error, msg} = Analyzer.validate_spec(spec)
      assert msg =~ "Missing required fields"
    end

    test "returns error for empty base_image", %{spec: spec} do
      spec = Map.put(spec, "base_image", "")
      assert {:error, msg} = Analyzer.validate_spec(spec)
      assert msg =~ "base_image"
    end

    test "returns error for non-string system_packages items", %{spec: spec} do
      spec = Map.put(spec, "system_packages", ["git", 42, "curl"])
      assert {:error, msg} = Analyzer.validate_spec(spec)
      assert msg =~ "system_packages"
    end

    test "returns error for system_packages as non-list", %{spec: spec} do
      spec = Map.put(spec, "system_packages", %{"git" => true})
      assert {:error, msg} = Analyzer.validate_spec(spec)
      assert msg =~ "system_packages"
    end

    test "returns error when runtime_deps.manager is missing", %{spec: spec} do
      spec = Map.put(spec, "runtime_deps", %{"packages" => %{}})
      assert {:error, msg} = Analyzer.validate_spec(spec)
      assert msg =~ "runtime_deps.manager"
    end

    test "returns error when runtime_deps.packages is missing", %{spec: spec} do
      spec = Map.put(spec, "runtime_deps", %{"manager" => "npm"})
      assert {:error, msg} = Analyzer.validate_spec(spec)
      assert msg =~ "runtime_deps.packages"
    end

    test "returns error when tool_configs.cli is missing", %{spec: spec} do
      spec = Map.put(spec, "tool_configs", %{"web_search" => %{"enabled" => true}})
      assert {:error, msg} = Analyzer.validate_spec(spec)
      assert msg =~ "tool_configs.cli"
    end

    test "returns error when tool_configs.web_search is missing", %{spec: spec} do
      spec = Map.put(spec, "tool_configs", %{"cli" => %{"shell" => "/bin/bash"}})
      assert {:error, msg} = Analyzer.validate_spec(spec)
      assert msg =~ "tool_configs.web_search"
    end

    test "returns error when eval_goals has fewer than 5 items", %{spec: spec} do
      spec = Map.put(spec, "eval_goals", ["goal 1", "goal 2", "goal 3"])
      assert {:error, msg} = Analyzer.validate_spec(spec)
      assert msg =~ "at least 5"
    end

    test "returns error when eval_goals contains non-string items", %{spec: spec} do
      spec = Map.put(spec, "eval_goals", ["ok", "ok", "ok", "ok", 42])
      assert {:error, msg} = Analyzer.validate_spec(spec)
      assert msg =~ "eval_goals"
    end

    test "accepts exactly 5 eval goals", %{spec: spec} do
      spec = Map.put(spec, "eval_goals", ["g1", "g2", "g3", "g4", "g5"])
      assert {:ok, _} = Analyzer.validate_spec(spec)
    end

    test "returns error for non-map input" do
      assert {:error, _} = Analyzer.validate_spec("not a map")
      assert {:error, _} = Analyzer.validate_spec(nil)
    end
  end

  # -- Full analyze/1 flow test (with DB) --

  describe "analyze/1 integration" do
    test "creates a sandbox spec from a skill when LLM returns valid JSON" do
      # Create a test skill in the DB
      {:ok, skill} =
        Skills.create_skill(%{
          name: "test-skill",
          description: "A test skill for analysis",
          raw_content: "# Test\n\nUse React and Node.js.\n\n## Tools\n\n- Web search\n- CLI",
          parsed_data: %{
            "name" => "test-skill",
            "mentioned_tools" => ["web_search", "cli_execution"],
            "mentioned_frameworks" => ["React", "Node.js"],
            "mentioned_dependencies" => []
          }
        })

      # We can't easily mock the LLM client in this test without a mocking
      # library, so we test extract_json + validate_spec as the critical path.
      # The full analyze/1 with a real LLM call is an integration test.

      # Instead, verify the full extract + validate + create_spec pipeline
      {:ok, spec_map} = Analyzer.extract_json(@valid_spec_json)
      {:ok, validated} = Analyzer.validate_spec(spec_map)

      {:ok, spec} =
        SkillToSandbox.Analysis.create_spec(
          Map.merge(validated, %{skill_id: skill.id, status: "draft"})
        )

      assert spec.id
      assert spec.skill_id == skill.id
      assert spec.base_image == "node:20-slim"
      assert spec.status == "draft"
      assert is_list(spec.system_packages)
      assert "git" in spec.system_packages
      assert is_list(spec.eval_goals)
      assert length(spec.eval_goals) == 8
      assert spec.runtime_deps["manager"] == "npm"
      assert spec.tool_configs["cli"]["shell"] == "/bin/bash"
    end
  end

  # -- Roundtrip test: verify lists survive DB storage --

  describe "SandboxSpec JSON list roundtrip" do
    test "system_packages list survives DB insert and read" do
      {:ok, skill} =
        Skills.create_skill(%{
          name: "roundtrip-test",
          raw_content: "test content"
        })

      {:ok, spec} =
        SkillToSandbox.Analysis.create_spec(%{
          skill_id: skill.id,
          base_image: "node:20-slim",
          system_packages: ["git", "curl", "build-essential"],
          eval_goals: [
            "Easy: task 1",
            "Easy: task 2",
            "Medium: task 3",
            "Hard: task 4",
            "Hard: task 5"
          ],
          status: "draft"
        })

      # Re-read from DB
      reloaded = SkillToSandbox.Analysis.get_spec!(spec.id)

      assert is_list(reloaded.system_packages)
      assert reloaded.system_packages == ["git", "curl", "build-essential"]
      assert is_list(reloaded.eval_goals)
      assert length(reloaded.eval_goals) == 5
      assert "Easy: task 1" in reloaded.eval_goals
    end
  end
end
