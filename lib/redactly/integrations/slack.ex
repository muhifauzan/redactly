defmodule Redactly.Integrations.Slack do
  @moduledoc "Slack Web API integration using Req."

  alias Redactly.Integrations.FileUtils

  require Logger

  @base_url "https://slack.com/api"

  @spec delete_message(String.t(), String.t()) :: :ok | {:error, any()}
  def delete_message(channel, ts) do
    req = client(user_token())

    Req.post(req, url: "/chat.delete", json: %{"channel" => channel, "ts" => ts})
    |> handle_response("delete", nil, fn _ ->
      Logger.info("[Slack] Deleted message at #{ts} in #{channel}")
    end)
  end

  @spec send_dm(String.t(), String.t()) :: :ok | {:error, any()}
  def send_dm(user_id, text) do
    req = client(bot_token())

    with {:ok, channel_id} <- open_conversation(req, user_id),
         :ok <- post_message(req, channel_id, text) do
      Logger.info("[Slack] DM sent to user #{user_id}")
      :ok
    else
      {:error, reason} ->
        Logger.warning("[Slack] Failed to send DM to #{user_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @spec lookup_user_by_email(String.t()) :: {:ok, String.t()} | :error
  def lookup_user_by_email(email) do
    url = "/users.lookupByEmail?email=#{URI.encode_www_form(email)}"
    req = client(bot_token())

    Req.get(req, url: url)
    |> handle_response(
      "lookup_user_by_email",
      fn %{"user" => %{"id" => id}} -> {:ok, id} end,
      fn %{"user" => %{"id" => id}} ->
        Logger.debug("[Slack] Resolved email #{email} to user ID #{id}")
      end
    )
  end

  @spec upload_file_to_user(String.t(), String.t(), binary(), String.t()) :: :ok | {:error, any()}
  def upload_file_to_user(user_id, filename, data, mime_type) do
    with {:ok, channel_id} <- open_conversation(client(bot_token()), user_id),
         {:ok, upload_url, file_id} <- get_upload_url(filename, byte_size(data), mime_type),
         :ok <-
           upload_file_to_url(upload_url, %{filename: filename, data: data, mime_type: mime_type}),
         :ok <- complete_upload(file_id, channel_id, filename) do
      Logger.info("[Slack] File #{filename} uploaded to user #{user_id}")
      :ok
    else
      {:error, reason} ->
        Logger.warning("[Slack] File upload failed for #{filename}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def download_file(url) do
    FileUtils.download(url, [{"Authorization", "Bearer #{bot_token()}"}])
  end

  ## Private

  defp get_upload_url(filename, length, _mime_type) do
    Req.post(client(bot_token()),
      url: "/files.getUploadURLExternal",
      form: %{
        "filename" => filename,
        "length" => to_string(length)
      }
    )
    |> handle_response(
      "get_upload_url",
      fn %{"upload_url" => url, "file_id" => id} -> {:ok, url, id} end,
      fn _ ->
        Logger.debug("[Slack] Got presigned upload URL for #{filename}")
      end
    )
  end

  defp upload_file_to_url(url, %{filename: filename, data: data, mime_type: mime}) do
    multipart =
      Multipart.new()
      |> Multipart.add_part(
        Multipart.Part.binary_body(data, [
          {"content-disposition", ~s(form-data; name="file"; filename="#{filename}")},
          {"content-type", mime}
        ])
      )

    headers = [
      {"Content-Type", Multipart.content_type(multipart, "multipart/form-data")},
      {"Content-Length", Multipart.content_length(multipart) |> to_string()}
    ]

    Req.post(
      Req.new(finch: Redactly.Finch),
      url: url,
      headers: headers,
      body: Multipart.body_stream(multipart)
    )
    |> case do
      {:ok, %{status: 200}} ->
        Logger.debug("[Slack] File uploaded to presigned URL for #{filename}")
        :ok

      {:ok, %{status: status, body: body}} ->
        Logger.error("[Slack] Upload failed with status #{status}: #{inspect(body)}")
        {:error, :upload_failed}

      {:error, reason} ->
        Logger.error("[Slack] Upload request error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp complete_upload(file_id, channel_id, filename) do
    Req.post(client(bot_token()),
      url: "/files.completeUploadExternal",
      json: %{
        "channel_id" => channel_id,
        "files" => [%{"id" => file_id, "title" => filename}]
      }
    )
    |> handle_response("complete_upload", nil, fn _ ->
      Logger.debug("[Slack] Completed upload for #{filename}")
    end)
  end

  ## Private

  defp open_conversation(req, user_id) do
    Req.post(req, url: "/conversations.open", json: %{"users" => user_id})
    |> handle_response(
      "open_conversation",
      fn %{"channel" => %{"id" => id}} -> {:ok, id} end,
      fn _ ->
        Logger.debug("[Slack] Opened DM channel for user #{user_id}")
      end
    )
  end

  defp post_message(req, channel_id, text) do
    Req.post(req, url: "/chat.postMessage", json: %{"channel" => channel_id, "text" => text})
    |> handle_response("post_message", nil, fn _ ->
      Logger.debug("[Slack] Sent message to channel #{channel_id}")
    end)
  end

  defp handle_response({:ok, %{body: %{"ok" => true} = body}}, _label, value_fun, log_fun) do
    if is_function(log_fun, 1) do
      log_fun.(body)
    end

    if is_function(value_fun, 1) do
      value_fun.(body)
    else
      :ok
    end
  end

  defp handle_response({:ok, %{body: %{"error" => error}}}, label, _, _) do
    level =
      if error in ["users_not_found", "channel_not_found"] do
        :warning
      else
        :error
      end

    Logger.log(level, "[Slack] Slack API error in #{label}: #{error}")
    {:error, error}
  end

  defp handle_response({:error, reason}, label, _, _) do
    Logger.error("[Slack] HTTP error in #{label}: #{inspect(reason)}")
    {:error, reason}
  end

  defp client(token) do
    Req.new(
      base_url: @base_url,
      finch: Redactly.Finch,
      retry: :safe_transient,
      json: true,
      headers: [
        {"Authorization", "Bearer #{token}"}
      ]
    )
    |> Req.merge(req_options())
  end

  defp req_options do
    Application.get_env(:redactly, :slack_req_options)
  end

  defp bot_token do
    Application.fetch_env!(:redactly, :slack)[:bot_token]
  end

  defp user_token do
    Application.fetch_env!(:redactly, :slack)[:user_token]
  end
end
