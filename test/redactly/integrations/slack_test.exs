defmodule Redactly.Integrations.SlackTest do
  use ExUnit.Case, async: true

  alias Redactly.Integrations.Slack

  setup do
    System.put_env("SLACK_BOT_TOKEN", "xoxb-test")
    System.put_env("SLACK_USER_TOKEN", "xoxp-test")
    :ok
  end

  describe "delete_message/2" do
    test "returns :ok when Slack confirms deletion" do
      Req.Test.stub(Slack, &Req.Test.json(&1, %{"ok" => true}))

      assert :ok = Slack.delete_message("C123", "456.789")
    end

    @tag :capture_log
    test "returns {:error, reason} on Slack API failure" do
      Req.Test.stub(Slack, &Req.Test.json(&1, %{"ok" => false, "error" => "channel_not_found"}))

      assert {:error, "channel_not_found"} = Slack.delete_message("C123", "456.789")
    end

    @tag :capture_log
    test "returns {:error, reason} on transport failure" do
      Req.Test.stub(Slack, &Req.Test.transport_error(&1, :econnrefused))

      assert {:error, %{reason: :econnrefused}} = Slack.delete_message("C123", "456.789")
    end
  end

  describe "lookup_user_by_email/1" do
    test "returns {:ok, user_id} on success" do
      Req.Test.stub(Slack, &Req.Test.json(&1, %{"ok" => true, "user" => %{"id" => "U123"}}))

      assert {:ok, "U123"} = Slack.lookup_user_by_email("test@example.com")
    end

    @tag :capture_log
    test "returns {:error, reason} on user not found" do
      Req.Test.stub(Slack, &Req.Test.json(&1, %{"ok" => false, "error" => "users_not_found"}))

      assert {:error, "users_not_found"} = Slack.lookup_user_by_email("missing@example.com")
    end
  end

  describe "send_dm/2" do
    test "returns :ok when both open_conversation and post_message succeed" do
      Req.Test.expect(Slack, &Req.Test.json(&1, %{"ok" => true, "channel" => %{"id" => "CH1"}}))
      Req.Test.expect(Slack, &Req.Test.json(&1, %{"ok" => true}))

      assert :ok = Slack.send_dm("U123", "Hello!")
    end

    @tag :capture_log
    test "returns {:error, reason} if opening conversation fails" do
      Req.Test.stub(Slack, &Req.Test.json(&1, %{"ok" => false, "error" => "users_not_found"}))

      assert {:error, "users_not_found"} = Slack.send_dm("U404", "Hi")
    end

    @tag :capture_log
    test "returns {:error, reason} if message post fails" do
      Req.Test.expect(Slack, &Req.Test.json(&1, %{"ok" => true, "channel" => %{"id" => "CH1"}}))
      Req.Test.expect(Slack, &Req.Test.json(&1, %{"ok" => false, "error" => "invalid_payload"}))

      assert {:error, "invalid_payload"} = Slack.send_dm("U123", "")
    end
  end
end
