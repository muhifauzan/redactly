defmodule Redactly.Notion.Linker do
  @moduledoc """
  Maps a Notion author's email to a Slack user ID.
  """

  @spec slack_user_id_from_email(String.t()) :: {:ok, String.t()} | :error
  def slack_user_id_from_email(email) do
    # TODO: call Redactly.Integrations.Slack.lookup_user_by_email/1
    {:ok, "U123456"}
  end
end
