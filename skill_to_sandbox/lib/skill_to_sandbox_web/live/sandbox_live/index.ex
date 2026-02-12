defmodule SkillToSandboxWeb.SandboxLive.Index do
  @moduledoc """
  Lists all sandbox containers with status, container info, and actions.
  """
  use SkillToSandboxWeb, :live_view

  alias SkillToSandbox.Sandboxes

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Sandboxes")
      |> assign(:sandboxes, Sandboxes.list_sandboxes())

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <a href="/" class="back-btn">
        <.icon name="hero-arrow-left-micro" class="size-3.5" /> Dashboard
      </a>

      <div>
        <h1 class="text-2xl font-semibold tracking-tight">Sandboxes</h1>
        <p class="text-sm text-base-content/45 mt-0.5">
          Docker containers running skill environments
        </p>
      </div>

      <%= if @sandboxes == [] do %>
        <div class="glass-panel">
          <div class="flex flex-col items-center text-center py-16 px-6">
            <span class="size-14 rounded-2xl bg-base-content/5 flex items-center justify-center mb-4">
              <.icon name="hero-server" class="size-7 text-base-content/20" />
            </span>
            <h3 class="text-base font-semibold text-base-content">No sandboxes yet</h3>
            <p class="text-sm text-base-content/45 mt-1 max-w-sm">
              Sandboxes are created when you run the pipeline on a skill.
            </p>
            <a href="/skills" class="btn btn-primary btn-sm mt-5 shadow-lg shadow-primary/20">
              View Skills
            </a>
          </div>
        </div>
      <% else %>
        <div class="glass-panel overflow-hidden">
          <table class="table table-sm">
            <thead class="bg-base-content/[0.03]">
              <tr class="text-xs uppercase tracking-wider text-base-content/30">
                <th class="font-semibold">Skill</th>
                <th class="font-semibold">Status</th>
                <th class="font-semibold">Container ID</th>
                <th class="font-semibold">Created</th>
                <th class="font-semibold text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              <%= for sandbox <- @sandboxes do %>
                <tr class="hover:bg-base-content/[0.02] transition-colors border-t border-base-content/5">
                  <td class="font-medium">
                    <%= if sandbox.sandbox_spec && sandbox.sandbox_spec.skill do %>
                      <a
                        href={"/skills/#{sandbox.sandbox_spec.skill.id}"}
                        class="text-primary hover:text-primary/80 transition-colors"
                      >
                        {sandbox.sandbox_spec.skill.name}
                      </a>
                    <% else %>
                      <span class="text-base-content/35">Unknown</span>
                    <% end %>
                  </td>
                  <td>
                    <span class="inline-flex items-center gap-1.5 text-xs font-medium">
                      <span class={["size-1.5 rounded-full", status_dot(sandbox.status)]} />
                      {sandbox.status}
                    </span>
                  </td>
                  <td class="font-mono text-xs text-base-content/40">
                    {truncate_id(sandbox.container_id)}
                  </td>
                  <td class="whitespace-nowrap text-sm text-base-content/40">
                    {Calendar.strftime(sandbox.inserted_at, "%b %d, %Y")}
                  </td>
                  <td class="text-right">
                    <a
                      href={"/sandboxes/#{sandbox.id}"}
                      class="btn btn-outline btn-xs border-base-content/10 text-base-content/60 hover:bg-base-content/5 hover:border-base-content/20"
                    >
                      Monitor
                    </a>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  defp status_dot("running"), do: "bg-success"
  defp status_dot("building"), do: "bg-warning"
  defp status_dot("stopped"), do: "bg-base-content/30"
  defp status_dot("error"), do: "bg-error"
  defp status_dot(_), do: "bg-base-content/20"

  defp truncate_id(nil), do: "--"
  defp truncate_id(id) when byte_size(id) > 12, do: String.slice(id, 0, 12) <> "..."
  defp truncate_id(id), do: id
end
