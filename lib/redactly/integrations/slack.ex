defmodule Redactly.Integrations.Slack do
  @moduledoc "Handles Slack API interactions."

  @spec delete_message(String.t(), String.t()) :: :ok | {:error, term()}
  def delete_message(_channel, _ts), do: :ok

  @spec send_dm(String.t(), String.t()) :: :ok | {:error, term()}
  def send_dm(_user_id, _message), do: :ok

  @spec lookup_user_by_email(String.t()) :: {:ok, String.t()} | :error
  def lookup_user_by_email(_email), do: {:ok, "U123456"}
end
