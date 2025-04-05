defmodule Redactly.Slack.Ingestor do
  @moduledoc """
  Handles incoming Slack messages via Events API.
  """

  require Logger

  alias Redactly.{PII.Scanner, Integrations.Slack}

  @spec handle_event(map()) :: :ok
  def handle_event(%{"event" => %{"subtype" => subtype}}) do
    Logger.debug("[Slack] Ignoring message with subtype #{subtype}")
    :ok
  end

  def handle_event(%{"event" => %{"bot_id" => bot_id}}) do
    Logger.debug("[Slack] Ignoring message from bot_id #{bot_id}")
    :ok
  end

  def handle_event(%{"event" => %{"type" => "message"} = event}) do
    user = event["user"]
    text = event["text"]
    channel = event["channel"]
    ts = event["ts"]

    Logger.info("[Slack] Received message from #{user}: #{inspect(text)}")

    if Scanner.contains_pii?(text) do
      Logger.info("[Slack] Detected PII — attempting to remove")

      case Slack.delete_message(channel, ts) do
        :ok ->
          Logger.info("[Slack] Message deleted successfully")

        {:error, reason} ->
          Logger.warning("[Slack] Could not delete message: #{inspect(reason)}")
      end

      Slack.send_dm(user, """
      🚨 Your message was removed because it contained PII.

      Please repost without the sensitive information:

      > #{text}
      """)
    end

    :ok
  end

  def handle_event(event) do
    Logger.debug("[Slack] Ignoring unhandled event: #{inspect(event)}")
    :ok
  end
end
