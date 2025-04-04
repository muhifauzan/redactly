defmodule Redactly.Integrations.Notion do
  @moduledoc "Handles Notion API interactions."

  @spec query_database(String.t()) :: list(map())
  def query_database(_db_id), do: []

  @spec delete_page(String.t()) :: :ok | {:error, term()}
  def delete_page(_page_id), do: :ok

  @spec extract_author_email(map()) :: String.t()
  def extract_author_email(_page), do: "user@example.com"

  @spec extract_content(map()) :: String.t()
  def extract_content(_page), do: "Some content here"
end
