defmodule RedactlyWeb.NotionEventController do
  use RedactlyWeb, :controller

  require Logger

  alias Redactly.Notion

  @spec event(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def event(conn, %{
        "type" => "page.content_updated",
        "entity" => %{"id" => page_id},
        "authors" => authors
      }) do
    Logger.debug("[Notion] Received page.content_updated for #{page_id}")
    Task.start(fn -> Notion.handle_updated_page(page_id, authors) end)
    send_resp(conn, 200, "ok")
  end

  def event(conn, _params) do
    Logger.debug("[Notion] Ignoring unrecognized webhook event")
    send_resp(conn, 200, "ignored")
  end
end
