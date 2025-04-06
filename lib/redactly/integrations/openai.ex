defmodule Redactly.Integrations.OpenAI do
  @moduledoc "Handles communication with OpenAI for PII analysis."

  require Logger

  @openai_url "https://api.openai.com/v1/chat/completions"

  @type pii_item :: %{optional(String.t()) => String.t()}
  @type file :: %{name: String.t(), mime_type: String.t(), data: binary()}

  @spec detect_pii(String.t(), list(file)) :: {:ok, list(pii_item)} | :empty
  def detect_pii(text, files) do
    text_result = detect_text_pii(text)
    file_results = Enum.map(files, &detect_file_pii/1)

    all_items =
      Enum.flat_map(
        [{:text, text_result} | Enum.zip(Enum.map(files, & &1.name), file_results)],
        fn
          {:text, {:ok, items}} ->
            Enum.map(items, &Map.put(&1, "source", "Message text"))

          {filename, {:ok, items}} ->
            Enum.map(items, &Map.put(&1, "source", filename))

          _ ->
            []
        end
      )

    if all_items == [] do
      :empty
    else
      {:ok, all_items}
    end
  end

  defp detect_text_pii(text) do
    Logger.info("[OpenAI] Scanning text: #{text}")

    body =
      Jason.encode!(%{
        model: "gpt-4o",
        messages: [
          %{
            role: "system",
            content: text_prompt()
          },
          %{
            role: "user",
            content: text
          }
        ],
        response_format: %{
          type: "json_schema",
          json_schema: %{
            strict: true,
            name: "pii",
            schema: response_schema()
          }
        }
      })

    Logger.debug("[OpenAI] Request body: #{body}")

    Finch.build(:post, @openai_url, headers(), body)
    |> Finch.request(Redactly.Finch)
    |> handle_response()
  end

  defp detect_file_pii(%{name: name, mime_type: mime, data: data}) do
    Logger.info("[OpenAI] Scanning file: #{name} (#{mime})")

    case extract_images_from_file(mime, data) do
      {:ok, image_inputs} ->
        body =
          Jason.encode!(%{
            model: "gpt-4o",
            messages: [
              %{
                role: "system",
                content: image_prompt()
              },
              %{
                role: "user",
                content: image_inputs
              }
            ],
            response_format: %{
              type: "json_schema",
              json_schema: %{
                strict: true,
                name: "pii",
                schema: response_schema()
              }
            }
          })

        Logger.debug("[OpenAI] Vision request body with #{length(image_inputs)} image(s)")

        Finch.build(:post, @openai_url, headers(), body)
        |> Finch.request(Redactly.Finch)
        |> handle_response()

      {:error, reason} ->
        Logger.warning("[OpenAI] Could not prepare image for #{name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_images_from_file("application/pdf", data) do
    with {:ok, base_path} <- write_temp_file(data, ".pdf"),
         output_prefix <- Path.rootname(base_path),
         {_, 0} <- System.cmd("pdftoppm", ["-png", base_path, output_prefix]),
         images <- Path.wildcard("#{output_prefix}-*.png"),
         true <- images != [] do
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

  defp extract_images_from_file(mime, data)
       when mime in ["image/png", "image/jpeg"] do
    url = base64_image_url(data)

    {:ok, [%{"type" => "image_url", "image_url" => %{"url" => url}}]}
  end

  defp extract_images_from_file(mime, _), do: {:error, "Unsupported file type: #{mime}"}

  defp base64_image_url(data) do
    encoded = Base.encode64(data)
    "data:image/png;base64,#{encoded}"
  end

  defp write_temp_file(data, ext) do
    tmp_path = Path.join(System.tmp_dir!(), "redactly-#{System.unique_integer()}" <> ext)

    case File.write(tmp_path, data) do
      :ok -> {:ok, tmp_path}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_response({:ok, %Finch.Response{status: 200, body: body}}) do
    case Jason.decode!(body) do
      %{"choices" => [%{"message" => %{"content" => content}} | _]} ->
        case Jason.decode(content) do
          {:ok, %{"items" => items}} when is_list(items) ->
            {:ok, items}

          _ ->
            Logger.error("[OpenAI] Unexpected assistant content: #{inspect(content)}")
            {:error, :bad_format}
        end

      _ ->
        Logger.error("[OpenAI] Unexpected response: #{body}")
        {:error, :unexpected_response}
    end
  end

  defp handle_response({:ok, %Finch.Response{status: status, body: body}}) do
    Logger.error("[OpenAI] Failed with status #{status}: #{body}")
    {:error, :http_error}
  end

  defp handle_response({:error, reason}) do
    Logger.error("[OpenAI] Request error: #{inspect(reason)}")
    {:error, reason}
  end

  defp headers do
    [
      {"Authorization", "Bearer #{api_key()}"},
      {"Content-Type", "application/json"}
    ]
  end

  defp api_key do
    Application.fetch_env!(:redactly, :openai)[:api_key]
  end

  defp text_prompt do
    """
    You are a strict data loss prevention (DLP) agent. Analyze the input and return a list of any PII (personally identifiable information) you find.

    Only return values that match the provided JSON schema. Do not explain.
    """
  end

  defp image_prompt do
    """
    You are a document privacy scanner. Analyze the images and extract any visible PII such as names, emails, addresses, ID numbers, etc.

    Only return values that match the provided JSON schema. Do not explain.
    """
  end

  defp response_schema do
    %{
      type: "object",
      properties: %{
        items: %{
          type: "array",
          items: %{
            type: "object",
            properties: %{
              type: %{type: "string"},
              value: %{type: "string"}
            },
            required: ["type", "value"],
            additionalProperties: false
          }
        }
      },
      required: ["items"],
      additionalProperties: false
    }
  end
end
