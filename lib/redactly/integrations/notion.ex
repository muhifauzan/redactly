defmodule Redactly.Integrations.Notion do
  @moduledoc "Handles Notion API interactions."

  require Logger

  @notion_api "https://api.notion.com/v1"

  @spec query_database(String.t()) :: list(map())
  def query_database(database_id) do
    url = "#{@notion_api}/databases/#{database_id}/query"

    body = Jason.encode!(%{})

    case Finch.build(:post, url, headers(), body)
         |> Finch.request(Redactly.Finch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        %{"results" => results} = Jason.decode!(body)
        results

      {:ok, %Finch.Response{status: status, body: body}} ->
        Logger.error("[Notion] Query failed (#{status}): #{body}")
        []

      {:error, reason} ->
        Logger.error("[Notion] Query error: #{inspect(reason)}")
        []
    end
  end

  @spec delete_page(String.t()) :: :ok | {:error, any()}
  def delete_page(page_id) do
    url = "#{@notion_api}/pages/#{page_id}"

    body = Jason.encode!(%{"archived" => true})

    case Finch.build(:patch, url, headers(), body)
         |> Finch.request(Redactly.Finch) do
      {:ok, %Finch.Response{status: 200}} ->
        Logger.info("[Notion] Deleted page #{page_id}")
        :ok

      {:ok, %Finch.Response{status: status, body: body}} ->
        Logger.error("[Notion] Failed to delete page (#{status}): #{body}")
        {:error, body}

      {:error, reason} ->
        Logger.error("[Notion] Failed to delete page: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @spec fetch_user_email(String.t()) :: String.t()
  def fetch_user_email(notion_user_id) do
    url = "#{@notion_api}/users/#{notion_user_id}"

    case Finch.build(:get, url, headers())
         |> Finch.request(Redactly.Finch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        case Jason.decode!(body) do
          %{"person" => %{"email" => email}} ->
            email

          _ ->
            Logger.warning("[Notion] User #{notion_user_id} has no email")
            ""
        end

      {:ok, %Finch.Response{status: status, body: body}} ->
        Logger.error("[Notion] Failed to fetch user email (#{status}): #{body}")
        ""

      {:error, reason} ->
        Logger.error("[Notion] Error fetching user email: #{inspect(reason)}")
        ""
    end
  end

  @spec extract_content(map()) :: String.t()
  def extract_content(page) do
    page
    |> get_in(["properties"])
    |> Enum.map(fn {key, value} ->
      "#{key}: #{extract_property(value)}"
    end)
    |> Enum.join("\n")
  end

  @spec fetch_page(String.t()) :: {:ok, map()} | {:error, any()}
  def fetch_page(page_id) do
    url = "#{@notion_api}/pages/#{page_id}"

    case Finch.build(:get, url, headers())
         |> Finch.request(Redactly.Finch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, %Finch.Response{status: status, body: body}} ->
        Logger.error("[Notion] Failed to fetch page (#{status}): #{body}")
        {:error, body}

      {:error, reason} ->
        Logger.error("[Notion] Failed to fetch page: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @spec fetch_block_texts(String.t()) :: String.t()
  def fetch_block_texts(page_id) do
    url = "#{@notion_api}/blocks/#{page_id}/children?page_size=100"

    case Finch.build(:get, url, headers())
         |> Finch.request(Redactly.Finch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"results" => blocks}} ->
            blocks
            |> Enum.flat_map(&extract_block_text/1)
            |> Enum.join("\n")

          _ ->
            Logger.error("[Notion] Unexpected response body when fetching blocks")
            ""
        end

      {:ok, %Finch.Response{status: status, body: body}} ->
        Logger.error("[Notion] Failed to fetch blocks (#{status}): #{body}")
        ""

      {:error, reason} ->
        Logger.error("[Notion] Error fetching blocks: #{inspect(reason)}")
        ""
    end
  end

  defp extract_block_text(%{"type" => "paragraph", "paragraph" => %{"rich_text" => rich_text}}) do
    Enum.map(rich_text, fn %{"plain_text" => text} -> text end)
  end

  defp extract_block_text(_), do: []

  defp extract_property(%{"type" => "rich_text", "rich_text" => rich_text}) do
    Enum.map(rich_text, fn %{"plain_text" => text} -> text end) |> Enum.join()
  end

  defp extract_property(%{"type" => "title", "title" => title}) do
    Enum.map(title, fn %{"plain_text" => text} -> text end) |> Enum.join()
  end

  defp extract_property(_), do: ""

  defp api_token do
    Application.fetch_env!(:redactly, :notion)[:api_token]
  end

  defp headers do
    [
      {"Authorization", "Bearer #{api_token()}"},
      {"Notion-Version", "2022-06-28"},
      {"Content-Type", "application/json"}
    ]
  end
end
