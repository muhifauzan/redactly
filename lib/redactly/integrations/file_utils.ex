defmodule Redactly.Integrations.FileUtils do
  @moduledoc "Utility helpers for working with file formats and conversions."

  require Logger

  @spec extract_images_from_file(String.t(), binary()) ::
          {:ok, list(map())} | {:error, any()}
  def extract_images_from_file("application/pdf", data) do
    with {:ok, base_path} <- write_temp_file(data, ".pdf"),
         output_prefix <- Path.rootname(base_path),
         {_, 0} <- System.cmd("pdftoppm", ["-png", base_path, output_prefix]),
         images <- Path.wildcard("#{output_prefix}-*.png"),
         true <- images != [] do
      Logger.debug("[FileUtils] Extracted #{length(images)} image(s) from PDF")

      urls =
        images
        |> Enum.map(&File.read!/1)
        |> Enum.map(&base64_image_url/1)
        |> Enum.map(&%{"type" => "image_url", "image_url" => %{"url" => &1}})

      Enum.each(images, &File.rm/1)
      File.rm(base_path)

      {:ok, urls}
    else
      false -> {:error, "No images generated"}
      err -> {:error, err}
    end
  end

  def extract_images_from_file(mime, data)
      when mime in ["image/png", "image/jpeg"] do
    url = base64_image_url(data)

    {:ok, [%{"type" => "image_url", "image_url" => %{"url" => url}}]}
  end

  def extract_images_from_file(mime, _), do: {:error, "Unsupported file type: #{mime}"}

  @spec write_temp_file(binary(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def write_temp_file(data, ext) do
    tmp_path = Path.join(System.tmp_dir!(), "redactly-#{System.unique_integer()}" <> ext)

    case File.write(tmp_path, data) do
      :ok -> {:ok, tmp_path}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec base64_image_url(binary()) :: String.t()
  def base64_image_url(data) do
    encoded = Base.encode64(data)
    "data:image/png;base64,#{encoded}"
  end

  @spec download(String.t(), list()) :: {:ok, binary()} | :error
  def download(url, headers \\ []) do
    Req.get(req(), url: url, headers: headers)
    |> case do
      {:ok, %{status: 200, body: body}} ->
        Logger.debug("[FileUtils] Downloaded content from #{String.slice(url, 0, 80)}...")
        {:ok, body}

      {:ok, %{status: status}} ->
        Logger.warning("[FileUtils] Download failed with status #{status}")
        :error

      {:error, reason} ->
        Logger.error("[FileUtils] Download error: #{inspect(reason)}")
        :error
    end
  end

  @spec guess_mime_type(String.t()) :: String.t()
  def guess_mime_type(url) do
    url
    |> String.split("?")
    |> hd()
    |> Path.extname()
    |> String.downcase()
    |> case do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".pdf" -> "application/pdf"
      _ -> "application/octet-stream"
    end
  end

  defp req do
    Req.new(finch: Redactly.Finch)
    |> Req.merge(req_options())
  end

  defp req_options do
    Application.get_env(:redactly, :fileutils_req_options)
  end
end
