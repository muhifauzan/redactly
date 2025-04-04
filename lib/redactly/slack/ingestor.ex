defmodule Redactly.Slack.Ingestor do
  @moduledoc """
  Handles incoming Slack messages via Events API.
  """

  require Logger

  @spec handle_event(map()) :: :ok
  def handle_event(%{"event" => %{"text" => text, "user" => user} = event}) do
    Logger.info("[Slack] Received message from #{user}: #{inspect(text)}")

    # TODO: Add call to PII scanner + delete + DM logic
    :ok
  end

  @spec handle_event(map()) :: :ok
  def handle_event(_other), do: :ok
end
