defmodule Redactly.Integrations.OpenAITest do
  use ExUnit.Case, async: true

  alias Redactly.Integrations.OpenAI
  alias Redactly.Integrations.FileUtils

  setup do
    System.put_env("OPENAI_API_KEY", "test-api-key")
    :ok
  end

  describe "detect_pii/2 (text-only)" do
    test "returns :empty if no PII is detected" do
      Req.Test.stub(OpenAI, fn conn ->
        content = ~s<{"items":[]}>
        json = %{"choices" => [%{"message" => %{"content" => content}}]}
        Req.Test.json(conn, json)
      end)

      assert :empty = OpenAI.detect_pii("harmless message", [])
    end

    test "returns {:ok, items} if PII is found" do
      Req.Test.stub(OpenAI, fn conn ->
        content = ~s<{"items":[{"type":"email","value":"secret@example.com"}]}>
        json = %{"choices" => [%{"message" => %{"content" => content}}]}
        Req.Test.json(conn, json)
      end)

      assert {:ok,
              [%{"type" => "email", "value" => "secret@example.com", "source" => "Message text"}]} =
               OpenAI.detect_pii("send to secret@example.com", [])
    end

    @tag :capture_log
    test "returns :empty if OpenAI returns malformed JSON" do
      Req.Test.stub(OpenAI, fn conn ->
        Req.Test.json(conn, %{"unexpected" => "data"})
      end)

      assert :empty = OpenAI.detect_pii("malformed", [])
    end

    @tag :capture_log
    test "returns :empty if OpenAI request errors" do
      Req.Test.stub(OpenAI, &Req.Test.transport_error(&1, :timeout))

      assert :empty = OpenAI.detect_pii("timeout", [])
    end
  end

  describe "detect_pii/2 (files)" do
    test "returns {:ok, items} if one file contains PII" do
      file = %{
        name: "file.png",
        mime_type: "image/png",
        data: "binary-data"
      }

      Req.Test.stub(FileUtils, fn conn ->
        # Not used in base64, just stubbed
        Req.Test.json(conn, "fake-image")
      end)

      Req.Test.stub(OpenAI, fn conn ->
        content = ~s<{"items":[{"type":"email","value":"doc@example.com"}]}>
        json = %{"choices" => [%{"message" => %{"content" => content}}]}
        Req.Test.json(conn, json)
      end)

      {:ok, results} = OpenAI.detect_pii("irrelevant text", [file])

      assert %{"type" => "email", "value" => "doc@example.com", "source" => "file.png"} in results
    end

    test "returns :empty if no PII is found in any file" do
      file = %{
        name: "no-pii.pdf",
        mime_type: "application/pdf",
        data: "fake-pdf"
      }

      Req.Test.stub(FileUtils, fn conn ->
        Req.Test.json(conn, "stub-image")
      end)

      Req.Test.stub(OpenAI, fn conn ->
        content = ~s<{"items":[]}>
        json = %{"choices" => [%{"message" => %{"content" => content}}]}
        Req.Test.json(conn, json)
      end)

      assert :empty = OpenAI.detect_pii("neutral", [file])
    end

    @tag :capture_log
    test "returns :empty if file preparation fails" do
      file = %{
        name: "bad.unknown",
        # unsupported type to trigger failure
        mime_type: "application/zip",
        data: "invalid"
      }

      Req.Test.stub(OpenAI, &Req.Test.json(&1, %{"unused" => true}))

      assert :empty = OpenAI.detect_pii("...", [file])
    end
  end
end
