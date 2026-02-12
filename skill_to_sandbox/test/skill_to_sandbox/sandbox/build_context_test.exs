defmodule SkillToSandbox.Sandbox.BuildContextTest do
  use ExUnit.Case, async: true

  alias SkillToSandbox.Sandbox.BuildContext

  # Helper to build a spec struct with the given overrides
  defp build_spec(attrs \\ %{}) do
    defaults = %{
      id: 1,
      skill_id: 1,
      base_image: "node:20-slim",
      system_packages: ["git", "curl"],
      runtime_deps: %{
        "manager" => "npm",
        "packages" => %{"react" => "^18.0.0", "react-dom" => "^18.0.0"}
      },
      tool_configs: %{
        "cli" => %{
          "shell" => "/bin/bash",
          "working_dir" => "/workspace",
          "path_additions" => [],
          "timeout_seconds" => 30
        },
        "web_search" => %{
          "enabled" => true,
          "description" => "Search the web"
        }
      },
      eval_goals: ["Easy: Create a hello world page"],
      dockerfile_content: nil,
      status: "approved"
    }

    struct(SkillToSandbox.Analysis.SandboxSpec, Map.merge(defaults, attrs))
  end

  describe "assemble/1" do
    test "creates a build context directory with all expected files" do
      spec = build_spec()
      assert {:ok, dir, _dockerfile} = BuildContext.assemble(spec)

      on_exit(fn -> BuildContext.cleanup(dir) end)

      # Check that directory exists
      assert File.dir?(dir)

      # Check required files exist
      assert File.exists?(Path.join(dir, "Dockerfile"))
      assert File.exists?(Path.join(dir, "package.json"))
      assert File.exists?(Path.join(dir, "tool_manifest.json"))
      assert File.exists?(Path.join(dir, "tools/cli_execution.sh"))
      assert File.exists?(Path.join(dir, "tools/web_search.sh"))
    end

    test "Dockerfile contains correct content" do
      spec = build_spec()
      assert {:ok, dir, dockerfile_content} = BuildContext.assemble(spec)

      on_exit(fn -> BuildContext.cleanup(dir) end)

      file_content = File.read!(Path.join(dir, "Dockerfile"))
      assert file_content == dockerfile_content
      assert file_content =~ "FROM node:20-slim"
      assert file_content =~ "npm install"
    end

    test "package.json is valid JSON for npm specs" do
      spec = build_spec()
      assert {:ok, dir, _} = BuildContext.assemble(spec)

      on_exit(fn -> BuildContext.cleanup(dir) end)

      content = File.read!(Path.join(dir, "package.json"))
      decoded = Jason.decode!(content)
      assert decoded["name"] == "sandbox"
      assert decoded["dependencies"]["react"] == "^18.0.0"
    end

    test "requirements.txt is generated for pip specs" do
      spec =
        build_spec(%{
          base_image: "python:3.12-slim",
          runtime_deps: %{
            "manager" => "pip",
            "packages" => %{"flask" => "3.0.0", "requests" => "^2.31.0"}
          }
        })

      assert {:ok, dir, _} = BuildContext.assemble(spec)

      on_exit(fn -> BuildContext.cleanup(dir) end)

      assert File.exists?(Path.join(dir, "requirements.txt"))
      content = File.read!(Path.join(dir, "requirements.txt"))
      assert content =~ "flask"
      assert content =~ "requests"
      # No package.json for pip projects
      refute File.exists?(Path.join(dir, "package.json"))
    end

    test "tool scripts are executable" do
      spec = build_spec()
      assert {:ok, dir, _} = BuildContext.assemble(spec)

      on_exit(fn -> BuildContext.cleanup(dir) end)

      cli_path = Path.join(dir, "tools/cli_execution.sh")
      %{mode: mode} = File.stat!(cli_path)
      # Check executable bit is set (owner execute = 0o100)
      assert Bitwise.band(mode, 0o111) != 0
    end

    test "tool manifest is valid JSON" do
      spec = build_spec()
      assert {:ok, dir, _} = BuildContext.assemble(spec)

      on_exit(fn -> BuildContext.cleanup(dir) end)

      content = File.read!(Path.join(dir, "tool_manifest.json"))
      manifest = Jason.decode!(content)
      assert manifest["version"] == "1.0"
      assert is_list(manifest["tools"])
      assert length(manifest["tools"]) == 2

      tool_names = Enum.map(manifest["tools"], & &1["name"])
      assert "cli_execution" in tool_names
      assert "web_search" in tool_names
    end

    test "tool manifest contains parameter schemas" do
      spec = build_spec()
      assert {:ok, dir, _} = BuildContext.assemble(spec)

      on_exit(fn -> BuildContext.cleanup(dir) end)

      manifest =
        dir
        |> Path.join("tool_manifest.json")
        |> File.read!()
        |> Jason.decode!()

      for tool <- manifest["tools"] do
        assert is_map(tool["parameters"])
        assert tool["parameters"]["type"] == "object"
        assert is_map(tool["parameters"]["properties"])
        assert is_map(tool["invocation"])
        assert tool["invocation"]["type"] == "shell_script"
        assert String.starts_with?(tool["invocation"]["path"], "/tools/")
      end
    end

    test "handles spec with no runtime deps" do
      spec = build_spec(%{runtime_deps: nil})
      assert {:ok, dir, _} = BuildContext.assemble(spec)

      on_exit(fn -> BuildContext.cleanup(dir) end)

      assert File.exists?(Path.join(dir, "Dockerfile"))
      refute File.exists?(Path.join(dir, "package.json"))
      refute File.exists?(Path.join(dir, "requirements.txt"))
    end

    test "returns dockerfile content as third element" do
      spec = build_spec()
      assert {:ok, dir, dockerfile} = BuildContext.assemble(spec)

      on_exit(fn -> BuildContext.cleanup(dir) end)

      assert is_binary(dockerfile)
      assert dockerfile =~ "FROM node:20-slim"
    end
  end

  describe "cleanup/1" do
    test "removes the build context directory" do
      spec = build_spec()
      assert {:ok, dir, _} = BuildContext.assemble(spec)

      assert File.dir?(dir)
      assert :ok = BuildContext.cleanup(dir)
      refute File.exists?(dir)
    end

    test "is a no-op for non-existent directories" do
      assert :ok = BuildContext.cleanup("/tmp/non_existent_dir_abc123")
    end
  end

  describe "list_files/1" do
    test "lists all files in the build context" do
      spec = build_spec()
      assert {:ok, dir, _} = BuildContext.assemble(spec)

      on_exit(fn -> BuildContext.cleanup(dir) end)

      files = BuildContext.list_files(dir)
      assert "Dockerfile" in files
      assert "package.json" in files
      assert "tool_manifest.json" in files
      assert "tools/cli_execution.sh" in files
      assert "tools/web_search.sh" in files
    end
  end
end
