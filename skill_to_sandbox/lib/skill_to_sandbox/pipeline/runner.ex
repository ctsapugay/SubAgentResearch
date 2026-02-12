defmodule SkillToSandbox.Pipeline.Runner do
  @moduledoc """
  GenServer that manages a single pipeline run's lifecycle.

  Implements a state machine with the following transitions:

      pending → parsing → analyzing → reviewing → building → configuring → ready
                                                                        ↘ failed

  Every state transition is:
  1. Written to the `pipeline_runs` DB table (persistence)
  2. Broadcast via PubSub (real-time UI updates)

  Heavy operations (LLM calls, Docker builds) are spawned as monitored
  Tasks under `SkillToSandbox.TaskSupervisor` to avoid blocking the
  GenServer message loop.
  """
  use GenServer

  require Logger

  alias SkillToSandbox.{Skills, Pipelines, Analysis, Sandboxes}
  alias SkillToSandbox.Analysis.Analyzer
  alias SkillToSandbox.Skills.Parser
  alias SkillToSandbox.Sandbox.{BuildContext, Docker}

  defstruct [
    :run_id,
    :skill_id,
    :sandbox_spec_id,
    :sandbox_id,
    :status,
    :error,
    :task_ref,
    step_timings: %{},
    step_started_at: nil
  ]

  # -------------------------------------------------------------------
  # Client API
  # -------------------------------------------------------------------

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: via_tuple(args.run_id))
  end

  @doc "Approve the reviewed spec and proceed to building."
  def approve_spec(run_id) do
    GenServer.cast(via_tuple(run_id), :approve_spec)
  end

  @doc "Request re-analysis of the skill."
  def re_analyze(run_id) do
    GenServer.cast(via_tuple(run_id), :re_analyze)
  end

  @doc "Retry a failed pipeline run from the beginning."
  def retry(run_id) do
    GenServer.cast(via_tuple(run_id), :retry)
  end

  @doc "Get the current pipeline status synchronously."
  def get_status(run_id) do
    GenServer.call(via_tuple(run_id), :get_status)
  end

  @doc "Check if a runner process is alive for the given run_id."
  def alive?(run_id) do
    case Registry.lookup(SkillToSandbox.PipelineRegistry, run_id) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  defp via_tuple(run_id) do
    {:via, Registry, {SkillToSandbox.PipelineRegistry, run_id}}
  end

  # -------------------------------------------------------------------
  # Callbacks
  # -------------------------------------------------------------------

  @impl true
  def init(%{run_id: run_id, skill_id: skill_id} = args) do
    state = %__MODULE__{
      run_id: run_id,
      skill_id: skill_id,
      status: :pending,
      step_timings: %{}
    }

    if args[:resume] do
      send(self(), :resume_from_db)
    else
      send(self(), :start_parsing)
    end

    {:ok, state}
  end

  # -- All handle_info clauses grouped together --

  @impl true
  def handle_info(:resume_from_db, state) do
    run = Pipelines.get_run!(state.run_id)

    state = %{state |
      status: String.to_existing_atom(run.status),
      sandbox_spec_id: run.sandbox_spec_id,
      sandbox_id: run.sandbox_id,
      step_timings: run.step_timings || %{}
    }

    case state.status do
      status when status in [:pending, :parsing] ->
        {:noreply, do_start_parsing(state)}

      :analyzing ->
        {:noreply, do_start_analyzing(state)}

      :reviewing ->
        Logger.info("[Runner] Run ##{state.run_id} resumed at reviewing state")
        {:noreply, state}

      :building ->
        {:noreply, do_start_building(state)}

      :configuring ->
        {:noreply, do_start_configuring(state)}

      terminal when terminal in [:ready, :failed] ->
        Logger.info("[Runner] Run ##{state.run_id} is in terminal state #{terminal}, stopping")
        {:stop, :normal, state}
    end
  end

  def handle_info(:start_parsing, state) do
    {:noreply, do_start_parsing(state)}
  end

  def handle_info({ref, result}, %{task_ref: ref} = state) do
    # The task completed. Demonitor and flush the :DOWN message.
    Process.demonitor(ref, [:flush])
    state = %{state | task_ref: nil}

    case {state.status, result} do
      # Analysis completed successfully
      {:analyzing, {:ok, spec}} ->
        state = record_step_timing(state, :analyzing)

        {:ok, _run} =
          Pipelines.update_run(Pipelines.get_run!(state.run_id), %{
            sandbox_spec_id: spec.id
          })

        state = %{state | sandbox_spec_id: spec.id}
        state = transition(state, :reviewing)
        {:noreply, state}

      # Analysis failed
      {:analyzing, {:error, reason}} ->
        error_msg = "LLM analysis failed: #{format_error(reason)}"
        {:noreply, transition(state, :failed, error_msg)}

      # Docker build completed successfully
      {:building, {:ok, sandbox_id}} ->
        state = record_step_timing(state, :building)
        state = %{state | sandbox_id: sandbox_id}

        {:ok, _run} =
          Pipelines.update_run(Pipelines.get_run!(state.run_id), %{
            sandbox_id: sandbox_id
          })

        {:noreply, do_start_configuring(state)}

      # Docker build failed
      {:building, {:error, reason}} ->
        error_msg = "Docker build failed: #{format_error(reason)}"
        {:noreply, transition(state, :failed, error_msg)}

      # Configuring (verification) completed
      {:configuring, :ok} ->
        state = record_step_timing(state, :configuring)
        {:noreply, transition(state, :ready)}

      # Configuring failed
      {:configuring, {:error, reason}} ->
        error_msg = "Sandbox verification failed: #{format_error(reason)}"
        {:noreply, transition(state, :failed, error_msg)}

      # Unexpected
      {status, result} ->
        Logger.warning(
          "[Runner] Unexpected task result in #{status}: #{inspect(result)}"
        )

        {:noreply, state}
    end
  end

  # Handle task crash
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task_ref: ref} = state) do
    state = %{state | task_ref: nil}
    error_msg = "Background task crashed: #{inspect(reason)}"
    {:noreply, transition(state, :failed, error_msg)}
  end

  # -- Private step functions --

  defp do_start_parsing(state) do
    state = transition(state, :parsing)
    skill = Skills.get_skill!(state.skill_id)

    case Parser.parse(skill.raw_content) do
      {:ok, parsed_data} ->
        # Update the skill's parsed_data if not already set
        if skill.parsed_data == nil || skill.parsed_data == %{} do
          Skills.update_skill(skill, %{parsed_data: parsed_data})
        end

        state = record_step_timing(state, :parsing)
        do_start_analyzing(state)

      {:error, reason} ->
        error_msg = "Parsing failed: #{inspect(reason)}"
        transition(state, :failed, error_msg)
    end
  end

  defp do_start_analyzing(state) do
    state = transition(state, :analyzing)
    skill = Skills.get_skill!(state.skill_id)

    task =
      Task.Supervisor.async_nolink(SkillToSandbox.TaskSupervisor, fn ->
        Analyzer.analyze(skill)
      end)

    %{state | task_ref: task.ref}
  end

  defp do_start_building(state) do
    state = transition(state, :building)

    spec = Analysis.get_spec!(state.sandbox_spec_id)

    task =
      Task.Supervisor.async_nolink(
        SkillToSandbox.TaskSupervisor,
        fn -> execute_docker_build(spec, state.run_id) end,
        timeout: :infinity
      )

    %{state | task_ref: task.ref}
  end

  defp do_start_configuring(state) do
    state = transition(state, :configuring)

    # Verify the container is running and tools are accessible
    task =
      Task.Supervisor.async_nolink(SkillToSandbox.TaskSupervisor, fn ->
        verify_sandbox(state.sandbox_id)
      end)

    %{state | task_ref: task.ref}
  end

  # -- User actions via casts --

  @impl true
  def handle_cast(:approve_spec, %{status: :reviewing} = state) do
    spec = Analysis.get_spec!(state.sandbox_spec_id)
    {:ok, _approved} = Analysis.approve_spec(spec)
    state = record_step_timing(state, :reviewing)
    {:noreply, do_start_building(state)}
  end

  def handle_cast(:approve_spec, state) do
    Logger.warning("[Runner] approve_spec called in invalid state: #{state.status}")
    {:noreply, state}
  end

  @impl true
  def handle_cast(:re_analyze, %{status: :reviewing} = state) do
    {:noreply, do_start_analyzing(state)}
  end

  def handle_cast(:re_analyze, state) do
    Logger.warning("[Runner] re_analyze called in invalid state: #{state.status}")
    {:noreply, state}
  end

  @impl true
  def handle_cast(:retry, %{status: :failed} = state) do
    state = %{state | error: nil, step_timings: %{}}
    {:noreply, do_start_parsing(state)}
  end

  def handle_cast(:retry, state) do
    Logger.warning("[Runner] retry called in invalid state: #{state.status}")
    {:noreply, state}
  end

  # -- Synchronous status query --

  @impl true
  def handle_call(:get_status, _from, state) do
    reply = %{
      run_id: state.run_id,
      skill_id: state.skill_id,
      status: state.status,
      sandbox_spec_id: state.sandbox_spec_id,
      sandbox_id: state.sandbox_id,
      error: state.error,
      step_timings: state.step_timings
    }

    {:reply, reply, state}
  end

  # -------------------------------------------------------------------
  # Docker build execution
  # -------------------------------------------------------------------

  defp execute_docker_build(spec, run_id) do
    tag = "sandbox-#{run_id}-#{:erlang.unique_integer([:positive])}"

    with {:ok, context_dir, dockerfile_content} <- BuildContext.assemble(spec),
         # Store the generated Dockerfile content in the spec
         {:ok, _spec} <- Analysis.update_spec(spec, %{dockerfile_content: dockerfile_content}),
         {:ok, _build_output} <- Docker.build_image(context_dir, tag),
         {:ok, container_id} <- Docker.run_container(tag, "sandbox-run-#{run_id}"),
         {:ok, sandbox} <-
           Sandboxes.create_sandbox(%{
             sandbox_spec_id: spec.id,
             container_id: String.trim(container_id),
             image_id: tag,
             status: "running"
           }) do
      # Clean up the build context
      BuildContext.cleanup(context_dir)
      {:ok, sandbox.id}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  # -------------------------------------------------------------------
  # Sandbox verification
  # -------------------------------------------------------------------

  defp verify_sandbox(sandbox_id) do
    sandbox = Sandboxes.get_sandbox!(sandbox_id)

    case Docker.container_status(sandbox.container_id) do
      {:ok, "running"} ->
        # Verify the tool manifest exists inside the container
        case Docker.exec_in_container(
               sandbox.container_id,
               "test -f /workspace/tool_manifest.json && echo OK",
               timeout: 10_000
             ) do
          {:ok, "OK"} ->
            :ok

          {:ok, _other} ->
            {:error, "tool_manifest.json not found in container"}

          {:error, reason} ->
            {:error, "Failed to verify tools: #{format_error(reason)}"}
        end

      {:ok, other_status} ->
        {:error, "Container is not running (status: #{other_status})"}

      {:error, reason} ->
        {:error, "Cannot inspect container: #{format_error(reason)}"}
    end
  end

  # -------------------------------------------------------------------
  # State transition (DB + PubSub)
  # -------------------------------------------------------------------

  defp transition(state, new_status, error \\ nil) do
    step = status_to_step(new_status)
    now = DateTime.utc_now()

    attrs = %{
      status: to_string(new_status),
      current_step: step,
      error_message: error
    }

    attrs =
      if new_status in [:ready, :failed] do
        Map.put(attrs, :completed_at, now)
      else
        attrs
      end

    # Update step_timings in state
    step_timings = state.step_timings

    attrs =
      if step_timings != %{} do
        Map.put(attrs, :step_timings, step_timings)
      else
        attrs
      end

    # Persist to DB
    run = Pipelines.get_run!(state.run_id)
    {:ok, _updated_run} = Pipelines.update_run(run, attrs)

    # Broadcast via PubSub
    Phoenix.PubSub.broadcast(
      SkillToSandbox.PubSub,
      "pipeline:#{state.run_id}",
      {:pipeline_update,
       %{
         run_id: state.run_id,
         status: new_status,
         current_step: step,
         error: error,
         sandbox_spec_id: state.sandbox_spec_id,
         sandbox_id: state.sandbox_id,
         step_timings: step_timings
       }}
    )

    Logger.info("[Runner] Run ##{state.run_id}: #{state.status} → #{new_status}")

    %{state | status: new_status, error: error, step_started_at: System.monotonic_time(:millisecond)}
  end

  defp record_step_timing(state, step_name) do
    if state.step_started_at do
      elapsed = System.monotonic_time(:millisecond) - state.step_started_at
      timings = Map.put(state.step_timings, to_string(step_name), elapsed)
      %{state | step_timings: timings}
    else
      state
    end
  end

  defp status_to_step(:pending), do: 0
  defp status_to_step(:parsing), do: 1
  defp status_to_step(:analyzing), do: 2
  defp status_to_step(:reviewing), do: 3
  defp status_to_step(:building), do: 4
  defp status_to_step(:configuring), do: 5
  defp status_to_step(:ready), do: 6
  defp status_to_step(:failed), do: -1

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
