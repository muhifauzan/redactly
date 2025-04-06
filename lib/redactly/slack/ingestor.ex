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

    case Scanner.scan(text) do
      {:ok, pii_items} ->
        Logger.info("[Slack] Detected PII — attempting to remove")
        Logger.debug("[Slack] Detected PII items: #{inspect(pii_items)}")

        case Slack.delete_message(channel, ts) do
          :ok ->
            Logger.info("[Slack] Message deleted successfully")

          {:error, reason} ->
            Logger.warning("[Slack] Could not delete message: #{inspect(reason)}")
        end

        formatted_items =
          pii_items
          |> Enum.map(fn %{"type" => type, "value" => value} -> "- #{type}: #{value}" end)
          |> Enum.join("\n")

        Slack.send_dm(user, """
        🚨 Your message was removed because it contained PII.

        Flagged items:

        #{formatted_items}

        Original message:

        > #{text}
        """)

      :empty ->
        Logger.debug("[Slack] No PII detected")
        :ok

      {:error, reason} ->
        Logger.error("[Slack] Failed to scan for PII: #{inspect(reason)}")
        :ok
    end
  end

  def handle_event(event) do
    Logger.debug("[Slack] Ignoring unhandled event: #{inspect(event)}")
    :ok
  end
end
