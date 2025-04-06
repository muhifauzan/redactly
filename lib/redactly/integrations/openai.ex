defmodule Redactly.Integrations.OpenAI do
  @moduledoc "Handles communication with OpenAI for PII analysis."

  require Logger

  @openai_api "https://api.openai.com/v1/chat/completions"

  @spec detect_pii(String.t()) :: {:ok, list(String.t())} | {:error, any()}
  def detect_pii(text) do
    prompt = build_prompt(text)

    headers = [
      {"Authorization", "Bearer #{api_key()}"},
      {"Content-Type", "application/json"}
    ]

    body =
      Jason.encode!(%{
        model: "gpt-4o",
        temperature: 0,
        messages: [
          %{
            role: "system",
            content:
              "You're a compliance assistant that identifies sensitive personal information (PII) in user-submitted content. Return ONLY the PII found, as a JSON list of strings. If no PII is found, return an empty list: []"
          },
          %{
            role: "user",
            content: prompt
          }
        ]
      })

    case Finch.build(:post, @openai_api, headers, body)
         |> Finch.request(Redactly.Finch) do
      {:ok, %Finch.Response{status: 200, body: response_body}} ->
        parse_response(response_body)

      {:ok, %Finch.Response{status: status, body: body}} ->
        Logger.error("[OpenAI] Error (#{status}): #{body}")
        {:error, :openai_error}

      {:error, reason} ->
        Logger.error("[OpenAI] Request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_response(body) do
    with {:ok, %{"choices" => [%{"message" => %{"content" => content}}]}} <- Jason.decode(body),
         {:ok, parsed} <- Jason.decode(content) do
      {:ok, parsed}
    else
      _ ->
        Logger.error("[OpenAI] Failed to parse PII from response")
        {:ok, []}
    end
  end

  defp build_prompt(text) do
    "Analyze this content and return a list of PII:\n\n#{text}"
  end

  defp api_key do
    Application.fetch_env!(:redactly, :openai)[:api_key]
  end
end
