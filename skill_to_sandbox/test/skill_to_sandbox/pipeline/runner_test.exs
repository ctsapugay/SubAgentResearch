defmodule SkillToSandbox.Pipeline.RunnerTest do
  @moduledoc """
  Tests for the Pipeline Runner GenServer.

  Tests the state machine transitions, DB persistence, PubSub broadcasting,
  and error handling. Uses shared Ecto sandbox mode so Runner and Task
  processes can access the database.
  """
  use SkillToSandbox.DataCase

  alias SkillToSandbox.{Skills, Pipelines, Analysis}
  alias SkillToSandbox.Pipeline.Runner

  @skill_content """
  ---
  name: test-skill
  description: A test skill
  ---

  # Test Skill

  This is a test skill for testing the pipeline runner.

  Uses React, Node.js, and npm.
  Supports web search and CLI execution.
  """

  setup do
    # Kill any lingering runner processes from previous tests
    Registry.select(SkillToSandbox.PipelineRegistry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.each(fn {_key, pid} ->
      if Process.alive?(pid), do: Process.exit(pid, :kill)
    end)

    # Small delay to let killed processes unregister
    Process.sleep(50)

    # Allow callers from other processes (Runner GenServer, Task) to use our DB connection.
    # This is needed because the Runner runs in its own process.
    Ecto.Adapters.SQL.Sandbox.mode(SkillToSandbox.Repo, {:shared, self()})

    # Create a test skill
    {:ok, skill} =
      Skills.create_skill(%{
        name: "test-skill",
        description: "A test skill",
        raw_content: @skill_content,
        parsed_data: %{
          "name" => "test-skill",
          "description" => "A test skill",
          "mentioned_tools" => ["web_search", "cli_execution"],
          "mentioned_frameworks" => ["React", "Node.js"],
          "mentioned_dependencies" => [],
          "sections" => ["Test Skill"]
        }
      })

    %{skill: skill}
  end

  describe "start_link/1 and init/1" do
    test "starts a runner process and registers it", %{skill: skill} do
      {:ok, run} = create_run(skill)

      {:ok, pid} = Runner.start_link(%{run_id: run.id, skill_id: skill.id})
      assert Process.alive?(pid)
      assert Runner.alive?(run.id)
    end

    test "initial status transitions from pending through parsing", %{skill: skill} do
      {:ok, run} = create_run(skill)

      # Subscribe to PubSub for this run
      Phoenix.PubSub.subscribe(SkillToSandbox.PubSub, "pipeline:#{run.id}")

      {:ok, _pid} = Runner.start_link(%{run_id: run.id, skill_id: skill.id})

      # Should receive parsing transition
      run_id = run.id
      assert_receive {:pipeline_update, %{status: :parsing, run_id: ^run_id}}, 5_000
    end
  end

  describe "alive?/1" do
    test "returns false for non-existent runner" do
      refute Runner.alive?(99999)
    end
  end

  describe "PubSub broadcasting" do
    test "broadcasts pipeline updates on state transitions", %{skill: skill} do
      {:ok, run} = create_run(skill)
      Phoenix.PubSub.subscribe(SkillToSandbox.PubSub, "pipeline:#{run.id}")

      {:ok, _pid} = Runner.start_link(%{run_id: run.id, skill_id: skill.id})

      # Should receive at least a parsing update
      assert_receive {:pipeline_update, %{status: :parsing}}, 5_000
    end

    test "broadcasts analyzing status after parsing", %{skill: skill} do
      {:ok, run} = create_run(skill)
      Phoenix.PubSub.subscribe(SkillToSandbox.PubSub, "pipeline:#{run.id}")

      {:ok, _pid} = Runner.start_link(%{run_id: run.id, skill_id: skill.id})

      # Should receive parsing then analyzing
      assert_receive {:pipeline_update, %{status: :parsing}}, 5_000
      assert_receive {:pipeline_update, %{status: :analyzing}}, 5_000
    end
  end

  describe "DB persistence" do
    test "updates pipeline_runs table on state transitions", %{skill: skill} do
      {:ok, run} = create_run(skill)
      Phoenix.PubSub.subscribe(SkillToSandbox.PubSub, "pipeline:#{run.id}")

      {:ok, _pid} = Runner.start_link(%{run_id: run.id, skill_id: skill.id})

      # Wait for parsing to start
      assert_receive {:pipeline_update, %{status: :parsing}}, 5_000

      # Check DB
      updated_run = Pipelines.get_run!(run.id)
      assert updated_run.current_step >= 1
    end

    test "records step_timings after steps complete", %{skill: skill} do
      {:ok, run} = create_run(skill)
      Phoenix.PubSub.subscribe(SkillToSandbox.PubSub, "pipeline:#{run.id}")

      {:ok, _pid} = Runner.start_link(%{run_id: run.id, skill_id: skill.id})

      # Wait for analyzing (which means parsing completed)
      assert_receive {:pipeline_update, %{status: :analyzing}}, 5_000

      # step_timings should include parsing time
      status = Runner.get_status(run.id)
      assert is_map(status.step_timings)
      assert Map.has_key?(status.step_timings, "parsing")
    end
  end

  describe "get_status/1" do
    test "returns current pipeline state", %{skill: skill} do
      {:ok, run} = create_run(skill)

      {:ok, _pid} = Runner.start_link(%{run_id: run.id, skill_id: skill.id})

      # Give it a moment to process
      _ = :sys.get_state(via_tuple(run.id))

      status = Runner.get_status(run.id)
      assert is_map(status)
      assert status.run_id == run.id
      assert status.skill_id == skill.id
      assert is_atom(status.status)
    end
  end

  describe "approve_spec/1 in wrong state" do
    test "logs warning when called in non-reviewing state", %{skill: skill} do
      {:ok, run} = create_run(skill)
      Phoenix.PubSub.subscribe(SkillToSandbox.PubSub, "pipeline:#{run.id}")

      {:ok, _pid} = Runner.start_link(%{run_id: run.id, skill_id: skill.id})

      # Wait for at least parsing to start
      assert_receive {:pipeline_update, %{status: :parsing}}, 5_000

      # This should not crash the process
      Runner.approve_spec(run.id)
      _ = :sys.get_state(via_tuple(run.id))

      # Process should still be alive
      assert Runner.alive?(run.id)
    end
  end

  describe "retry/1 in wrong state" do
    test "logs warning when called in non-failed state", %{skill: skill} do
      {:ok, run} = create_run(skill)
      Phoenix.PubSub.subscribe(SkillToSandbox.PubSub, "pipeline:#{run.id}")

      {:ok, _pid} = Runner.start_link(%{run_id: run.id, skill_id: skill.id})

      # Wait for parsing
      assert_receive {:pipeline_update, %{status: :parsing}}, 5_000

      # This should not crash the process
      Runner.retry(run.id)
      _ = :sys.get_state(via_tuple(run.id))

      assert Runner.alive?(run.id)
    end
  end

  describe "resume mode" do
    test "resumes a runner at reviewing state", %{skill: skill} do
      # Create a spec so we have something to review
      {:ok, spec} = create_test_spec(skill)

      {:ok, run} =
        Pipelines.create_run(%{
          skill_id: skill.id,
          sandbox_spec_id: spec.id,
          status: "reviewing",
          current_step: 3,
          started_at: DateTime.utc_now()
        })

      # Start in resume mode
      {:ok, pid} = Runner.start_link(%{run_id: run.id, skill_id: skill.id, resume: true})
      assert Process.alive?(pid)

      # Wait for the resume to process
      _ = :sys.get_state(via_tuple(run.id))

      # Should be in reviewing state
      status = Runner.get_status(run.id)
      assert status.status == :reviewing
      assert status.sandbox_spec_id == spec.id
    end

    test "resumes a runner at failed state (stops)", %{skill: skill} do
      {:ok, run} =
        Pipelines.create_run(%{
          skill_id: skill.id,
          status: "failed",
          current_step: -1,
          error_message: "Previous failure",
          started_at: DateTime.utc_now(),
          completed_at: DateTime.utc_now()
        })

      # Start in resume mode -- should stop since failed is terminal
      result = Runner.start_link(%{run_id: run.id, skill_id: skill.id, resume: true})

      case result do
        {:ok, pid} ->
          ref = Process.monitor(pid)
          assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000

        {:error, _} ->
          # Process may exit before start_link returns -- that's fine
          :ok
      end
    end
  end

  describe "Pipeline.Supervisor.start_pipeline/1" do
    test "creates a run and starts a runner", %{skill: skill} do
      alias SkillToSandbox.Pipeline.Supervisor, as: PipelineSupervisor

      {:ok, run} = PipelineSupervisor.start_pipeline(skill.id)

      assert run.skill_id == skill.id
      assert run.status == "pending"
      assert run.started_at != nil

      # Give runner a moment to register
      Process.sleep(100)
      assert Runner.alive?(run.id)
    end
  end

  describe "Recovery" do
    test "recover_on_startup marks building runs as failed", %{skill: skill} do
      {:ok, run} =
        Pipelines.create_run(%{
          skill_id: skill.id,
          status: "building",
          current_step: 4,
          started_at: DateTime.utc_now()
        })

      SkillToSandbox.Pipeline.Recovery.recover_on_startup()

      updated = Pipelines.get_run!(run.id)
      assert updated.status == "failed"
      assert updated.error_message =~ "Interrupted by application restart"
    end

    test "recover_on_startup resumes reviewing runs", %{skill: skill} do
      {:ok, spec} = create_test_spec(skill)

      {:ok, run} =
        Pipelines.create_run(%{
          skill_id: skill.id,
          sandbox_spec_id: spec.id,
          status: "reviewing",
          current_step: 3,
          started_at: DateTime.utc_now()
        })

      SkillToSandbox.Pipeline.Recovery.recover_on_startup()

      # Should have started a runner process
      Process.sleep(1_500)
      assert Runner.alive?(run.id)
    end
  end

  # -- Helpers --

  defp create_run(skill) do
    Pipelines.create_run(%{
      skill_id: skill.id,
      status: "pending",
      current_step: 0,
      started_at: DateTime.utc_now()
    })
  end

  defp create_test_spec(skill) do
    Analysis.create_spec(%{
      skill_id: skill.id,
      base_image: "node:20-slim",
      system_packages: ["git", "curl"],
      runtime_deps: %{"manager" => "npm", "packages" => %{"react" => "^18"}},
      tool_configs: %{
        "cli" => %{"shell" => "/bin/bash"},
        "web_search" => %{"enabled" => true}
      },
      eval_goals: [
        "Easy: test 1",
        "Easy: test 2",
        "Medium: test 3",
        "Medium: test 4",
        "Hard: test 5"
      ],
      status: "draft"
    })
  end

  defp via_tuple(run_id) do
    {:via, Registry, {SkillToSandbox.PipelineRegistry, run_id}}
  end
end
