defmodule SkillToSandboxWeb.PipelineLive.Show do
  @moduledoc """
  Pipeline run status view with real-time updates via PubSub.

  Subscribes to `"pipeline:<run_id>"` PubSub topic and receives
  `{:pipeline_update, payload}` messages from the Pipeline Runner
  GenServer, triggering LiveView re-renders for real-time progress.

  When the pipeline reaches the "reviewing" state, this page displays
  the LLM-generated sandbox specification with editable fields.
  The user can approve the spec to proceed with Docker build, or
  request re-analysis.
  """
  use SkillToSandboxWeb, :live_view

  alias SkillToSandbox.Skills
  alias SkillToSandbox.Pipelines
  alias SkillToSandbox.Analysis
  alias SkillToSandbox.Pipeline.Runner

  @steps [
    {1, "Parse", "hero-document-text-micro"},
    {2, "Analyze", "hero-sparkles-micro"},
    {3, "Review", "hero-eye-micro"},
    {4, "Build", "hero-wrench-screwdriver-micro"},
    {5, "Configure", "hero-cog-6-tooth-micro"},
    {6, "Ready", "hero-check-circle-micro"}
  ]

  @impl true
  def mount(%{"id" => skill_id} = params, _session, socket) do
    skill = Skills.get_skill!(skill_id)
    runs = Pipelines.runs_for_skill(skill.id)

    # If a specific run is requested via ?run=ID, load it with its spec
    {active_run, spec} = load_active_run(params, runs)

    # Subscribe to PubSub for real-time updates
    if active_run && connected?(socket) do
      Phoenix.PubSub.subscribe(SkillToSandbox.PubSub, "pipeline:#{active_run.id}")
    end

    socket =
      socket
      |> assign(:page_title, "Pipeline — #{skill.name}")
      |> assign(:skill, skill)
      |> assign(:runs, runs)
      |> assign(:active_run, active_run)
      |> assign(:spec, spec)
      |> assign(:steps, @steps)
      |> assign(:re_analyzing, false)
      |> assign(:approving, false)
      |> assign(:building, active_run && active_run.status in ["building", "configuring"])
      |> assign_spec_form(spec)

    {:ok, socket}
  end

  # -- PubSub handler: real-time pipeline updates --

  @impl true
  def handle_info({:pipeline_update, payload}, socket) do
    # Reload the run and spec from DB for fresh data
    run = Pipelines.get_run!(payload.run_id)
    runs = Pipelines.runs_for_skill(socket.assigns.skill.id)

    spec =
      if payload.sandbox_spec_id do
        Analysis.get_spec!(payload.sandbox_spec_id)
      else
        socket.assigns.spec
      end

    socket =
      socket
      |> assign(:active_run, run)
      |> assign(:runs, runs)
      |> assign(:spec, spec)
      |> assign(:re_analyzing, false)
      |> assign(:approving, false)
      |> assign(:building, run.status in ["building", "configuring"])
      |> assign_spec_form(spec)

    # Flash messages for key transitions
    socket =
      case payload.status do
        :reviewing ->
          put_flash(socket, :info, "Analysis complete! Review the specification below.")

        :building ->
          put_flash(socket, :info, "Building Docker container... this may take a few minutes.")

        :configuring ->
          put_flash(socket, :info, "Verifying sandbox tools...")

        :ready ->
          put_flash(socket, :info, "Sandbox is ready! View it in the Sandboxes section.")

        :failed ->
          put_flash(socket, :error, payload.error || "Pipeline failed.")

        _ ->
          socket
      end

    {:noreply, socket}
  end

  # -- Events --

  @impl true
  def handle_event("update_spec", %{"spec" => spec_params}, socket) do
    spec = socket.assigns.spec

    # Parse system_packages from comma-separated string
    spec_params = parse_spec_params(spec_params)

    case Analysis.update_spec(spec, spec_params) do
      {:ok, updated_spec} ->
        {:noreply,
         socket
         |> assign(:spec, updated_spec)
         |> assign_spec_form(updated_spec)}

      {:error, changeset} ->
        {:noreply, assign(socket, :spec_form, to_form(changeset, as: :spec))}
    end
  end

  @impl true
  def handle_event("approve_spec", _params, socket) do
    run = socket.assigns.active_run
    socket = assign(socket, :approving, true)

    # Delegate to the Runner GenServer
    Runner.approve_spec(run.id)

    {:noreply,
     socket
     |> put_flash(:info, "Spec approved! Starting Docker build...")}
  end

  @impl true
  def handle_event("re_analyze", _params, socket) do
    run = socket.assigns.active_run
    socket = assign(socket, :re_analyzing, true)

    # Delegate to the Runner GenServer
    Runner.re_analyze(run.id)

    {:noreply,
     socket
     |> put_flash(:info, "Re-analyzing with LLM...")}
  end

  @impl true
  def handle_event("retry", _params, socket) do
    run = socket.assigns.active_run

    if Runner.alive?(run.id) do
      Runner.retry(run.id)
    else
      # Runner process is gone (e.g., after app restart) -- start a fresh pipeline
      alias SkillToSandbox.Pipeline.Supervisor, as: PipelineSupervisor
      PipelineSupervisor.resume_pipeline(run.id, socket.assigns.skill.id)
      Runner.retry(run.id)
    end

    {:noreply,
     socket
     |> put_flash(:info, "Retrying pipeline...")}
  end

  @impl true
  def handle_event("add_eval_goal", _params, socket) do
    spec = socket.assigns.spec
    current_goals = spec.eval_goals || []
    new_goals = current_goals ++ ["New: Describe a concrete task here"]

    case Analysis.update_spec(spec, %{eval_goals: new_goals}) do
      {:ok, updated_spec} ->
        {:noreply,
         socket
         |> assign(:spec, updated_spec)
         |> assign_spec_form(updated_spec)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_eval_goal", %{"index" => index_str}, socket) do
    spec = socket.assigns.spec
    index = String.to_integer(index_str)
    current_goals = spec.eval_goals || []

    new_goals = List.delete_at(current_goals, index)

    case Analysis.update_spec(spec, %{eval_goals: new_goals}) do
      {:ok, updated_spec} ->
        {:noreply,
         socket
         |> assign(:spec, updated_spec)
         |> assign_spec_form(updated_spec)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_eval_goal", params, socket) do
    index_str = params["index"]
    value = params["value"]

    if index_str && value do
      spec = socket.assigns.spec
      index = String.to_integer(index_str)
      current_goals = spec.eval_goals || []

      new_goals = List.replace_at(current_goals, index, value)

      case Analysis.update_spec(spec, %{eval_goals: new_goals}) do
        {:ok, updated_spec} ->
          {:noreply,
           socket
           |> assign(:spec, updated_spec)}

        {:error, _} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add_package", %{"package" => package}, socket) do
    package = String.trim(package)

    if package != "" do
      spec = socket.assigns.spec
      current_packages = spec.system_packages || []
      new_packages = Enum.uniq(current_packages ++ [package])

      case Analysis.update_spec(spec, %{system_packages: new_packages}) do
        {:ok, updated_spec} ->
          {:noreply,
           socket
           |> assign(:spec, updated_spec)
           |> assign_spec_form(updated_spec)}

        {:error, _} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_package", %{"package" => package}, socket) do
    spec = socket.assigns.spec
    current_packages = spec.system_packages || []
    new_packages = List.delete(current_packages, package)

    case Analysis.update_spec(spec, %{system_packages: new_packages}) do
      {:ok, updated_spec} ->
        {:noreply,
         socket
         |> assign(:spec, updated_spec)
         |> assign_spec_form(updated_spec)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_runtime_dep", %{"name" => name}, socket) do
    spec = socket.assigns.spec
    current_packages = get_in(spec.runtime_deps, ["packages"]) || %{}
    new_packages = Map.delete(current_packages, name)
    new_runtime_deps = Map.put(spec.runtime_deps, "packages", new_packages)

    case Analysis.update_spec(spec, %{runtime_deps: new_runtime_deps}) do
      {:ok, updated_spec} ->
        {:noreply,
         socket
         |> assign(:spec, updated_spec)
         |> assign_spec_form(updated_spec)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add_runtime_dep", %{"dep_name" => name, "dep_version" => version}, socket) do
    name = String.trim(name)
    version = String.trim(version)

    if name != "" do
      spec = socket.assigns.spec
      current_packages = get_in(spec.runtime_deps, ["packages"]) || %{}
      new_packages = Map.put(current_packages, name, if(version == "", do: "latest", else: version))
      new_runtime_deps = Map.put(spec.runtime_deps, "packages", new_packages)

      case Analysis.update_spec(spec, %{runtime_deps: new_runtime_deps}) do
        {:ok, updated_spec} ->
          {:noreply,
           socket
           |> assign(:spec, updated_spec)
           |> assign_spec_form(updated_spec)}

        {:error, _} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # -- Render --

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <a href={"/skills/#{@skill.id}"} class="back-btn">
        <.icon name="hero-arrow-left-micro" class="size-3.5" /> Back to Skill
      </a>

      <div>
        <h1 class="text-2xl font-semibold tracking-tight">Pipeline</h1>
        <p class="text-sm text-base-content/45 mt-0.5">
          {@skill.name} — skill-to-sandbox conversion
        </p>
      </div>

      <%!-- Step Indicator --%>
      <div class="glass-panel p-5">
        <div class="flex items-center justify-between">
          <%= for {num, label, icon} <- @steps do %>
            <div class="flex flex-col items-center gap-1.5 flex-1">
              <span class={[
                "size-9 rounded-full flex items-center justify-center text-xs font-medium transition-all",
                step_classes(num, current_step(@active_run))
              ]}>
                <%= if num < current_step(@active_run) do %>
                  <.icon name="hero-check-micro" class="size-4" />
                <% else %>
                  <.icon name={icon} class="size-4" />
                <% end %>
              </span>
              <span class={[
                "text-[11px] font-medium transition-colors",
                if(num <= current_step(@active_run),
                  do: "text-base-content/70",
                  else: "text-base-content/25"
                )
              ]}>
                {label}
              </span>
            </div>
            <%= if num < 6 do %>
              <div class={[
                "w-full h-px flex-shrink-0 max-w-12 transition-colors",
                if(num < current_step(@active_run),
                  do: "bg-primary/40",
                  else: "bg-base-content/10"
                )
              ]} />
            <% end %>
          <% end %>
        </div>
      </div>

      <%!-- Active Run Status --%>
      <%= if @active_run do %>
        <div class={[
          "glass-panel p-4 flex items-center gap-3",
          status_glow(@active_run.status)
        ]}>
          <span class={["size-2.5 rounded-full", run_dot(@active_run.status)]} />
          <%= if animating?(@active_run.status) do %>
            <.icon name="hero-arrow-path" class="size-4 animate-spin text-base-content/30" />
          <% end %>
          <span class="text-sm font-medium text-base-content/70">
            {status_label(@active_run.status)}
          </span>
          <%!-- Step Timings --%>
          <%= if @active_run.step_timings && @active_run.step_timings != %{} do %>
            <div class="ml-auto flex gap-3">
              <%= for {step, ms} <- @active_run.step_timings do %>
                <span class="text-[10px] font-mono text-base-content/25">
                  {step}: {format_duration(ms)}
                </span>
              <% end %>
            </div>
          <% end %>
          <%= if @active_run.error_message && @active_run.step_timings in [nil, %{}] do %>
            <span class="text-xs text-error/70 ml-auto max-w-md truncate">
              {@active_run.error_message}
            </span>
          <% end %>
        </div>
      <% end %>

      <%!-- Spec Review UI (visible when reviewing) --%>
      <%= if @spec && reviewing?(@active_run) do %>
        {render_spec_review(assigns)}
      <% end %>

      <%!-- Building / Configuring state --%>
      <%= if @building do %>
        <div class="glass-panel p-6">
          <div class="flex items-center gap-4">
            <div class="size-12 rounded-xl bg-warning/15 flex items-center justify-center shrink-0">
              <.icon name="hero-arrow-path" class="size-6 text-warning animate-spin" />
            </div>
            <div>
              <h3 class="text-sm font-semibold text-base-content">
                <%= if @active_run.status == "building" do %>
                  Building Docker Container
                <% else %>
                  Verifying Sandbox Tools
                <% end %>
              </h3>
              <p class="text-sm text-base-content/50 mt-1">
                <%= if @active_run.status == "building" do %>
                  Docker is building the sandbox image. This may take a few minutes depending on the number of dependencies...
                <% else %>
                  Checking that the container is running and tools are accessible...
                <% end %>
              </p>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Approved / Building state: spec summary --%>
      <%= if @spec && approved_or_later?(@active_run) do %>
        {render_spec_summary(assigns)}
      <% end %>

      <%!-- Ready state --%>
      <%= if @active_run && @active_run.status == "ready" do %>
        <div class="glass-panel p-6 glow-primary">
          <div class="flex items-start gap-4">
            <div class="size-12 rounded-xl bg-success/15 flex items-center justify-center shrink-0">
              <.icon name="hero-check-circle" class="size-6 text-success" />
            </div>
            <div>
              <h3 class="text-sm font-semibold text-success">Sandbox Ready</h3>
              <p class="text-sm text-base-content/50 mt-1">
                Your sandbox container is running and tools are verified.
              </p>
              <%= if @active_run.sandbox_id do %>
                <a
                  href={"/sandboxes/#{@active_run.sandbox_id}"}
                  class="inline-flex items-center gap-1.5 text-sm font-medium text-primary hover:text-primary/80 mt-3 transition-colors"
                >
                  <.icon name="hero-arrow-top-right-on-square-micro" class="size-4" />
                  View Sandbox
                </a>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Failed state --%>
      <%= if @active_run && @active_run.status == "failed" do %>
        <div class="glass-panel p-6">
          <div class="flex items-start gap-3">
            <span class="size-10 rounded-xl bg-error/15 flex items-center justify-center shrink-0">
              <.icon name="hero-exclamation-triangle" class="size-5 text-error" />
            </span>
            <div class="flex-1">
              <h3 class="text-sm font-semibold text-error">Pipeline Failed</h3>
              <p class="text-sm text-base-content/50 mt-1">
                {@active_run.error_message || "An unknown error occurred."}
              </p>
              <div class="flex gap-3 mt-4">
                <button
                  id="retry-pipeline-btn"
                  phx-click="retry"
                  class="btn btn-primary btn-sm shadow-lg shadow-primary/20"
                >
                  <.icon name="hero-arrow-path-micro" class="size-4" /> Retry Pipeline
                </button>
                <a
                  href={"/skills/#{@skill.id}"}
                  class="inline-flex items-center gap-1 text-xs text-accent hover:text-accent/80 transition-colors self-center"
                >
                  <.icon name="hero-arrow-left-micro" class="size-3" /> Back to skill
                </a>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- All Pipeline Runs --%>
      <div class="glass-panel overflow-hidden">
        <div class="px-5 py-3.5 border-b border-base-content/5">
          <h2 class="text-sm font-semibold text-base-content">All Runs</h2>
        </div>
        <%= if @runs == [] do %>
          <div class="py-12 text-center">
            <p class="text-sm text-base-content/25">
              No pipeline runs yet. Click "Analyze & Build" on the skill page to start.
            </p>
          </div>
        <% else %>
          <div class="divide-y divide-base-content/5">
            <%= for run <- @runs do %>
              <div class={[
                "flex items-center justify-between px-5 py-3 transition-colors",
                if(@active_run && @active_run.id == run.id,
                  do: "bg-primary/5",
                  else: "hover:bg-base-content/[0.02]"
                )
              ]}>
                <div class="flex items-center gap-3">
                  <span class="inline-flex items-center gap-1.5 text-xs font-medium">
                    <span class={["size-1.5 rounded-full", run_dot(run.status)]} />
                    {run.status}
                  </span>
                  <span class="text-xs text-base-content/35">
                    Step {run.current_step}/6
                  </span>
                  <%= if @active_run && @active_run.id == run.id do %>
                    <span class="text-[10px] font-medium text-primary/60 bg-primary/10 px-1.5 py-0.5 rounded">
                      active
                    </span>
                  <% end %>
                </div>
                <span class="text-xs text-base-content/35">
                  {if run.started_at,
                    do: Calendar.strftime(run.started_at, "%b %d %H:%M"),
                    else: "Not started"}
                </span>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # -- Spec Review subtemplate --

  defp render_spec_review(assigns) do
    ~H"""
    <div class="space-y-5">
      <%!-- Review header --%>
      <div class="glass-panel p-5 glow-accent">
        <div class="flex items-start justify-between">
          <div>
            <h2 class="text-lg font-semibold text-base-content flex items-center gap-2">
              <.icon name="hero-clipboard-document-check" class="size-5 text-accent" />
              Review Sandbox Specification
            </h2>
            <p class="text-sm text-base-content/45 mt-1">
              The LLM has analyzed your skill and produced the specification below.
              Review, edit as needed, then approve to proceed with building.
            </p>
          </div>
          <div class="flex gap-2 shrink-0">
            <button
              id="re-analyze-btn"
              phx-click="re_analyze"
              disabled={@re_analyzing}
              class={[
                "btn btn-outline btn-sm border-base-content/15 text-base-content/70 hover:bg-base-content/5",
                @re_analyzing && "opacity-60 cursor-wait"
              ]}
            >
              <%= if @re_analyzing do %>
                <.icon name="hero-arrow-path" class="size-4 animate-spin" /> Re-analyzing...
              <% else %>
                <.icon name="hero-arrow-path-micro" class="size-4" /> Re-analyze
              <% end %>
            </button>
            <button
              id="approve-spec-btn"
              phx-click="approve_spec"
              disabled={@approving || @re_analyzing}
              class="btn btn-primary btn-sm shadow-lg shadow-primary/20"
            >
              <%= if @approving do %>
                <.icon name="hero-arrow-path" class="size-4 animate-spin" /> Approving...
              <% else %>
                <.icon name="hero-check-micro" class="size-4" /> Approve & Build
              <% end %>
            </button>
          </div>
        </div>
      </div>

      <%!-- Base Image & Package Manager --%>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-5">
        <div class="glass-panel p-5">
          <h3 class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30 mb-3">
            Base Docker Image
          </h3>
          <.form
            for={@spec_form}
            id="spec-base-image-form"
            phx-change="update_spec"
            phx-debounce="500"
          >
            <.input
              field={@spec_form[:base_image]}
              type="text"
              placeholder="e.g. node:20-slim"
              class="font-mono text-sm bg-base-200/50 border-base-content/10 focus:border-primary/40"
            />
          </.form>
        </div>

        <div class="glass-panel p-5">
          <h3 class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30 mb-3">
            Package Manager
          </h3>
          <div class="flex items-center gap-3">
            <span class="text-sm font-mono text-base-content/60 bg-base-200/50 px-3 py-2 rounded-lg border border-base-content/10">
              {get_in(@spec.runtime_deps, ["manager"]) || "N/A"}
            </span>
            <span class="text-xs text-base-content/30">
              {runtime_dep_count(@spec)} dependencies
            </span>
          </div>
        </div>
      </div>

      <%!-- System Packages --%>
      <div class="glass-panel p-5">
        <h3 class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30 mb-3">
          System Packages (apt-get)
        </h3>
        <div class="flex flex-wrap gap-2 mb-3">
          <%= for pkg <- (@spec.system_packages || []) do %>
            <span class="inline-flex items-center gap-1 text-xs font-mono px-2.5 py-1 rounded-full bg-base-content/5 text-base-content/60 group">
              {pkg}
              <button
                phx-click="remove_package"
                phx-value-package={pkg}
                class="text-base-content/20 hover:text-error transition-colors"
                title="Remove"
              >
                <.icon name="hero-x-mark-micro" class="size-3" />
              </button>
            </span>
          <% end %>
        </div>
        <form phx-submit="add_package" class="flex gap-2">
          <input
            type="text"
            name="package"
            placeholder="Add package..."
            class="flex-1 text-xs font-mono bg-base-200/50 border border-base-content/10 rounded-lg px-3 py-1.5 focus:outline-none focus:border-primary/40 text-base-content placeholder:text-base-content/25"
          />
          <button
            type="submit"
            class="btn btn-outline btn-xs border-base-content/15 text-base-content/50"
          >
            <.icon name="hero-plus-micro" class="size-3" /> Add
          </button>
        </form>
      </div>

      <%!-- Runtime Dependencies --%>
      <div class="glass-panel p-5">
        <h3 class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30 mb-3">
          Runtime Dependencies
        </h3>
        <%= if deps_packages(@spec) != %{} do %>
          <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-2 mb-3">
            <%= for {name, version} <- deps_packages(@spec) do %>
              <div class="flex items-center justify-between text-xs font-mono px-3 py-2 rounded-lg bg-base-content/[0.03] border border-base-content/5 group">
                <span class="text-base-content/70">{name}</span>
                <div class="flex items-center gap-2">
                  <span class="text-base-content/35">{version}</span>
                  <button
                    phx-click="remove_runtime_dep"
                    phx-value-name={name}
                    class="text-base-content/15 hover:text-error opacity-0 group-hover:opacity-100 transition-all"
                    title={"Remove #{name}"}
                  >
                    <.icon name="hero-x-mark-micro" class="size-3.5" />
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        <% else %>
          <p class="text-xs text-base-content/30 mb-3">No runtime dependencies specified.</p>
        <% end %>
        <form phx-submit="add_runtime_dep" class="flex gap-2">
          <input
            type="text"
            name="dep_name"
            placeholder="Package name..."
            class="flex-1 text-xs font-mono bg-base-200/50 border border-base-content/10 rounded-lg px-3 py-1.5 focus:outline-none focus:border-primary/40 text-base-content placeholder:text-base-content/25"
          />
          <input
            type="text"
            name="dep_version"
            placeholder="Version (e.g. ^18.0.0)"
            class="w-36 text-xs font-mono bg-base-200/50 border border-base-content/10 rounded-lg px-3 py-1.5 focus:outline-none focus:border-primary/40 text-base-content placeholder:text-base-content/25"
          />
          <button
            type="submit"
            class="btn btn-outline btn-xs border-base-content/15 text-base-content/50"
          >
            <.icon name="hero-plus-micro" class="size-3" /> Add
          </button>
        </form>
      </div>

      <%!-- Tool Configs --%>
      <div class="glass-panel p-5">
        <h3 class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30 mb-3">
          Tool Configuration
        </h3>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <%!-- CLI Tool --%>
          <div class="p-3 rounded-lg bg-base-content/[0.03] border border-base-content/5">
            <div class="flex items-center gap-2 mb-2">
              <.icon name="hero-command-line-micro" class="size-4 text-orange-400" />
              <span class="text-xs font-semibold text-base-content/60">CLI Execution</span>
            </div>
            <%= if cli_config(@spec) do %>
              <div class="space-y-1 text-xs font-mono text-base-content/40">
                <div>shell: {cli_config(@spec)["shell"] || "/bin/bash"}</div>
                <div>working_dir: {cli_config(@spec)["working_dir"] || "/workspace"}</div>
                <div>timeout: {cli_config(@spec)["timeout_seconds"] || 30}s</div>
              </div>
            <% else %>
              <p class="text-xs text-base-content/30">Default configuration</p>
            <% end %>
          </div>

          <%!-- Web Search Tool --%>
          <div class="p-3 rounded-lg bg-base-content/[0.03] border border-base-content/5">
            <div class="flex items-center gap-2 mb-2">
              <.icon name="hero-magnifying-glass-micro" class="size-4 text-blue-400" />
              <span class="text-xs font-semibold text-base-content/60">Web Search</span>
            </div>
            <%= if web_search_config(@spec) do %>
              <div class="space-y-1 text-xs font-mono text-base-content/40">
                <div>
                  enabled:
                  <span class={[
                    if(web_search_config(@spec)["enabled"],
                      do: "text-success",
                      else: "text-error"
                    )
                  ]}>
                    {to_string(web_search_config(@spec)["enabled"])}
                  </span>
                </div>
                <%= if desc = web_search_config(@spec)["description"] do %>
                  <div class="text-base-content/30 mt-1 font-sans">{desc}</div>
                <% end %>
              </div>
            <% else %>
              <p class="text-xs text-base-content/30">Default configuration</p>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Evaluation Goals --%>
      <div class="glass-panel p-5">
        <div class="flex items-center justify-between mb-3">
          <h3 class="text-[11px] font-semibold uppercase tracking-widest text-base-content/30">
            Evaluation Goals ({length(@spec.eval_goals || [])})
          </h3>
          <button
            phx-click="add_eval_goal"
            class="btn btn-outline btn-xs border-base-content/15 text-base-content/50"
          >
            <.icon name="hero-plus-micro" class="size-3" /> Add Goal
          </button>
        </div>
        <div class="space-y-2">
          <%= for {goal, idx} <- Enum.with_index(@spec.eval_goals || []) do %>
            <div class="flex items-start gap-2 group">
              <span class={[
                "text-[10px] font-bold mt-2.5 px-1.5 py-0.5 rounded shrink-0",
                goal_difficulty_class(goal)
              ]}>
                {goal_difficulty_label(goal)}
              </span>
              <form phx-change="update_eval_goal" phx-debounce="500" class="flex-1">
                <input type="hidden" name="index" value={idx} />
                <input
                  type="text"
                  name="value"
                  value={goal}
                  class="w-full text-sm bg-transparent border border-transparent hover:border-base-content/10 focus:border-primary/40 focus:outline-none rounded-lg px-2 py-1.5 text-base-content/60 transition-colors"
                />
              </form>
              <button
                phx-click="remove_eval_goal"
                phx-value-index={idx}
                class="mt-1.5 text-base-content/15 hover:text-error opacity-0 group-hover:opacity-100 transition-all"
                title="Remove goal"
              >
                <.icon name="hero-trash-micro" class="size-4" />
              </button>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # -- Spec Summary (after approval) subtemplate --

  defp render_spec_summary(assigns) do
    ~H"""
    <div class="glass-panel p-5">
      <h2 class="text-sm font-semibold text-base-content flex items-center gap-2 mb-4">
        <.icon name="hero-check-circle-micro" class="size-4 text-success" /> Approved Specification
      </h2>
      <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div>
          <span class="text-[10px] font-semibold uppercase tracking-widest text-base-content/25">
            Image
          </span>
          <p class="text-sm font-mono text-base-content/60 mt-1">{@spec.base_image}</p>
        </div>
        <div>
          <span class="text-[10px] font-semibold uppercase tracking-widest text-base-content/25">
            Packages
          </span>
          <p class="text-sm text-base-content/60 mt-1">
            {length(@spec.system_packages || [])} system
          </p>
        </div>
        <div>
          <span class="text-[10px] font-semibold uppercase tracking-widest text-base-content/25">
            Dependencies
          </span>
          <p class="text-sm text-base-content/60 mt-1">{runtime_dep_count(@spec)} runtime</p>
        </div>
        <div>
          <span class="text-[10px] font-semibold uppercase tracking-widest text-base-content/25">
            Eval Goals
          </span>
          <p class="text-sm text-base-content/60 mt-1">{length(@spec.eval_goals || [])} goals</p>
        </div>
      </div>
    </div>
    """
  end

  # -- Private helpers --

  defp load_active_run(params, runs) do
    case params["run"] do
      nil ->
        # Pick the most recent non-terminal run, or the most recent run
        run = Enum.find(runs, List.first(runs), fn r -> r.status not in ["ready", "failed"] end)
        load_run_with_spec(run)

      run_id ->
        run = Pipelines.get_run!(run_id)
        load_run_with_spec(run)
    end
  end

  defp load_run_with_spec(nil), do: {nil, nil}

  defp load_run_with_spec(run) do
    spec =
      if run.sandbox_spec_id do
        Analysis.get_spec!(run.sandbox_spec_id)
      else
        nil
      end

    {run, spec}
  end

  defp assign_spec_form(socket, nil) do
    assign(socket, :spec_form, nil)
  end

  defp assign_spec_form(socket, spec) do
    changeset = Analysis.change_spec(spec)
    assign(socket, :spec_form, to_form(changeset, as: :spec))
  end

  defp parse_spec_params(params) do
    # system_packages might come as comma-separated string from the form
    params =
      if pkg_string = params["system_packages_string"] do
        packages =
          pkg_string
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        Map.put(params, "system_packages", packages)
      else
        params
      end

    Map.delete(params, "system_packages_string")
  end

  defp current_step(nil), do: 0
  defp current_step(run), do: run.current_step || 0

  defp reviewing?(nil), do: false
  defp reviewing?(run), do: run.status == "reviewing"

  defp approved_or_later?(nil), do: false
  defp approved_or_later?(run), do: run.status in ["building", "configuring", "ready"]

  defp animating?(status) when status in ["parsing", "analyzing", "building", "configuring"],
    do: true

  defp animating?(_), do: false

  defp format_duration(ms) when is_number(ms) do
    cond do
      ms < 1_000 -> "#{ms}ms"
      ms < 60_000 -> "#{Float.round(ms / 1_000, 1)}s"
      true -> "#{Float.round(ms / 60_000, 1)}m"
    end
  end

  defp format_duration(_), do: ""

  defp step_classes(step_num, current) do
    cond do
      step_num < current ->
        "bg-primary/20 text-primary border border-primary/30"

      step_num == current ->
        "bg-primary text-primary-content border border-primary shadow-lg shadow-primary/30"

      true ->
        "border border-base-content/10 text-base-content/25 bg-base-content/[0.03]"
    end
  end

  defp run_dot("ready"), do: "bg-success"
  defp run_dot("failed"), do: "bg-error"
  defp run_dot("pending"), do: "bg-base-content/30"
  defp run_dot("reviewing"), do: "bg-accent"
  defp run_dot(_), do: "bg-warning"

  defp status_glow("reviewing"), do: "glow-accent"
  defp status_glow("failed"), do: ""
  defp status_glow("ready"), do: "glow-primary"
  defp status_glow(_), do: ""

  defp status_label("pending"), do: "Pending — initializing pipeline..."
  defp status_label("parsing"), do: "Parsing skill definition..."
  defp status_label("analyzing"), do: "Analyzing with LLM — this may take a moment..."
  defp status_label("reviewing"), do: "Review the generated specification below"
  defp status_label("building"), do: "Building Docker container..."
  defp status_label("configuring"), do: "Verifying sandbox tools..."
  defp status_label("ready"), do: "Sandbox is ready!"
  defp status_label("failed"), do: "Pipeline failed"
  defp status_label(s), do: s

  defp cli_config(spec), do: get_in(spec.tool_configs, ["cli"])
  defp web_search_config(spec), do: get_in(spec.tool_configs, ["web_search"])

  defp deps_packages(spec) do
    get_in(spec.runtime_deps, ["packages"]) || %{}
  end

  defp runtime_dep_count(spec) do
    spec.runtime_deps
    |> get_in(["packages"])
    |> case do
      pkgs when is_map(pkgs) -> map_size(pkgs)
      _ -> 0
    end
  end

  defp goal_difficulty_class(goal) do
    cond do
      String.starts_with?(goal, "Easy") -> "bg-success/15 text-success"
      String.starts_with?(goal, "Medium") -> "bg-warning/15 text-warning"
      String.starts_with?(goal, "Hard") -> "bg-error/15 text-error"
      true -> "bg-base-content/10 text-base-content/40"
    end
  end

  defp goal_difficulty_label(goal) do
    cond do
      String.starts_with?(goal, "Easy") -> "EASY"
      String.starts_with?(goal, "Medium") -> "MED"
      String.starts_with?(goal, "Hard") -> "HARD"
      true -> "?"
    end
  end
end
