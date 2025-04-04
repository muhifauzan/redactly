defmodule Redactly.PII.Scanner do
  @moduledoc """
  Uses AI to determine if a message or ticket contains PII.
  """

  @type text :: String.t()

  @spec contains_pii?(text()) :: boolean()
  def contains_pii?(_content) do
    # TODO: Implement OpenAI call to detect PII
    false
  end
end
