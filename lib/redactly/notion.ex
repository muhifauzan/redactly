defmodule Redactly.Notion do
  @moduledoc "Coordinates Notion ticket updates and PII enforcement."

  require Logger

  alias Redactly.PII.Scanner
  alias Redactly.Integrations.{Notion, Slack}

  @spec handle_updated_page(String.t(), list(map())) :: :ok
  def handle_updated_page(page_id, authors) do
    Logger.info("[Notion] Handling update for page #{page_id}")

    case Notion.fetch_page(page_id) do
      {:ok, page} ->
        content = Notion.extract_content(page)
        block_text = Notion.fetch_block_texts(page_id)

        full_content =
          [content, block_text]
          |> Enum.reject(&(&1 == ""))
          |> Enum.join("\n")

        quoted_content =
          full_content
          |> String.split("\n")
          |> Enum.map(&("> " <> &1))
          |> Enum.join("\n")

        case Scanner.scan(full_content) do
          {:ok, pii_items} ->
            Logger.info("[Notion] Detected PII — deleting page #{page_id}")
            Notion.delete_page(page_id)

            user_email =
              authors
              |> List.first()
              |> Map.get("id")
              |> then(&Notion.fetch_user_email/1)

            case Slack.lookup_user_by_email(user_email) do
              {:ok, slack_id} ->
                formatted_items =
                  pii_items
                  |> Enum.map(fn %{"type" => type, "value" => value} -> "- #{type}: #{value}" end)
                  |> Enum.join("\n")

                Slack.send_dm(slack_id, """
                🚨 Your Notion ticket was removed because it contained PII.

                Flagged content:

                #{formatted_items}

                Original post:

                #{quoted_content}
                """)

              :error ->
                Logger.warning("[Notion] Could not map author email to Slack ID: #{user_email}")
            end

          :empty ->
            Logger.debug("[Notion] No PII found in page #{page_id}")
        end

      {:error, reason} ->
        Logger.error("[Notion] Could not handle page #{page_id}: #{inspect(reason)}")
    end

    :ok
  end
end
