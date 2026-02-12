defmodule SkillToSandboxWeb.API.ToolController do
  @moduledoc """
  API controller for tool proxy endpoints.

  Containers call these endpoints to use tools (like web search)
  without needing API keys. The host Elixir app proxies requests
  to the actual APIs.
  """
  use SkillToSandboxWeb, :controller

  alias SkillToSandbox.Tools.WebSearch

  def search(conn, %{"query" => query}) when is_binary(query) and query != "" do
    case WebSearch.execute(%{"query" => query}) do
      {:ok, results} ->
        json(conn, %{status: "ok", results: results})

      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{status: "error", error: reason})
    end
  end

  def search(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{status: "error", error: "Missing or empty 'query' parameter"})
  end
end
