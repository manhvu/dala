defmodule MlModelsApp.DetectionScreen do
  @moduledoc """
  Object detection screen using YOLOS-tiny ONNX model.
  """
  use Dala.Spark.Dsl

  attributes do
    attribute(:detections, :list, default: [])
    attribute(:loading, :boolean, default: false)
    attribute(:model_loaded, :boolean, default: false)
    attribute(:model_ref, :integer, default: nil)
    attribute(:error, :string, default: nil)
    attribute(:has_result, :boolean, default: false)
  end

  screen name: :detection do
    column padding: 16, gap: 12 do
      row gap: :space_sm, alignment: :center do
        button("← Back", on_tap: :go_back)
        text("Object Detection", text_size: :xl, font_weight: "bold", fill_width: true)
      end

      text("YOLOS-tiny model", text_size: :sm)

      if @model_loaded do
        text("Model loaded ✓", text_size: :sm)
      end

      unless @model_loaded do
        text("Model not loaded", text_size: :sm)
      end

      divider()

      if @loading do
        row gap: :space_sm do
          activity_indicator()
          text("Detecting objects...")
        end
      end

      if compute(fn assigns -> not assigns[:loading] and assigns[:model_loaded] end) do
        button("Detect Objects (Demo)", on_tap: :detect, fill_width: true)
      end

      if compute(fn assigns -> not assigns[:loading] and not assigns[:model_loaded] end) do
        text("Download the detection model from the home screen first.")
      end

      if @has_result do
        divider()
        text("Detections", text_size: :lg, font_weight: "bold")

        if compute(fn assigns -> assigns[:detections] == [] end) do
          text("No objects detected.")
        end

        list(:detection_list, data: @detections)
      end

      if compute(fn assigns -> assigns[:error] != nil end) do
        text(text: compute(fn assigns -> "Error: #{assigns[:error]}" end), text_color: "#ff0000")
      end

      divider()
      text("About", text_size: :lg, font_weight: "bold")

      text(
        "YOLOS-tiny is a lightweight object detection model that can identify 80+ COCO object classes.",
        text_size: :sm
      )

      text("Model: Xenova/yolos-tiny (~81MB)", text_size: :sm)
    end
  end

  def mount(_params, _session, socket) do
    socket =
      case MlModelsApp.OnnxRuntime.load_model(:detection) do
        {:ok, ref} ->
          Dala.Platform.Native.log("DetectionScreen: model loaded")

          Dala.Socket.assign(socket, :model_loaded, true)
          |> Dala.Socket.assign(:model_ref, ref)

        {:error, _reason} ->
          Dala.Socket.assign(socket, :model_loaded, false)
      end

    {:ok, socket}
  end

  def handle_event(:go_back, _params, socket) do
    {:noreply, Dala.Socket.pop_screen(socket)}
  end

  def handle_event(:detect, _params, socket) do
    socket =
      socket
      |> Dala.Socket.assign(:loading, true)
      |> Dala.Socket.assign(:error, nil)

    me = self()
    model_ref = socket.assigns.model_ref
    image_path = Path.join(:code.priv_dir(:ml_models_app), "models/sample.jpg")

    Task.start(fn ->
      result = MlModelsApp.OnnxRuntime.predict_detection(model_ref, image_path)
      send(me, {:detection_result, result})
    end)

    {:noreply, socket}
  end

  def handle_info({:detection_result, {:ok, detections}}, socket) do
    socket =
      socket
      |> Dala.Socket.assign(:detections, detections)
      |> Dala.Socket.assign(:has_result, true)
      |> Dala.Socket.assign(:loading, false)

    {:noreply, socket}
  end

  def handle_info({:detection_result, {:error, reason}}, socket) do
    socket =
      socket
      |> Dala.Socket.assign(:loading, false)
      |> Dala.Socket.assign(:error, reason)

    {:noreply, socket}
  end
end
