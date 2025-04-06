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

  @spec scan(String.t() | nil, list(file())) :: {:ok, list(pii)} | :empty | {:error, any()}
  def scan(nil, files), do: scan("", files)

  def scan(text, files) when is_binary(text) do
    if String.trim(text) == "" and files == [] do
      :empty
    else
      case OpenAI.detect_pii(text, files) do
        {:ok, []} ->
          Logger.info("[Scanner] No PII detected.")
          :empty

        {:ok, items} ->
          Logger.info("[Scanner] PII detected: #{inspect(items)}")
          {:ok, items}

        :empty ->
          Logger.info("[Scanner] No PII detected.")
          :empty
      end
    end
  end
end
