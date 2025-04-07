defmodule Redactly.Integrations.Notion do
  @moduledoc "Handles Notion API interactions."

  alias Redactly.Integrations.FileUtils

  require Logger

  @base_url "https://api.notion.com/v1"

  @spec archive_page(String.t()) :: :ok | {:error, any()}
  def archive_page(page_id) do
    Req.patch(client(), url: "/pages/#{page_id}", json: %{"archived" => true})
    |> handle_response("archive_page", nil, fn _ ->
      Logger.info("[Notion] Archived page #{page_id}")
    end)
  end

  @spec fetch_user_email(String.t()) :: String.t()
  def fetch_user_email(notion_user_id) do
    Req.get(client(), url: "/users/#{notion_user_id}")
    |> handle_response(
      "fetch_user_email",
      fn
        %{"person" => %{"email" => email}} -> email
        _ -> ""
      end,
      fn _ ->
        Logger.debug("[Notion] Fetched email for user #{notion_user_id}")
      end
    )
  rescue
    _ -> ""
  end

  @spec fetch_user_email_from_page(String.t()) :: String.t()
  def fetch_user_email_from_page(page_id) do
    Req.get(client(), url: "/pages/#{page_id}")
    |> handle_response("fetch_user_email_from_page", fn
      %{"created_by" => %{"id" => user_id}} ->
        fetch_user_email(user_id)

      _ ->
        Logger.warning("[Notion] Could not extract created_by from page #{page_id}")
        ""
    end)
    |> case do
      {:ok, email} -> email
      {:error, _} -> ""
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

  ## Private

  defp extract_block_text_and_files(page_id) do
    Req.get(client(),
      url: "/blocks/#{page_id}/children?page_size=100",
      headers: [{"Content-Type", ""}]
    )
    |> handle_response("extract_block_text_and_files", fn %{"results" => blocks} ->
      Enum.reduce(blocks, {[], []}, fn block, {text_acc, file_acc} ->
        case block do
          %{"type" => type} ->
            case Map.get(block, type) do
              %{"rich_text" => rich_text} when is_list(rich_text) ->
                lines = Enum.map(rich_text, & &1["plain_text"])
                {text_acc ++ lines, file_acc}

              %{"type" => "file", "file" => %{"url" => url}} ->
                filename = url |> String.split("?") |> hd() |> Path.basename()
                line = "[file: #{filename}]"

                case FileUtils.download(url) do
                  {:ok, data} ->
                    file = %{
                      name: filename,
                      mime_type: FileUtils.guess_mime_type(url),
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
    end)
    |> case do
      {:ok, result} -> result
      {:error, _} -> {[], []}
    end
  end

  defp extract_page_properties(page_id) do
    Req.get(client(), url: "/pages/#{page_id}")
    |> handle_response("extract_page_properties", fn
      %{"properties" => props} ->
        Enum.map(props, fn {name, value} ->
          text = extract_property(value)
          "#{name}: #{text}"
        end)

      _ ->
        Logger.warning("[Notion] No properties in page #{page_id}")
        []
    end)
    |> case do
      {:ok, lines} -> lines
      {:error, _} -> []
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

  defp client do
    Req.new(
      base_url: @base_url,
      finch: Redactly.Finch,
      retry: :safe_transient,
      json: true,
      headers: [
        {"Authorization", "Bearer #{api_token()}"},
        {"Notion-Version", "2022-06-28"},
        {"Content-Type", "application/json"}
      ]
    )
    |> Req.merge(req_options())
  end

  defp req_options do
    Application.get_env(:redactly, :notion_req_options)
  end

  defp api_token do
    Application.fetch_env!(:redactly, :notion)[:api_token]
  end

  defp handle_response(response, label, value_fun, log_fun \\ nil)

  defp handle_response({:ok, %{body: body}}, _label, value_fun, log_fun) when is_map(body) do
    if is_function(log_fun, 1), do: log_fun.(body)

    if is_function(value_fun, 1) do
      {:ok, value_fun.(body)}
    else
      :ok
    end
  end

  defp handle_response({:ok, %{status: status, body: body}}, label, _, _) do
    Logger.error("[Notion] Unexpected response (#{label}): #{status} - #{inspect(body)}")
    {:error, :unexpected_response}
  end

  defp handle_response({:error, reason}, label, _, _) do
    Logger.error("[Notion] HTTP error during #{label}: #{inspect(reason)}")
    {:error, reason}
  end
end
