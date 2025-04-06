defmodule Redactly.Notion do
  @moduledoc "Handles Notion events."

  require Logger
  alias Redactly.Integrations.Slack
  alias Redactly.Integrations.Notion, as: NotionAPI
  alias Redactly.PII.Scanner

  @spec handle_updated_page(String.t(), %{text: [String.t()], files: [map()]}, String.t()) :: :ok
  def handle_updated_page(page_id, %{text: lines, files: files}, slack_user_id) do
    Logger.debug("[Notion] Scanning page #{page_id} for PII")

    case Scanner.scan(Enum.join(lines, "\n"), files) do
      {:ok, pii_items} ->
        Logger.info("[Notion] PII detected in page #{page_id}, deleting...")

        case NotionAPI.archive_page(page_id) do
          :ok ->
            grouped =
              Enum.group_by(pii_items, fn %{"source" => src} -> src || "Message text" end)

            formatted =
              grouped
              |> Enum.map(fn {source, items} ->
                header =
                  if source == "Message text" do
                    "*In content:*"
                  else
                    "*In file _#{source}_:*"
                  end

                header <> "\n" <> Enum.map_join(items, "\n", &format_item/1)
              end)
              |> Enum.join("\n\n")

            quoted =
              lines
              |> Enum.map(&("> " <> &1))
              |> Enum.join("\n")

            Slack.send_dm(slack_user_id, """
            🚨 Your Notion ticket was removed because it contained PII.

            #{formatted}

            *Original ticket:*
            #{quoted}
            """)

            Enum.each(files, fn file ->
              Slack.upload_file_to_user(slack_user_id, file.name, file.data, file.mime_type)
            end)

          {:error, reason} ->
            Logger.error("[Notion] Failed to delete page #{page_id}: #{inspect(reason)}")
        end

      :empty ->
        Logger.debug("[Notion] No PII found in page #{page_id}")

      {:error, reason} ->
        Logger.error("[Notion] Failed to scan page #{page_id}: #{inspect(reason)}")
    end
  end

  defp format_item(%{"type" => type, "value" => value}), do: "- #{type}: #{value}"
end
