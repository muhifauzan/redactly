defmodule Redactly.Integrations.OpenAI do
  @moduledoc "Handles communication with OpenAI for PII analysis."

  require Logger

  @openai_url "https://api.openai.com/v1/chat/completions"

  @type pii_item :: %{type: String.t(), value: String.t()}

  @type file :: %{
          name: String.t(),
          mime_type: String.t(),
          data: binary()
        }

  @spec detect_pii(String.t(), list(file())) :: {:ok, list(pii_item)} | {:error, any()}
  def detect_pii(text, []), do: detect_text_pii(text)

  def detect_pii(_text, files) do
    Logger.warning(
      "[OpenAI] File-based PII detection not yet implemented: #{length(files)} file(s)"
    )

    {:ok, []}
  end

  defp detect_text_pii(text) do
    Logger.info("[OpenAI] Scanning text: #{text}")

    body =
      Jason.encode!(%{
        model: "gpt-4o",
        messages: [
          %{
            role: "system",
            content: """
            You are a strict data loss prevention (DLP) agent. Given a message, your job is to detect any personally identifiable information (PII), such as:

            - Full names
            - Email addresses
            - Phone numbers
            - Physical addresses
            - Credit card numbers
            - Government IDs (like SSNs)
            - Bank or account numbers
            - Dates of birth
            - IP addresses

            You MUST return a machine-readable JSON list. Each item must include:

            - `type`: the type of PII (e.g. `email`, `phone`, `credit_card`)
            - `value`: the exact string found in the message

            If nothing is found, return `[]` (an empty JSON array). No explanation, no extra text.
            """
          },
          %{
            role: "user",
            content: text
          }
        ]
      })

    Logger.debug("[OpenAI] Request body: #{body}")

    headers = [
      {"Authorization", "Bearer #{api_key()}"},
      {"Content-Type", "application/json"}
    ]

    Finch.build(:post, @openai_url, headers, body)
    |> Finch.request(Redactly.Finch)
    |> handle_response()
  end

  defp handle_response({:ok, %Finch.Response{status: 200, body: body}}) do
    Logger.debug("[OpenAI] Raw response: #{inspect(body)}")

    with %{"choices" => [%{"message" => %{"content" => content}} | _]} <- Jason.decode!(body),
         {:ok, items} <- Jason.decode(content),
         true <- is_list(items) do
      {:ok, items}
    else
      _ ->
        Logger.error("[OpenAI] Invalid or unexpected response format.")
        {:error, :invalid_format}
    end
  end

  defp handle_response({:ok, %Finch.Response{status: status, body: body}}) do
    Logger.error("[OpenAI] Failed with status #{status}: #{body}")
    {:error, :http_error}
  end

  defp handle_response({:error, reason}) do
    Logger.error("[OpenAI] Request error: #{inspect(reason)}")
    {:error, reason}
  end

  defp api_key do
    Application.fetch_env!(:redactly, :openai)[:api_key]
  end
end
