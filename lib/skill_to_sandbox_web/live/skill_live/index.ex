defmodule SkillToSandboxWeb.SkillLive.Index do
  @moduledoc """
  Lists all uploaded skills with name, description, creation date, and actions.
  """
  use SkillToSandboxWeb, :live_view

  alias SkillToSandbox.Skills

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Skills")
      |> assign(:skills, Skills.list_skills())

    {:ok, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    skill = Skills.get_skill!(id)
    {:ok, _} = Skills.delete_skill(skill)

    {:noreply,
     socket
     |> put_flash(:info, "Skill \"#{skill.name}\" deleted.")
     |> assign(:skills, Skills.list_skills())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <a href="/" class="back-btn">
        <.icon name="hero-arrow-left-micro" class="size-3.5" /> Dashboard
      </a>

      <div class="flex items-end justify-between">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight">Skills</h1>
          <p class="text-sm text-base-content/45 mt-0.5">Uploaded skill definitions</p>
        </div>
        <a href="/skills/new" class="btn btn-primary btn-sm shadow-lg shadow-primary/20">
          <.icon name="hero-plus-micro" class="size-4" /> Upload Skill
        </a>
      </div>

      <%= if @skills == [] do %>
        <div class="glass-panel">
          <div class="flex flex-col items-center text-center py-16 px-6">
            <span class="size-14 rounded-2xl bg-base-content/5 flex items-center justify-center mb-4">
              <.icon name="hero-document-text" class="size-7 text-base-content/20" />
            </span>
            <h3 class="text-base font-semibold text-base-content">No skills uploaded yet</h3>
            <p class="text-sm text-base-content/45 mt-1 max-w-sm">
              Upload a SKILL.md file to get started with the pipeline.
            </p>
            <a href="/skills/new" class="btn btn-primary btn-sm mt-5 shadow-lg shadow-primary/20">
              Upload Your First Skill
            </a>
          </div>
        </div>
      <% else %>
        <div class="glass-panel overflow-hidden">
          <table class="table table-sm">
            <thead class="bg-base-content/[0.03]">
              <tr class="text-xs uppercase tracking-wider text-base-content/30">
                <th class="font-semibold">Name</th>
                <th class="font-semibold">Description</th>
                <th class="font-semibold">Source</th>
                <th class="font-semibold">Created</th>
                <th class="font-semibold text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              <%= for skill <- @skills do %>
                <tr class="hover:bg-base-content/[0.02] transition-colors border-t border-base-content/5">
                  <td>
                    <a
                      href={"/skills/#{skill.id}"}
                      class="font-medium text-primary hover:text-primary/80 transition-colors"
                    >
                      {skill.name}
                    </a>
                  </td>
                  <td class="max-w-xs truncate text-sm text-base-content/50">
                    {skill.description || "No description"}
                  </td>
                  <td>
                    <%= if skill.source_url do %>
                      <span class="text-xs font-medium text-accent bg-accent/10 px-2 py-0.5 rounded-full">
                        URL
                      </span>
                    <% else %>
                      <span class="text-xs font-medium text-base-content/40 bg-base-content/5 px-2 py-0.5 rounded-full">
                        Upload
                      </span>
                    <% end %>
                  </td>
                  <td class="whitespace-nowrap text-sm text-base-content/40">
                    {Calendar.strftime(skill.inserted_at, "%b %d, %Y")}
                  </td>
                  <td class="text-right">
                    <div class="flex gap-1.5 justify-end">
                      <a
                        href={"/skills/#{skill.id}"}
                        class="btn btn-outline btn-xs border-base-content/10 text-base-content/60 hover:bg-base-content/5 hover:border-base-content/20"
                      >
                        View
                      </a>
                      <button
                        phx-click="delete"
                        phx-value-id={skill.id}
                        data-confirm="Are you sure you want to delete this skill?"
                        class="btn btn-outline btn-xs border-error/20 text-error/60 hover:bg-error/10 hover:text-error hover:border-error/30"
                      >
                        Delete
                      </button>
                    </div>
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
end
