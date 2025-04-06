defmodule Redactly.Integrations.Slack do
  @moduledoc """
  Slack Web API integration.
  """

  require Logger

  alias Finch.Response
  alias Multipart.Part

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
  def lookup_user_by_email(email) do
    url = "#{@slack_api}/users.lookupByEmail?email=#{URI.encode_www_form(email)}"

    case Finch.build(:get, url, bot_auth_headers())
         |> Finch.request(Redactly.Finch) do
      {:ok, %Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"ok" => true, "user" => %{"id" => slack_id}}} ->
            {:ok, slack_id}

          {:ok, %{"error" => error}} ->
            Logger.error("[Slack] Failed to find user by email: #{error}")
            :error

          _ ->
            Logger.error("[Slack] Unexpected response body during email lookup")
            :error
        end

      {:error, reason} ->
        Logger.error("[Slack] Error looking up user by email: #{inspect(reason)}")
        :error
    end
  end

  @spec upload_file_to_user(String.t(), String.t(), binary(), String.t()) :: :ok | {:error, any()}
  def upload_file_to_user(user_id, filename, data, mime_type) do
    with {:ok, channel_id} <- open_dm_channel(user_id),
         {:ok, upload_url, file_id} <- get_upload_url(filename, byte_size(data), mime_type),
         :ok <-
           upload_file_to_url(upload_url, %{filename: filename, data: data, mime_type: mime_type}),
         :ok <- complete_upload(file_id, channel_id, filename) do
      Logger.info("[Slack] File uploaded to user #{user_id}")
      :ok
    else
      {:error, reason} ->
        Logger.error("[Slack] File upload failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp open_dm_channel(user_id) do
    body = Jason.encode!(%{"users" => user_id})

    Finch.build(:post, "#{@slack_api}/conversations.open", bot_auth_headers(), body)
    |> Finch.request(Redactly.Finch)
    |> case do
      {:ok, %Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"ok" => true, "channel" => %{"id" => channel_id}}} ->
            {:ok, channel_id}

          {:ok, %{"error" => error}} ->
            {:error, error}

          _ ->
            {:error, :unexpected_response}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_upload_url(filename, length, mime_type) do
    body =
      URI.encode_query(%{
        "token" => System.get_env("SLACK_BOT_TOKEN"),
        "filename" => filename,
        "length" => length
      })

    headers = [
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]

    Finch.build(:post, "https://slack.com/api/files.getUploadURLExternal", headers, body)
    |> Finch.request(Redactly.Finch)
    |> case do
      {:ok, %Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"ok" => true, "upload_url" => upload_url, "file_id" => file_id}} ->
            {:ok, upload_url, file_id}

          {:ok, %{"error" => error}} ->
            Logger.error("Failed to get upload URL: #{error}")
            {:error, error}

          _ ->
            Logger.error("Unexpected response body during get upload URL")
            {:error, :unexpected_response}
        end

      {:error, reason} ->
        Logger.error("Error getting upload URL: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp upload_file_to_url(upload_url, %{filename: filename, data: data, mime_type: mime_type}) do
    multipart =
      Multipart.new()
      |> Multipart.add_part(
        Part.binary_body(data, [
          {"content-disposition", ~s(form-data; name="file"; filename="#{filename}")},
          {"content-type", mime_type}
        ])
      )

    body_stream = Multipart.body_stream(multipart)
    content_length = Multipart.content_length(multipart)
    content_type = Multipart.content_type(multipart, "multipart/form-data")

    headers = [
      {"Content-Type", content_type},
      {"Content-Length", to_string(content_length)}
    ]

    Finch.build(:post, upload_url, headers, {:stream, body_stream})
    |> Finch.request(Redactly.Finch)
    |> case do
      {:ok, %Response{status: 200}} ->
        Logger.debug("[Slack] File uploaded to presigned URL successfully")
        :ok

      {:ok, %Response{status: status, body: body}} ->
        Logger.error("[Slack] Multipart upload failed with status #{status}: #{inspect(body)}")
        {:error, :multipart_failed}

      {:error, reason} ->
        Logger.error("[Slack] File PUT failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp complete_upload(file_id, channel_id, filename) do
    body =
      Jason.encode!(%{
        "channel_id" => channel_id,
        "files" => [
          %{
            "id" => file_id,
            "title" => filename
          }
        ]
      })

    Finch.build(:post, "#{@slack_api}/files.completeUploadExternal", bot_auth_headers(), body)
    |> Finch.request(Redactly.Finch)
    |> case do
      {:ok, %Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"ok" => true}} -> :ok
          {:ok, %{"error" => error}} -> {:error, error}
          _ -> {:error, :unexpected_response}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_response({:ok, %Response{status: 200, body: body}}, success_log_fn) do
    case Jason.decode(body) do
      {:ok, %{"ok" => true}} ->
        success_log_fn.()
        :ok

      {:ok, %{"ok" => false, "error" => error}} ->
        {:error, error}

      _ ->
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
