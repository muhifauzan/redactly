defmodule RedactlyWeb.SlackEventController do
  use RedactlyWeb, :controller

  require Logger

  alias Redactly.Slack.Ingestor

  def event(conn, %{"type" => "url_verification", "challenge" => challenge}) do
    json(conn, %{challenge: challenge})
  end

  def event(conn, %{"type" => "event_callback"} = params) do
    Logger.debug("Slack event received: #{inspect(params)}")

    Task.start(fn -> Ingestor.handle_event(params) end)
    send_resp(conn, 200, "ok")
  end

  def event(conn, _params) do
    # fallback: accept and ignore unrecognized event types
    send_resp(conn, 200, "ignored")
  end
end
