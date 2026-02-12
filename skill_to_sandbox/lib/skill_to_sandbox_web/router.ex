defmodule SkillToSandboxWeb.Router do
  use SkillToSandboxWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SkillToSandboxWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", SkillToSandboxWeb do
    pipe_through :browser

    live "/", DashboardLive, :index
    live "/skills", SkillLive.Index, :index
    live "/skills/new", SkillLive.New, :new
    live "/skills/:id", SkillLive.Show, :show
    live "/skills/:id/pipeline", PipelineLive.Show, :show
    live "/sandboxes", SandboxLive.Index, :index
    live "/sandboxes/:id", SandboxLive.Show, :show
  end

  scope "/api", SkillToSandboxWeb.API do
    pipe_through :api

    post "/tools/search", ToolController, :search
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:skill_to_sandbox, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SkillToSandboxWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
