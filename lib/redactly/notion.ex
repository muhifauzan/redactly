defmodule Redactly.Notion do
  @moduledoc "Coordinates Notion ticket updates and PII enforcement."

  require Logger

  alias Redactly.PII.Scanner
  alias Redactly.Integrations.{Notion, Slack}

  @spec handle_updated_page(String.t(), String.t()) :: :ok
  def handle_updated_page(page_id, author_id) do
    Logger.info("[Notion] Handling update for page #{page_id}")

    case Notion.fetch_page(page_id) do
      {:ok, page} ->
        content = Notion.extract_content(page)

        if Scanner.contains_pii?(content) do
          Logger.info("[Notion] Detected PII — deleting page #{page_id}")
          Notion.delete_page(page_id)

          user_email = Notion.fetch_user_email(author_id)

          case Slack.lookup_user_by_email(user_email) do
            {:ok, slack_id} ->
              Slack.send_dm(slack_id, """
              🚨 Your Notion ticket was removed because it contained PII.

              Please recreate the ticket without sensitive information:

              > #{content}
              """)

            :error ->
              Logger.warning("[Notion] Could not map author email to Slack ID: #{user_email}")
          end
        end

      {:error, reason} ->
        Logger.error("[Notion] Skipping page #{page_id} due to fetch failure: #{inspect(reason)}")
    end

    :ok
  end
end
