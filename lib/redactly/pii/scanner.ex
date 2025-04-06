defmodule Redactly.PII.Scanner do
  @moduledoc """
  Uses OpenAI (GPT-4o) to detect PII in messages, images, and documents.
  """

  require Logger

  alias Redactly.Integrations.OpenAI

  @type pii :: String.t()
  @type file :: %{
          name: String.t(),
          mime_type: String.t(),
          data: binary()
        }

  @spec scan(String.t(), list(OpenAI.file())) :: {:ok, list(pii)} | :empty
  def scan(text, files \\ []) when is_binary(text) and byte_size(text) > 0 do
    Logger.info("[Scanner] Scanning text: #{text}")

    case OpenAI.detect_pii(text, files) do
      {:ok, []} ->
        Logger.info("[Scanner] No PII detected.")
        :empty

      {:ok, items} ->
        Logger.info("[Scanner] PII detected: #{inspect(items)}")
        {:ok, items}

      {:error, reason} ->
        Logger.error("[Scanner] Error during detection: #{inspect(reason)}")
        :empty
    end
  end
end
