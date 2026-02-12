defmodule SkillToSandbox.Tools.WebSearch do
  @moduledoc """
  Web search tool for sandbox containers.

  Executes web searches via a configurable search API provider.
  Currently supports Tavily. The search is executed from the host
  (where API keys live), and results are returned to the caller.

  Containers access this tool via the `/api/tools/search` proxy
  endpoint on the host Elixir app, so they never need API keys.
  """

  @behaviour SkillToSandbox.Tools.Tool

  require Logger

  @impl true
  def name, do: "web_search"

  @impl true
  def description, do: "Search the web for information"

  @impl true
  def parameter_schema do
    %{
      "type" => "object",
      "properties" => %{
        "query" => %{
          "type" => "string",
          "description" => "The search query"
        },
        "max_results" => %{
          "type" => "integer",
          "description" => "Maximum number of results to return (default: 5)"
        }
      },
      "required" => ["query"]
    }
  end

  @impl true
  def execute(%{"query" => query} = args) do
    max_results = Map.get(args, "max_results", 5)
    config = Application.get_env(:skill_to_sandbox, :search, [])
    provider = Keyword.get(config, :provider, "tavily")
    api_key = Keyword.get(config, :api_key)

    if is_nil(api_key) or api_key == "" do
      {:error, "Search API key not configured. Set SEARCH_API_KEY environment variable."}
    else
      do_search(provider, query, api_key, max_results)
    end
  end

  def execute(_args) do
    {:error, "Missing required field: 'query'"}
  end

  @impl true
  def container_setup_script do
    """
    #!/bin/bash
    # Web search via host proxy
    # Usage: web_search.sh "<query>"
    QUERY="$1"
    HOST="${TOOL_PROXY_HOST:-host.docker.internal}"
    PORT="${TOOL_PROXY_PORT:-4000}"

    if [ -z "$QUERY" ]; then
      echo "Error: query argument required"
      echo "Usage: web_search.sh \"<query>\""
      exit 1
    fi

    curl -s -X POST "http://$HOST:$PORT/api/tools/search" \
      -H "Content-Type: application/json" \
      -d "{\\"query\\": \\"$QUERY\\"}"
    """
  end

  # -- Provider implementations --

  defp do_search("tavily", query, api_key, max_results) do
    case Req.post("https://api.tavily.com/search",
           json: %{query: query, api_key: api_key, max_results: max_results},
           receive_timeout: 15_000
         ) do
      {:ok, %{status: 200, body: %{"results" => results}}} ->
        formatted =
          results
          |> Enum.map(fn r ->
            title = Map.get(r, "title", "Untitled")
            url = Map.get(r, "url", "")
            content = Map.get(r, "content", "")
            "#{title}\n#{url}\n#{content}"
          end)
          |> Enum.join("\n---\n")

        {:ok, formatted}

      {:ok, %{status: 200, body: body}} ->
        # Tavily response without "results" key -- return raw
        {:ok, Jason.encode!(body)}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[WebSearch] Tavily returned #{status}: #{inspect(body)}")
        {:error, "Search API returned status #{status}"}

      {:error, reason} ->
        Logger.error("[WebSearch] Request failed: #{inspect(reason)}")
        {:error, "Search request failed: #{inspect(reason)}"}
    end
  end

  defp do_search(provider, _query, _api_key, _max_results) do
    {:error, "Unsupported search provider: #{provider}. Supported: tavily"}
  end
end
