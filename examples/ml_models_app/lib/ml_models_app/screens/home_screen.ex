defmodule MlModelsApp.HomeScreen do
  @moduledoc """
  Home screen showing model status, download controls, and navigation.
  """
  use Dala.Spark.Dsl

  attributes do
    attribute(:downloading, :atom, default: nil)
    attribute(:download_status, :map, default: %{})
    attribute(:ml_status, :map, default: %{})
    attribute(:error, :string, default: nil)
  end

  screen name: :home do
    column padding: 16, gap: 12 do
      text("ML Models Demo", text_size: :xl, font_weight: "bold")
      text("ONNX Runtime Inference", text_size: :sm)

      divider()

      text("Models", text_size: :lg, font_weight: "bold")

      row gap: :space_sm, alignment: :center do
        text("Sentiment Analysis (DistilBERT)", fill_width: true)
        text("Cached", text_size: :sm)
      end

      if compute(fn assigns -> assigns[:downloading] == nil end) do
        button("Download Sentiment Model", on_tap: :download_sentiment, fill_width: true)
      end

      row gap: :space_sm, alignment: :center do
        text("Object Detection (YOLOS-tiny)", fill_width: true)
        text("Cached", text_size: :sm)
      end

      if compute(fn assigns -> assigns[:downloading] == nil end) do
        button("Download Detection Model", on_tap: :download_detection, fill_width: true)
      end

      if compute(fn assigns -> assigns[:downloading] != nil end) do
        row gap: :space_sm do
          activity_indicator()

          text(
            text:
              compute(fn assigns ->
                name =
                  case assigns[:downloading] do
                    :sentiment -> "Sentiment Analysis"
                    :detection -> "Object Detection"
                    _ -> "Unknown"
                  end

                "Downloading #{name}..."
              end)
          )
        end
      end

      if compute(fn assigns -> assigns[:error] != nil end) do
        text(text: compute(fn assigns -> "Error: #{assigns[:error]}" end), text_color: "#ff0000")
      end

      divider()

      text("Screens", text_size: :lg, font_weight: "bold")
      button("Sentiment Analysis →", on_tap: :go_sentiment, fill_width: true)
      button("Object Detection →", on_tap: :go_detection, fill_width: true)

      divider()

      text("Backend Info", text_size: :lg, font_weight: "bold")

      text(
        text:
          compute(fn assigns ->
            platform = (assigns[:ml_status] || %{})[:platform]
            "Platform: #{platform || "unknown"}"
          end),
        text_size: :sm
      )

      text(
        text:
          compute(fn assigns ->
            "Backend: #{inspect((assigns[:ml_status] || %{})[:backend])}"
          end),
        text_size: :sm
      )

      text(
        text:
          compute(fn assigns ->
            "ONNX available: #{(assigns[:ml_status] || %{})[:onnx_available] || false}"
          end),
        text_size: :sm
      )
    end
  end

  def mount(_params, _session, socket) do
    socket =
      socket
      |> Dala.Socket.assign(:ml_status, Dala.ML.status())
      |> Dala.Socket.assign(:download_status, %{
        sentiment: MlModelsApp.OnnxRuntime.cached?(:sentiment),
        detection: MlModelsApp.OnnxRuntime.cached?(:detection)
      })

    {:ok, socket}
  end

  def handle_event(:download_sentiment, _params, socket) do
    socket =
      socket
      |> Dala.Socket.assign(:downloading, :sentiment)
      |> Dala.Socket.assign(:error, nil)

    me = self()

    Task.start(fn ->
      result = MlModelsApp.OnnxRuntime.download(:sentiment)
      send(me, {:download_complete, :sentiment, result})
    end)

    {:noreply, socket}
  end

  def handle_event(:download_detection, _params, socket) do
    socket =
      socket
      |> Dala.Socket.assign(:downloading, :detection)
      |> Dala.Socket.assign(:error, nil)

    me = self()

    Task.start(fn ->
      result = MlModelsApp.OnnxRuntime.download(:detection)
      send(me, {:download_complete, :detection, result})
    end)

    {:noreply, socket}
  end

  def handle_event(:go_sentiment, _params, socket) do
    {:noreply, Dala.Socket.push_screen(socket, MlModelsApp.SentimentScreen)}
  end

  def handle_event(:go_detection, _params, socket) do
    {:noreply, Dala.Socket.push_screen(socket, MlModelsApp.DetectionScreen)}
  end

  def handle_info({:download_complete, model_key, result}, socket) do
    is_cached = match?({:ok, _}, result)

    socket =
      socket
      |> Dala.Socket.assign(:downloading, nil)
      |> Dala.Socket.assign(
        :download_status,
        Map.put(socket.assigns.download_status, model_key, is_cached)
      )
      |> Dala.Socket.assign(
        :error,
        case result do
          {:ok, _} -> nil
          {:error, reason} -> reason
        end
      )

    {:noreply, socket}
  end
end
