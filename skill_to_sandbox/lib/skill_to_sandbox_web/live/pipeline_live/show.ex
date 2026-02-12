defmodule SkillToSandboxWeb.PipelineLive.Show do
  @moduledoc """
  Pipeline run status view with step indicator. Stub for Phase 1 --
  will be fully implemented in Phase 5 with real-time PubSub updates.
  """
  use SkillToSandboxWeb, :live_view

  alias SkillToSandbox.Pipelines

  @steps [
    {1, "Parse"},
    {2, "Analyze"},
    {3, "Review"},
    {4, "Build"},
    {5, "Configure"},
    {6, "Ready"}
  ]

  @impl true
  def mount(%{"id" => skill_id}, _session, socket) do
    runs = Pipelines.runs_for_skill(String.to_integer(skill_id))

    socket =
      socket
      |> assign(:page_title, "Pipeline")
      |> assign(:skill_id, skill_id)
      |> assign(:runs, runs)
      |> assign(:steps, @steps)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <a href={"/skills/#{@skill_id}"} class="back-btn">
        <.icon name="hero-arrow-left-micro" class="size-3.5" /> Back to Skill
      </a>

      <div>
        <h1 class="text-2xl font-semibold tracking-tight">Pipeline</h1>
        <p class="text-sm text-base-content/45 mt-0.5">Skill-to-sandbox conversion pipeline</p>
      </div>

      <%!-- Step Indicator --%>
      <div class="glass-panel p-5">
        <h2 class="text-sm font-semibold text-base-content/50 mb-4">Steps</h2>
        <div class="flex items-center gap-2">
          <%= for {num, label} <- @steps do %>
            <div class="flex items-center gap-2 flex-1">
              <span class="size-7 rounded-full border border-base-content/10 flex items-center justify-center text-xs font-medium text-base-content/35 bg-base-content/[0.03]">
                {num}
              </span>
              <span class="text-xs text-base-content/35 hidden sm:inline">{label}</span>
            </div>
            <%= if num < 6 do %>
              <div class="w-4 h-px bg-base-content/10 flex-shrink-0" />
            <% end %>
          <% end %>
        </div>
      </div>

      <%!-- Pipeline Runs --%>
      <div class="glass-panel overflow-hidden">
        <div class="px-5 py-3.5 border-b border-base-content/5">
          <h2 class="text-sm font-semibold text-base-content">Runs</h2>
        </div>
        <%= if @runs == [] do %>
          <div class="py-12 text-center">
            <p class="text-sm text-base-content/25">
              No pipeline runs yet. Full pipeline in Phase 5.
            </p>
          </div>
        <% else %>
          <div class="divide-y divide-base-content/5">
            <%= for run <- @runs do %>
              <div class="flex items-center justify-between px-5 py-3 hover:bg-base-content/[0.02] transition-colors">
                <div class="flex items-center gap-3">
                  <span class="inline-flex items-center gap-1.5 text-xs font-medium">
                    <span class={["size-1.5 rounded-full", run_dot(run.status)]} />
                    {run.status}
                  </span>
                  <span class="text-xs text-base-content/35">
                    Step {run.current_step}/6
                  </span>
                </div>
                <span class="text-xs text-base-content/35">
                  {if run.started_at, do: Calendar.strftime(run.started_at, "%b %d %H:%M"), else: "Not started"}
                </span>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp run_dot("ready"), do: "bg-success"
  defp run_dot("failed"), do: "bg-error"
  defp run_dot("pending"), do: "bg-base-content/30"
  defp run_dot(_), do: "bg-warning"
end
