defmodule MlModelsApp.SentimentScreen do
  @moduledoc """
  Sentiment analysis screen using DistilBERT SST-2 ONNX model.
  """
  use Dala.Spark.Dsl

  attributes do
    attribute(:input_text, :string, default: "")
    attribute(:result, :map, default: nil)
    attribute(:loading, :boolean, default: false)
    attribute(:history, :list, default: [])
    attribute(:model_loaded, :boolean, default: false)
    attribute(:model_ref, :integer, default: nil)
    attribute(:error, :string, default: nil)
  end

  screen name: :sentiment do
    column padding: 16, gap: 12 do
      row gap: :space_sm, alignment: :center do
        button("← Back", on_tap: :go_back)
        text("Sentiment Analysis", text_size: :xl, font_weight: "bold", fill_width: true)
      end

      text("Enter text to analyze:", text_size: :sm)

      text_field(text: @input_text, placeholder: "Type something...", on_change: :text_changed)

      if @loading do
        row gap: :space_sm do
          activity_indicator()
          text("Analyzing...")
        end
      end

      unless @loading do
        button("Analyze Sentiment", on_tap: :analyze, fill_width: true)
      end

      if compute(fn assigns -> assigns[:result] != nil end) do
        divider()
        text("Result", text_size: :lg, font_weight: "bold")

        row gap: :space_sm, alignment: :center do
          text(
            text:
              compute(fn assigns ->
                (assigns[:result] || %{})[:label] || ""
              end),
            text_size: :xl,
            font_weight: "bold",
            text_color:
              compute(fn assigns ->
                case (assigns[:result] || %{})[:label] do
                  "POSITIVE" -> :success
                  "NEGATIVE" -> :error
                  _ -> :default
                end
              end)
          )

          text(
            text:
              compute(fn assigns ->
                confidence = (assigns[:result] || %{})[:confidence] || 0.0
                "#{Float.round(confidence * 100, 1)}%"
              end),
            text_size: :lg
          )
        end

        progress_bar(
          progress: compute(fn assigns -> (assigns[:result] || %{})[:confidence] || 0.0 end)
        )
      end

      if compute(fn assigns -> assigns[:error] != nil end) do
        text(text: compute(fn assigns -> "Error: #{assigns[:error]}" end), text_color: "#ff0000")
      end

      divider()
      text("Try an example:", text_size: :sm)

      button("I love this product, it's amazing!",
        on_tap: {:use_example, "I love this product, it's amazing!"},
        fill_width: true
      )

      button("This is the worst experience ever.",
        on_tap: {:use_example, "This is the worst experience ever."},
        fill_width: true
      )

      if compute(fn assigns -> assigns[:history] != [] end) do
        divider()
        text("History", text_size: :lg, font_weight: "bold")
        list(:history_list, data: @history)
      end
    end
  end

  def mount(_params, _session, socket) do
    socket =
      case MlModelsApp.OnnxRuntime.load_model(:sentiment) do
        {:ok, ref} ->
          Dala.Platform.Native.log("SentimentScreen: model loaded")

          Dala.Socket.assign(socket, :model_loaded, true)
          |> Dala.Socket.assign(:model_ref, ref)

        {:error, reason} ->
          Dala.Platform.Native.log("SentimentScreen: model not loaded: #{reason}")

          Dala.Socket.assign(
            socket,
            :error,
            "Model not loaded. Download it from the home screen."
          )
      end

    {:ok, socket}
  end

  def handle_event(:go_back, _params, socket) do
    {:noreply, Dala.Socket.pop_screen(socket)}
  end

  def handle_event(:text_changed, %{"value" => text}, socket) do
    {:noreply, Dala.Socket.assign(socket, :input_text, text)}
  end

  def handle_event(:analyze, _params, socket) do
    text = socket.assigns.input_text

    if text == "" or text == nil do
      {:noreply, Dala.Socket.assign(socket, :error, "Please enter some text to analyze.")}
    else
      socket =
        socket
        |> Dala.Socket.assign(:loading, true)
        |> Dala.Socket.assign(:error, nil)

      me = self()
      model_ref = socket.assigns.model_ref

      Task.start(fn ->
        result = MlModelsApp.OnnxRuntime.predict_sentiment(model_ref, text)
        send(me, {:sentiment_result, result})
      end)

      {:noreply, socket}
    end
  end

  def handle_event({:use_example, example}, _params, socket) do
    socket = Dala.Socket.assign(socket, :input_text, example)
    {:noreply, socket}
  end

  def handle_info({:sentiment_result, {:ok, result}}, socket) do
    history = [
      %{text: socket.assigns.input_text, label: result.label, confidence: result.confidence}
      | socket.assigns.history
    ]

    socket =
      socket
      |> Dala.Socket.assign(:result, result)
      |> Dala.Socket.assign(:history, history)
      |> Dala.Socket.assign(:loading, false)
      |> Dala.Socket.assign(:error, nil)

    {:noreply, socket}
  end

  def handle_info({:sentiment_result, {:error, reason}}, socket) do
    socket =
      socket
      |> Dala.Socket.assign(:loading, false)
      |> Dala.Socket.assign(:error, reason)

    {:noreply, socket}
  end
end
