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

  @spec extract_page_content(String.t()) :: %{text: [String.t()], files: [map()]}
  def extract_page_content(page_id) do
    url = "#{@notion_api}/blocks/#{page_id}/children?page_size=100"

    case Finch.build(:get, url, headers())
         |> Finch.request(Redactly.Finch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"results" => blocks}} ->
            Enum.reduce(blocks, %{text: [], files: []}, fn block, acc ->
              case block do
                %{"type" => "paragraph", "paragraph" => %{"rich_text" => rich_text}} ->
                  lines = Enum.map(rich_text, fn %{"plain_text" => t} -> t end)
                  %{acc | text: acc.text ++ lines}

                %{"type" => block_type} ->
                  case Map.get(block, block_type) do
                    %{"type" => "file", "file" => %{"url" => url}} ->
                      case download_file(url) do
                        {:ok, data} ->
                          mime = guess_mime_type(url)
                          file = %{name: Path.basename(url), mime_type: mime, data: data}
                          %{acc | files: [file | acc.files]}

                        _ ->
                          Logger.warning("[Notion] Skipping failed file download from #{url}")
                          acc
                      end

                    _ ->
                      acc
                  end

                _ ->
                  acc
              end
            end)

          _ ->
            Logger.error("[Notion] Unexpected response body when fetching blocks")
            %{text: [], files: []}
        end

      {:ok, %Finch.Response{status: status, body: body}} ->
        Logger.error("[Notion] Failed to fetch blocks (#{status}): #{body}")
        %{text: [], files: []}

      {:error, reason} ->
        Logger.error("[Notion] Error fetching blocks: #{inspect(reason)}")
        %{text: [], files: []}
    end
  end

  defp download_file(url) do
    # <-- no headers here!
    Finch.build(:get, url)
    |> Finch.request(Redactly.Finch)
    |> case do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        {:ok, body}

      error ->
        Logger.error("[Notion] File download failed: #{inspect(error)}")
        :error
    end
  end

  defp guess_mime_type(url) do
    url
    |> String.split("?")
    |> hd()
    |> Path.extname()
    |> String.downcase()
    |> case do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".pdf" -> "application/pdf"
      _ -> "application/octet-stream"
    end
  end

  defp extract_property(%{"type" => "rich_text", "rich_text" => rich_text}) do
    Enum.map(rich_text, fn %{"plain_text" => text} -> text end)
    |> Enum.join()
  end

  defp extract_property(%{"type" => "title", "title" => title}) do
    Enum.map(title, fn %{"plain_text" => text} -> text end)
    |> Enum.join()
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
