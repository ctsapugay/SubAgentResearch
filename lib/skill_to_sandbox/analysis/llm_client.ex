defmodule SkillToSandbox.Analysis.LLMClient do
  @moduledoc """
  HTTP client for calling LLM APIs (Anthropic Claude or OpenAI).

  Wraps `Req` with retry/exponential backoff. Reads provider, API key,
  and model from application config (set via environment variables in
  `config/runtime.exs`).

  ## Configuration

      config :skill_to_sandbox, :llm,
        provider: "anthropic",
        api_key: "sk-ant-...",
        model: "claude-sonnet-4-20250514"
  """

  require Logger

  @max_retries 3
  @base_delay_ms 1_000
  @default_max_tokens 4_096
  @request_timeout_ms 120_000

  @doc """
  Send a chat request to the configured LLM provider.

  Takes a system prompt and user message, returns `{:ok, text}` with the
  assistant's response or `{:error, reason}`.

  ## Options

    * `:max_tokens` - Maximum tokens in the response (default: #{@default_max_tokens})
    * `:temperature` - Sampling temperature (default: provider-specific)
  """
  def chat(system_prompt, user_message, opts \\ []) do
    config = Application.get_env(:skill_to_sandbox, :llm, [])
    provider = config[:provider] || "anthropic"
    api_key = config[:api_key]
    model = config[:model] || default_model(provider)

    if is_nil(api_key) or api_key == "" do
      {:error, "LLM API key not configured. Set LLM_API_KEY environment variable."}
    else
      do_chat(provider, system_prompt, user_message, api_key, model, opts, 0)
    end
  end

  # -- Retry loop --

  defp do_chat(_provider, _system, _user, _api_key, _model, _opts, attempt)
       when attempt >= @max_retries do
    {:error, "Max retries (#{@max_retries}) exceeded"}
  end

  defp do_chat(provider, system, user, api_key, model, opts, attempt) do
    case send_request(provider, system, user, api_key, model, opts) do
      {:ok, response} ->
        {:ok, response}

      {:error, :rate_limited, retry_after} ->
        Logger.warning(
          "[LLMClient] Rate limited, retrying after #{retry_after}ms (attempt #{attempt + 1})"
        )

        Process.sleep(retry_after)
        do_chat(provider, system, user, api_key, model, opts, attempt + 1)

      {:error, :server_error, detail} ->
        delay = trunc(@base_delay_ms * :math.pow(2, attempt))

        Logger.warning(
          "[LLMClient] Server error: #{detail}, retrying in #{delay}ms (attempt #{attempt + 1})"
        )

        Process.sleep(delay)
        do_chat(provider, system, user, api_key, model, opts, attempt + 1)

      {:error, :timeout} ->
        delay = trunc(@base_delay_ms * :math.pow(2, attempt))

        Logger.warning(
          "[LLMClient] Request timeout, retrying in #{delay}ms (attempt #{attempt + 1})"
        )

        Process.sleep(delay)
        do_chat(provider, system, user, api_key, model, opts, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # -- Anthropic Messages API --

  defp send_request("anthropic", system, user, api_key, model, opts) do
    max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)

    body = %{
      model: model,
      system: system,
      messages: [%{role: "user", content: user}],
      max_tokens: max_tokens
    }

    body =
      if temp = Keyword.get(opts, :temperature) do
        Map.put(body, :temperature, temp)
      else
        body
      end

    headers = [
      {"x-api-key", api_key},
      {"anthropic-version", "2023-06-01"},
      {"content-type", "application/json"}
    ]

    case Req.post("https://api.anthropic.com/v1/messages",
           json: body,
           headers: headers,
           receive_timeout: @request_timeout_ms
         ) do
      {:ok, %{status: 200, body: resp_body}} ->
        extract_anthropic_text(resp_body)

      {:ok, %{status: 429} = resp} ->
        retry_after = get_retry_after(resp)
        {:error, :rate_limited, retry_after}

      {:ok, %{status: 401, body: body}} ->
        {:error, "Authentication failed: #{inspect_body(body)}. Check your LLM_API_KEY."}

      {:ok, %{status: status, body: body}} when status >= 500 ->
        {:error, :server_error, "HTTP #{status}: #{inspect_body(body)}"}

      {:ok, %{status: status, body: body}} ->
        {:error, "LLM API returned HTTP #{status}: #{inspect_body(body)}"}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, %Req.TransportError{reason: reason}} ->
        {:error, "Network error: #{inspect(reason)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  # -- OpenAI Chat Completions API --

  defp send_request("openai", system, user, api_key, model, opts) do
    max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)

    body = %{
      model: model,
      messages: [
        %{role: "system", content: system},
        %{role: "user", content: user}
      ],
      max_tokens: max_tokens
    }

    body =
      if temp = Keyword.get(opts, :temperature) do
        Map.put(body, :temperature, temp)
      else
        body
      end

    headers = [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]

    case Req.post("https://api.openai.com/v1/chat/completions",
           json: body,
           headers: headers,
           receive_timeout: @request_timeout_ms
         ) do
      {:ok, %{status: 200, body: resp_body}} ->
        extract_openai_text(resp_body)

      {:ok, %{status: 429} = resp} ->
        retry_after = get_retry_after(resp)
        {:error, :rate_limited, retry_after}

      {:ok, %{status: 401, body: body}} ->
        {:error, "Authentication failed: #{inspect_body(body)}. Check your LLM_API_KEY."}

      {:ok, %{status: status, body: body}} when status >= 500 ->
        {:error, :server_error, "HTTP #{status}: #{inspect_body(body)}"}

      {:ok, %{status: status, body: body}} ->
        {:error, "LLM API returned HTTP #{status}: #{inspect_body(body)}"}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, %Req.TransportError{reason: reason}} ->
        {:error, "Network error: #{inspect(reason)}"}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  defp send_request(provider, _system, _user, _api_key, _model, _opts) do
    {:error, "Unsupported LLM provider: #{provider}. Use \"anthropic\" or \"openai\"."}
  end

  # -- Response extraction --

  defp extract_anthropic_text(%{"content" => [%{"type" => "text", "text" => text} | _]}) do
    {:ok, text}
  end

  defp extract_anthropic_text(%{"content" => content}) do
    {:error, "Unexpected Anthropic response content format: #{inspect(content)}"}
  end

  defp extract_anthropic_text(body) do
    {:error, "Unexpected Anthropic response format: #{inspect_body(body)}"}
  end

  defp extract_openai_text(%{"choices" => [%{"message" => %{"content" => text}} | _]}) do
    {:ok, text}
  end

  defp extract_openai_text(body) do
    {:error, "Unexpected OpenAI response format: #{inspect_body(body)}"}
  end

  # -- Helpers --

  defp get_retry_after(%{headers: headers}) do
    case List.keyfind(headers, "retry-after", 0) do
      {_, value} ->
        case Integer.parse(value) do
          {seconds, _} -> seconds * 1_000
          :error -> @base_delay_ms * 2
        end

      nil ->
        @base_delay_ms * 2
    end
  end

  defp get_retry_after(_), do: @base_delay_ms * 2

  defp default_model("anthropic"), do: "claude-sonnet-4-20250514"
  defp default_model("openai"), do: "gpt-4o"
  defp default_model(_), do: "claude-sonnet-4-20250514"

  defp inspect_body(body) when is_binary(body), do: String.slice(body, 0, 500)
  defp inspect_body(body) when is_map(body), do: body |> Jason.encode!() |> String.slice(0, 500)
  defp inspect_body(body), do: inspect(body) |> String.slice(0, 500)
end
