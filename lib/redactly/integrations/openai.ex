defmodule Redactly.Integrations.OpenAI do
  @moduledoc "Handles communication with OpenAI for PII analysis."

  alias Redactly.Integrations.FileUtils

  require Logger

  @base_url "https://api.openai.com/v1"

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

  ## Private

  defp detect_text_pii(text) do
    Logger.info("[OpenAI] Scanning text: #{text}")

    body = %{
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
    }

    Req.post(client(), url: "/chat/completions", json: body)
    |> handle_response("detect_text_pii")
  end

  defp detect_file_pii(%{name: name, mime_type: mime, data: data}) do
    Logger.info("[OpenAI] Scanning file: #{name} (#{mime})")

    case FileUtils.extract_images_from_file(mime, data) do
      {:ok, image_inputs} ->
        body = %{
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
        }

        Logger.debug("[OpenAI] Vision request body with #{length(image_inputs)} image(s)")

        Req.post(client(), url: "/chat/completions", json: body)
        |> handle_response("detect_file_pii")

      {:error, reason} ->
        Logger.warning("[OpenAI] Could not prepare image for #{name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_response(
         {:ok, %{body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}},
         label
       ) do
    case Jason.decode(content) do
      {:ok, %{"items" => items}} when is_list(items) ->
        {:ok, items}

      _ ->
        Logger.error("[OpenAI] Malformed assistant content in #{label}: #{inspect(content)}")
        {:error, :bad_format}
    end
  end

  defp handle_response({:ok, %{status: status, body: body}}, label) do
    Logger.error("[OpenAI] Unexpected response in #{label} (#{status}): #{inspect(body)}")
    {:error, :unexpected_response}
  end

  defp handle_response({:error, reason}, label) do
    Logger.error("[OpenAI] HTTP error in #{label}: #{inspect(reason)}")
    {:error, reason}
  end

  defp client do
    Req.new(
      base_url: @base_url,
      finch: Redactly.Finch,
      retry: :safe_transient,
      json: true,
      headers: [
        {"Authorization", "Bearer #{api_key()}"},
        {"Content-Type", "application/json"}
      ]
    )
    |> Req.merge(req_options())
  end

  defp req_options do
    Application.get_env(:redactly, :openai_req_options)
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
