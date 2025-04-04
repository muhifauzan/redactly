defmodule Redactly.Notion do
  @moduledoc "Coordinates Notion ticket polling and PII enforcement."

  alias Redactly.PII.Scanner
  alias Redactly.Integrations.{Notion, Slack}
  alias Redactly.Notion.{Deleter, Linker}

  @spec poll_for_tickets() :: :ok
  def poll_for_tickets do
    db_id = System.fetch_env!("NOTION_DATABASE_ID")
    pages = Notion.query_database(db_id)

    Enum.each(pages, fn page ->
      content = Notion.extract_content(page)

      if Scanner.contains_pii?(content) do
        page_id = page["id"]
        Deleter.delete_page(page_id)

        user_email = Notion.extract_author_email(page)

        case Linker.slack_user_id_from_email(user_email) do
          {:ok, slack_id} ->
            Slack.send_dm(slack_id, """
            🚨 Your Notion ticket was removed because it contained PII.

            Please recreate the ticket without sensitive information:

            > #{content}
            """)

          :error ->
            # Optional: log or report failure to link
            :noop
        end
      end
    end)

    :ok
  end
end
