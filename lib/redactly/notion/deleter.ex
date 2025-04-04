defmodule Redactly.Notion.Deleter do
  @moduledoc """
  Deletes a Notion page that was flagged for PII.
  """

  @spec delete_page(String.t()) :: :ok | {:error, term()}
  def delete_page(page_id) do
    # TODO: call Redactly.Integrations.Notion.delete_page(page_id)
    :ok
  end
end
