defmodule SkillToSandbox.Integration.PipelineIntegrationTest do
  @moduledoc """
  End-to-end integration tests for the pipeline with directory and single-file skills.

  These tests require Docker to be available. They are excluded by default.
  Run with: mix test --include docker
  """
  use SkillToSandbox.DataCase, async: false

  @moduletag :docker

  alias SkillToSandbox.{Skills, Pipelines, Analysis, Sandboxes}
  alias SkillToSandbox.Pipeline.Runner
  alias SkillToSandbox.Sandbox.Docker

  @agent_browser_file_tree %{
    "SKILL.md" => """
    ---
    name: agent-browser
    description: Browser automation with Playwright
    allowed-tools: Bash(npx agent-browser:*)
    ---

    # Agent Browser

    Browser automation skill. See references for details.
    """,
    "references/commands.md" => "# Commands\n\nCommand reference for agent-browser.",
    "templates/form-automation.sh" => "#!/bin/bash\necho 'form automation template'"
  }

  @single_file_content """
  ---
  name: single-file-skill
  description: A simple single-file skill
  ---

  # Single File Skill

  Uses React and Node.js.
  """

  setup do
    # Kill any lingering runner processes
    Registry.select(SkillToSandbox.PipelineRegistry, [
      {{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}
    ])
    |> Enum.each(fn {_key, pid} ->
      if Process.alive?(pid), do: Process.exit(pid, :kill)
    end)

    Process.sleep(50)
    Ecto.Adapters.SQL.Sandbox.mode(SkillToSandbox.Repo, {:shared, self()})

    :ok
  end

  defp create_test_spec(skill) do
    Analysis.create_spec(%{
      skill_id: skill.id,
      base_image: "node:20-slim",
      system_packages: ["git", "curl"],
      runtime_deps: %{"manager" => "npm", "packages" => %{}},
      tool_configs: %{
        "cli" => %{
          "shell" => "/bin/bash",
          "working_dir" => "/workspace",
          "path_additions" => [],
          "timeout_seconds" => 30
        },
        "web_search" => %{"enabled" => true}
      },
      eval_goals: [
        "Easy: task 1",
        "Easy: task 2",
        "Medium: task 3",
        "Medium: task 4",
        "Hard: task 5"
      ],
      status: "draft"
    })
  end

  defp wait_for_ready(run_id, timeout_ms \\ 180_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    wait_loop = fn wait_loop ->
      status = Runner.get_status(run_id)

      case status.status do
        :ready ->
          {:ok, status}

        :failed ->
          {:error, status.error}

        _ ->
          if System.monotonic_time(:millisecond) > deadline do
            {:error, "Timeout waiting for ready (last status: #{status.status})"}
          else
            Process.sleep(500)
            wait_loop.(wait_loop)
          end
      end
    end

    wait_loop.(wait_loop)
  end

  defp cleanup_container(sandbox_id) do
    if sandbox_id do
      sandbox = Sandboxes.get_sandbox!(sandbox_id)
      if sandbox.container_id, do: Docker.remove_container(sandbox.container_id)
      if sandbox.image_id, do: Docker.remove_image(sandbox.image_id)
    end
  end

  describe "directory skill (agent-browser structure) pipeline" do
    @tag :docker
    test "runs pipeline to completion and container has /workspace/skill with full file tree" do
      # Create directory skill with agent-browser structure
      {:ok, skill} =
        Skills.create_skill(%{
          name: "agent-browser",
          description: "Browser automation",
          raw_content: @agent_browser_file_tree["SKILL.md"],
          source_type: "directory",
          source_root_url:
            "https://github.com/vercel-labs/agent-browser/tree/main/skills/agent-browser",
          file_tree: @agent_browser_file_tree,
          parsed_data: %{
            "name" => "agent-browser",
            "mentioned_tools" => ["cli_execution"],
            "mentioned_frameworks" => []
          }
        })

      {:ok, spec} = create_test_spec(skill)
      {:ok, _} = Analysis.approve_spec(spec)

      {:ok, run} =
        Pipelines.create_run(%{
          skill_id: skill.id,
          sandbox_spec_id: spec.id,
          status: "reviewing",
          current_step: 3,
          started_at: DateTime.utc_now()
        })

      Phoenix.PubSub.subscribe(SkillToSandbox.PubSub, "pipeline:#{run.id}")

      {:ok, _pid} = Runner.start_link(%{run_id: run.id, skill_id: skill.id, resume: true})

      # Approve to trigger build
      Runner.approve_spec(run.id)

      case wait_for_ready(run.id) do
        {:ok, status} ->
          assert status.sandbox_id
          sandbox_id = status.sandbox_id

          # Verify container has /workspace/skill with expected files
          sandbox = Sandboxes.get_sandbox!(sandbox_id)
          container_id = sandbox.container_id

          assert {:ok, "OK"} =
                   Docker.exec_in_container(
                     container_id,
                     "test -f /workspace/skill/SKILL.md && echo OK",
                     timeout: 10_000
                   )

          assert {:ok, "OK"} =
                   Docker.exec_in_container(
                     container_id,
                     "test -f /workspace/skill/references/commands.md && echo OK",
                     timeout: 10_000
                   )

          assert {:ok, "OK"} =
                   Docker.exec_in_container(
                     container_id,
                     "test -f /workspace/skill/templates/form-automation.sh && echo OK",
                     timeout: 10_000
                   )

          # Verify template is executable
          assert {:ok, output} =
                   Docker.exec_in_container(
                     container_id,
                     "test -x /workspace/skill/templates/form-automation.sh && echo OK",
                     timeout: 10_000
                   )

          assert output =~ "OK"

          # Verify SKILL_PATH env
          assert {:ok, env_output} =
                   Docker.exec_in_container(
                     container_id,
                     "echo $SKILL_PATH",
                     timeout: 10_000
                   )

          assert env_output =~ "/workspace/skill"

          # Cleanup
          cleanup_container(sandbox_id)

        {:error, reason} ->
          # Try to cleanup any partial sandbox
          run = Pipelines.get_run!(run.id)
          if run.sandbox_id, do: cleanup_container(run.sandbox_id)
          flunk("Pipeline failed: #{inspect(reason)}")
      end
    end
  end

  describe "single-file skill backward compatibility" do
    @tag :docker
    test "runs pipeline to completion and container has /workspace/skill/SKILL.md" do
      {:ok, skill} =
        Skills.create_skill(%{
          name: "single-file-skill",
          description: "A simple skill",
          raw_content: @single_file_content,
          source_type: "file",
          file_tree: %{"SKILL.md" => @single_file_content},
          parsed_data: %{
            "name" => "single-file-skill",
            "mentioned_tools" => ["web_search", "cli_execution"],
            "mentioned_frameworks" => ["React", "Node.js"]
          }
        })

      {:ok, spec} = create_test_spec(skill)
      {:ok, _} = Analysis.approve_spec(spec)

      {:ok, run} =
        Pipelines.create_run(%{
          skill_id: skill.id,
          sandbox_spec_id: spec.id,
          status: "reviewing",
          current_step: 3,
          started_at: DateTime.utc_now()
        })

      Phoenix.PubSub.subscribe(SkillToSandbox.PubSub, "pipeline:#{run.id}")

      {:ok, _pid} = Runner.start_link(%{run_id: run.id, skill_id: skill.id, resume: true})
      Runner.approve_spec(run.id)

      case wait_for_ready(run.id) do
        {:ok, status} ->
          assert status.sandbox_id
          sandbox_id = status.sandbox_id

          sandbox = Sandboxes.get_sandbox!(sandbox_id)

          # Single-file skill: skill/SKILL.md should exist
          assert {:ok, "OK"} =
                   Docker.exec_in_container(
                     sandbox.container_id,
                     "test -f /workspace/skill/SKILL.md && echo OK",
                     timeout: 10_000
                   )

          # Content should match
          assert {:ok, content} =
                   Docker.exec_in_container(
                     sandbox.container_id,
                     "cat /workspace/skill/SKILL.md",
                     timeout: 10_000
                   )

          assert content =~ "single-file-skill"
          assert content =~ "Single File Skill"

          cleanup_container(sandbox_id)

        {:error, reason} ->
          run = Pipelines.get_run!(run.id)
          if run.sandbox_id, do: cleanup_container(run.sandbox_id)
          flunk("Pipeline failed: #{inspect(reason)}")
      end
    end
  end
end
