defmodule Redactly.PII.Scanner do
  @moduledoc """
  Uses OpenAI to detect PII in messages and tickets.
  """

  alias Redactly.Integrations.OpenAI

  @type pii :: String.t()

  @spec scan(String.t()) :: {:ok, list(pii)} | :empty
  def scan(text) when is_binary(text) and byte_size(text) > 0 do
    case OpenAI.detect_pii(text) do
      {:ok, []} -> :empty
      {:ok, items} -> {:ok, items}
      {:error, _reason} -> :empty
    end
  end

  def scan(_), do: :empty
end
