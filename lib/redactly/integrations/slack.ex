defmodule Redactly.Integrations.Slack do
  @moduledoc """
  Slack Web API integration.
  """

  require Logger

  alias Finch.Response

  @slack_api "https://slack.com/api"
  @headers [{"Content-Type", "application/json; charset=utf-8"}]

  @spec delete_message(String.t(), String.t()) :: :ok | {:error, any()}
  def delete_message(channel, ts) do
    body = Jason.encode!(%{"channel" => channel, "ts" => ts})

    Finch.build(:post, "#{@slack_api}/chat.delete", user_auth_headers(), body)
    |> Finch.request(Redactly.Finch)
    |> handle_response(fn ->
      Logger.info("[Slack] Deleted message at #{ts} in #{channel}")
    end)
  end

  @spec send_dm(String.t(), String.t()) :: :ok | {:error, any()}
  def send_dm(user_id, text) do
    conv_body = Jason.encode!(%{"users" => user_id})

    with {:ok, %Response{status: 200, body: conv_json}} <-
           Finch.build(:post, "#{@slack_api}/conversations.open", bot_auth_headers(), conv_body)
           |> Finch.request(Redactly.Finch),
         {:ok, %{"ok" => true, "channel" => %{"id" => channel_id}}} <- Jason.decode(conv_json) do
      msg_body = Jason.encode!(%{"channel" => channel_id, "text" => text})

      Finch.build(:post, "#{@slack_api}/chat.postMessage", bot_auth_headers(), msg_body)
      |> Finch.request(Redactly.Finch)
      |> handle_response(fn ->
        Logger.info("[Slack] DM sent to user #{user_id}")
      end)
    else
      {:ok, %{"error" => error}} ->
        Logger.error("[Slack] Failed to open conversation: #{error}")
        {:error, error}

      error ->
        Logger.error("[Slack] Failed to open conversation: #{inspect(error)}")
        {:error, error}
    end
  end

  @spec lookup_user_by_email(String.t()) :: {:ok, String.t()} | :error
  def lookup_user_by_email(_email), do: :error

  defp handle_response({:ok, %Response{status: 200, body: body}}, success_log_fn) do
    case Jason.decode(body) do
      {:ok, %{"ok" => true}} ->
        success_log_fn.()
        :ok

      {:ok, %{"error" => error}} ->
        Logger.error("[Slack] API error: #{error}")
        {:error, error}

      _ ->
        Logger.error("[Slack] Unexpected response body")
        {:error, :unexpected_response}
    end
  end

  defp handle_response({:error, reason}, _), do: {:error, reason}

  defp bot_auth_headers do
    bot_token = Application.fetch_env!(:redactly, :slack)[:bot_token]
    [{"Authorization", "Bearer #{bot_token}"} | @headers]
  end

  defp user_auth_headers do
    user_token = Application.fetch_env!(:redactly, :slack)[:user_token]
    [{"Authorization", "Bearer #{user_token}"} | @headers]
  end
end
