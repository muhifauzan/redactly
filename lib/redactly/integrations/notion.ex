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

  @spec archive_page(String.t()) :: :ok | {:error, any()}
  def archive_page(page_id) do
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
    properties_text = extract_page_properties(page_id)
    {block_text, files} = extract_block_text_and_files(page_id)

    %{
      text: properties_text ++ block_text,
      files: files
    }
  end

  defp extract_block_text_and_files(page_id) do
    url = "#{@notion_api}/blocks/#{page_id}/children?page_size=100"

    case Finch.build(:get, url, headers()) |> Finch.request(Redactly.Finch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"results" => blocks}} ->
            Enum.reduce(blocks, {[], []}, fn block, {text_acc, file_acc} ->
              case block do
                %{"type" => type} ->
                  case Map.get(block, type) do
                    %{"rich_text" => rich_text} when is_list(rich_text) ->
                      lines =
                        Enum.map(rich_text, fn %{"plain_text" => t} -> t end)

                      {text_acc ++ lines, file_acc}

                    %{"type" => "file", "file" => %{"url" => url}} ->
                      filename = url |> String.split("?") |> hd() |> Path.basename()
                      line = "[file: #{filename}]"

                      case download_file(url) do
                        {:ok, data} ->
                          file = %{
                            name: filename,
                            mime_type: guess_mime_type(url),
                            data: data
                          }

                          {text_acc ++ [line], [file | file_acc]}

                        _ ->
                          Logger.warning("[Notion] Failed to download file from #{url}")
                          {text_acc ++ [line], file_acc}
                      end

                    _ ->
                      {text_acc, file_acc}
                  end

                _ ->
                  {text_acc, file_acc}
              end
            end)

          _ ->
            Logger.error("[Notion] Unexpected body when fetching blocks")
            {[], []}
        end

      {:ok, %Finch.Response{status: status, body: body}} ->
        Logger.error("[Notion] Failed to fetch blocks (#{status}): #{body}")
        {[], []}

      {:error, reason} ->
        Logger.error("[Notion] Error fetching blocks: #{inspect(reason)}")
        {[], []}
    end
  end

  defp extract_page_properties(page_id) do
    url = "#{@notion_api}/pages/#{page_id}"

    case Finch.build(:get, url, headers()) |> Finch.request(Redactly.Finch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"properties" => props}} ->
            Enum.map(props, fn {name, value} ->
              text = extract_property(value)
              "#{name}: #{text}"
            end)

          _ ->
            Logger.warning("[Notion] No properties in page #{page_id}")
            []
        end

      {:ok, %Finch.Response{status: status, body: body}} ->
        Logger.error("[Notion] Failed to fetch page props (#{status}): #{body}")
        []

      {:error, reason} ->
        Logger.error("[Notion] Error fetching page props: #{inspect(reason)}")
        []
    end
  end

  defp extract_files_from_blocks(page_id) do
    url = "#{@notion_api}/blocks/#{page_id}/children?page_size=100"

    case Finch.build(:get, url, headers()) |> Finch.request(Redactly.Finch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"results" => blocks}} ->
            Enum.reduce(blocks, [], fn block, acc ->
              case block do
                %{"type" => type} ->
                  case Map.get(block, type) do
                    %{"type" => "file", "file" => %{"url" => url}} ->
                      with {:ok, data} <- download_file(url) do
                        file = %{
                          name: url |> String.split("?") |> hd() |> Path.basename(),
                          mime_type: guess_mime_type(url),
                          data: data
                        }

                        [file | acc]
                      else
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
            Logger.warning("[Notion] Unexpected block structure for file scan")
            []
        end

      {:ok, %Finch.Response{status: status, body: body}} ->
        Logger.error("[Notion] Failed to fetch blocks for file scan (#{status}): #{body}")
        []

      {:error, reason} ->
        Logger.error("[Notion] File block fetch error: #{inspect(reason)}")
        []
    end
  end

  @spec fetch_user_email_from_page(String.t()) :: String.t()
  def fetch_user_email_from_page(page_id) do
    url = "#{@notion_api}/pages/#{page_id}"

    case Finch.build(:get, url, headers())
         |> Finch.request(Redactly.Finch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          %{"created_by" => %{"id" => user_id}} ->
            fetch_user_email(user_id)

          _ ->
            Logger.warning("[Notion] Could not extract created_by from page #{page_id}")
            ""
        end

      error ->
        Logger.error("[Notion] Could not fetch page details: #{inspect(error)}")
        ""
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

  defp extract_property(%{"type" => "title", "title" => title}),
    do: join_plain_text(title)

  defp extract_property(%{"type" => "rich_text", "rich_text" => rich_text}),
    do: join_plain_text(rich_text)

  defp extract_property(%{"type" => "select", "select" => %{"name" => name}}),
    do: name

  defp extract_property(%{"type" => "multi_select", "multi_select" => list}) when is_list(list),
    do: Enum.map_join(list, ", ", & &1["name"])

  defp extract_property(%{"type" => "number", "number" => number}) when not is_nil(number),
    do: to_string(number)

  defp extract_property(%{"type" => "date", "date" => %{"start" => start}})
       when not is_nil(start),
       do: start

  defp extract_property(%{"type" => "checkbox", "checkbox" => val}),
    do: if(val, do: "✓", else: "✗")

  defp extract_property(%{"type" => "people", "people" => people}) when is_list(people),
    do: Enum.map_join(people, ", ", fn person -> person["name"] || "Unnamed" end)

  defp extract_property(%{"type" => "url", "url" => url}) when is_binary(url),
    do: url

  defp extract_property(%{"type" => "relation", "relation" => rels}) when is_list(rels),
    do: "#{length(rels)} linked"

  defp extract_property(%{
         "type" => "rollup",
         "rollup" => %{"type" => _, "function" => _, "number" => num}
       })
       when is_number(num),
       do: to_string(num)

  defp extract_property(%{
         "type" => "formula",
         "formula" => %{"type" => "number", "number" => num}
       })
       when is_number(num),
       do: to_string(num)

  defp extract_property(_), do: ""

  defp join_plain_text(items) when is_list(items) do
    items
    |> Enum.map(& &1["plain_text"])
    |> Enum.join()
  end

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
