defmodule Redactly.Integrations.FileUtilsTest do
  use ExUnit.Case, async: true

  alias Redactly.Integrations.FileUtils

  describe "extract_images_from_file/2" do
    test "converts image/png into base64 data URL" do
      # fake JPEG data
      data = <<255, 216, 255>>
      {:ok, result} = FileUtils.extract_images_from_file("image/png", data)

      assert [%{"type" => "image_url", "image_url" => %{"url" => url}}] = result
      assert String.starts_with?(url, "data:image/png;base64,")
    end

    test "converts image/jpeg into base64 data URL" do
      # fake PNG data
      data = <<137, 80, 78, 71>>
      {:ok, result} = FileUtils.extract_images_from_file("image/jpeg", data)

      assert [%{"type" => "image_url", "image_url" => %{"url" => url}}] = result
      assert String.starts_with?(url, "data:image/png;base64,")
    end

    test "returns error for unsupported file type" do
      assert {:error, _} = FileUtils.extract_images_from_file("application/zip", <<0>>)
    end
  end

  describe "download/1" do
    test "returns {:ok, body} for 200 response" do
      Req.Test.stub(FileUtils, &Plug.Conn.resp(&1, 200, "file-content"))

      assert {:ok, "file-content"} = FileUtils.download("https://some-url.com/file")
    end

    @tag :capture_log
    test "returns :error for non-200 response" do
      Req.Test.stub(FileUtils, &Plug.Conn.resp(&1, 404, "not found"))

      assert :error = FileUtils.download("https://some-url.com/missing")
    end

    @tag :capture_log
    test "returns :error for transport error" do
      Req.Test.stub(FileUtils, &Req.Test.transport_error(&1, :econnrefused))

      assert :error = FileUtils.download("https://fail.me")
    end
  end

  describe "guess_mime_type/1" do
    test "detects supported file types" do
      assert FileUtils.guess_mime_type("file.jpg") == "image/jpeg"
      assert FileUtils.guess_mime_type("file.jpeg") == "image/jpeg"
      assert FileUtils.guess_mime_type("file.png") == "image/png"
      assert FileUtils.guess_mime_type("file.pdf") == "application/pdf"
    end

    test "defaults to octet-stream for unknown type" do
      assert FileUtils.guess_mime_type("file.unknown") == "application/octet-stream"
    end
  end
end
