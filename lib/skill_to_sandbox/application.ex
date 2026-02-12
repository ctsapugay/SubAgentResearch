defmodule SkillToSandbox.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SkillToSandboxWeb.Telemetry,
      SkillToSandbox.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:skill_to_sandbox, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:skill_to_sandbox, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: SkillToSandbox.PubSub},
      # Pipeline infrastructure
      {Registry, keys: :unique, name: SkillToSandbox.PipelineRegistry},
      {Task.Supervisor, name: SkillToSandbox.TaskSupervisor},
      SkillToSandbox.Pipeline.Supervisor,
      # Recovery: resume interrupted pipeline runs after startup
      {Task, &SkillToSandbox.Pipeline.Recovery.recover_on_startup/0},
      # Start to serve requests, typically the last entry
      SkillToSandboxWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SkillToSandbox.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SkillToSandboxWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
