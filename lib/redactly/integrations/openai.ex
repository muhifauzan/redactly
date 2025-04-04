defmodule Redactly.Integrations.OpenAI do
  @moduledoc "Handles communication with OpenAI for PII analysis."

  @spec detect_pii(String.t()) :: boolean()
  def detect_pii(_content) do
    # TODO: Send prompt to OpenAI and parse response
    false
  end
end
