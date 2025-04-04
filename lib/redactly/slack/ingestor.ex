defmodule Redactly.Slack.Ingestor do
  @moduledoc """
  Handles incoming Slack messages via Events API.
  """

  require Logger

  alias Redactly.{PII.Scanner, Integrations.Slack}

  @spec handle_event(map()) :: :ok
  def handle_event(%{
        "event" => %{
          "type" => "message",
          "text" => text,
          "user" => user_id,
          "channel" => channel,
          "ts" => ts
        }
      }) do
    Logger.info("[Slack] Received message from #{user_id}: #{inspect(text)}")

    if Scanner.contains_pii?(text) do
      Logger.info("[Slack] Detected PII — deleting + notifying #{user_id}")

      Slack.delete_message(channel, ts)

      Slack.send_dm(user_id, """
      🚨 Your message was removed because it contained PII.

      Please repost without the sensitive information:

      > #{text}
      """)
    end

    :ok
  end

  def handle_event(_), do: :ok
end
