defmodule Redactly.Integrations.NotionTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias Redactly.Integrations.Notion

  setup do
    System.put_env("NOTION_API_TOKEN", "test-token")
    :ok
  end

  describe "archive_page/1" do
    test "returns :ok on success" do
      Req.Test.stub(Notion, &Req.Test.json(&1, %{}))
      assert :ok = Notion.archive_page("page123")
    end

    test "returns error on failure" do
      Req.Test.stub(Notion, &Req.Test.transport_error(&1, :econnrefused))
      assert {:error, _} = Notion.archive_page("page123")
    end
  end

  describe "fetch_user_email/1" do
    test "returns email on success" do
      Req.Test.stub(Notion, &Req.Test.json(&1, %{"person" => %{"email" => "user@example.com"}}))
      assert Notion.fetch_user_email("U1") == "user@example.com"
    end

    test "returns empty string if person block is missing" do
      Req.Test.stub(Notion, &Req.Test.json(&1, %{}))
      assert Notion.fetch_user_email("U1") == ""
    end

    test "returns empty string if request errors" do
      Req.Test.stub(Notion, &Req.Test.transport_error(&1, :timeout))
      assert Notion.fetch_user_email("U1") == ""
    end
  end

  describe "fetch_user_email_from_page/1" do
    test "returns email when created_by is present" do
      Req.Test.expect(Notion, &Req.Test.json(&1, %{"created_by" => %{"id" => "U123"}}))
      Req.Test.expect(Notion, &Req.Test.json(&1, %{"person" => %{"email" => "me@here.com"}}))

      assert Notion.fetch_user_email_from_page("page123") == "me@here.com"
    end

    test "returns empty string when created_by is missing" do
      Req.Test.stub(Notion, &Req.Test.json(&1, %{}))
      assert Notion.fetch_user_email_from_page("page123") == ""
    end
  end

  describe "extract_page_content/1" do
    test "returns merged properties and block text with empty files" do
      Req.Test.expect(Notion, fn conn ->
        Req.Test.json(conn, %{
          "properties" => %{
            "Name" => %{"type" => "title", "title" => [%{"plain_text" => "Hello"}]}
          }
        })
      end)

      Req.Test.expect(Notion, fn conn ->
        Req.Test.json(conn, %{
          "results" => [
            %{
              "type" => "paragraph",
              "paragraph" => %{
                "rich_text" => [%{"plain_text" => "World"}]
              }
            }
          ]
        })
      end)

      result = Notion.extract_page_content("page123")

      assert result.text == ["Name: Hello", "World"]
      assert result.files == []
    end
  end
end
