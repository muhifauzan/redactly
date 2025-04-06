defmodule Redactly.Slack.Ingestor do
  @moduledoc """
  Handles incoming Slack messages via Events API.
  """

  require Logger
  alias Redactly.{PII.Scanner, Integrations.Slack}

  @spec handle_event(map()) :: :ok

  def handle_event(%{"event" => %{"subtype" => subtype}} = event)
      when subtype in ["message_changed", "message_deleted", "bot_message"] do
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
    files = Map.get(event, "files", [])

    Logger.info("[Slack] Received message from #{user}: #{inspect(text)}")

    downloaded_files = Enum.map(files, &download_slack_file/1) |> Enum.filter(& &1)

    case Scanner.scan(text, downloaded_files) do
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

        quoted_text =
          text
          |> String.split("\n")
          |> Enum.map(&("> " <> &1))
          |> Enum.join("\n")

        Slack.send_dm(user, """
        🚨 Your message was removed because it contained PII.

        Flagged items:

        #{formatted_items}

        Original message:

        #{quoted_text}
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

  defp download_slack_file(%{"url_private" => url, "name" => name, "mimetype" => mime}) do
    headers = [
      {"Authorization", "Bearer #{bot_token()}"}
    ]

    case Finch.build(:get, url, headers) |> Finch.request(Redactly.Finch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        Logger.debug("[Slack] Downloaded file #{name} (#{mime})")
        %{name: name, mime_type: mime, data: body}

      {:ok, %Finch.Response{status: status}} ->
        Logger.warning("[Slack] Failed to fetch file #{name} (status: #{status})")
        nil

      {:error, reason} ->
        Logger.error("[Slack] Error downloading file #{name}: #{inspect(reason)}")
        nil
    end
  end

  defp download_slack_file(_), do: nil

  defp bot_token do
    Application.fetch_env!(:redactly, :slack)[:bot_token]
  end
end
