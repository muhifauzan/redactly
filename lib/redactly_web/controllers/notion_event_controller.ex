defmodule RedactlyWeb.NotionEventController do
  use RedactlyWeb, :controller
  require Logger

  alias Redactly.Notion
  alias Redactly.Integrations.Notion, as: NotionAPI
  alias Redactly.Integrations.Slack

  def event(conn, %{
        "type" => "page.content_updated",
        "entity" => %{"id" => page_id},
        "data" => %{"parent" => %{"type" => "database"}},
        "authors" => [%{"id" => notion_user_id} | _]
      }) do
    Logger.debug("[Notion] Received page.content_updated for #{page_id}")

    Task.start(fn ->
      content = NotionAPI.extract_page_content(page_id)

      with email when is_binary(email) and email != "" <-
             NotionAPI.fetch_user_email(notion_user_id),
           {:ok, slack_user_id} <- Slack.lookup_user_by_email(email) do
        Notion.handle_updated_page(page_id, content, slack_user_id)
      else
        _ ->
          Logger.warning("[Notion] Could not resolve Slack user for page #{page_id}")
      end
    end)

    send_resp(conn, 200, "ok")
  end

  def event(conn, params) do
    Logger.debug("[Notion] Ignoring unsupported event: #{inspect(params)}")
    send_resp(conn, 200, "ignored")
  end
end
