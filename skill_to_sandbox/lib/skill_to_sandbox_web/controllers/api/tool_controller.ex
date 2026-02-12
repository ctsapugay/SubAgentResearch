defmodule SkillToSandboxWeb.API.ToolController do
  @moduledoc """
  API controller for tool proxy endpoints.

  Containers call these endpoints to use tools (like web search)
  without needing API keys. The host Elixir app proxies requests
  to the actual APIs.
  """
  use SkillToSandboxWeb, :controller

  def search(conn, %{"query" => query}) when is_binary(query) and query != "" do
    # Will be wired to SkillToSandbox.Tools.WebSearch in Phase 4.
    # For now, return a stub response.
    json(conn, %{
      status: "ok",
      message: "Search proxy not yet implemented (Phase 4)",
      query: query,
      results: []
    })
  end

  def search(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{status: "error", error: "Missing or empty 'query' parameter"})
  end
end
