defmodule Dala.ML.Example do
  @compile {:nowarn_undefined, [:Nx]}
  @moduledoc """
  Examples of using ML in a Dala app.

  Demonstrates basic ML operations using the auto-configured backend
  (EMLX on iOS, BinaryBackend elsewhere).
  """

  @doc """
  Simple tensor operations with auto-configured backend.
  """
  @spec basic_operations() :: map()
  def basic_operations do
    Dala.Ml.Nx.init()

    a = Nx.tensor([[1.0, 2.0], [3.0, 4.0]])
    b = Nx.tensor([[5.0], [6.0]])
    result = Nx.dot(a, b)

    %{
      input_a: Nx.to_flat_list(a),
      input_b: Nx.to_flat_list(b),
      result: Nx.to_flat_list(result),
      backend: inspect(Nx.default_backend())
    }
  end

  @doc """
  Image classification preprocessing pipeline.

  Takes an image tensor and applies standard ImageNet preprocessing.
  Returns a normalized batch tensor ready for model input.
  """
  @spec image_classify(Nx.Tensor.t()) :: {:ok, Nx.Tensor.t()} | {:error, term()}
  def image_classify(image_tensor) do
    preprocessed =
      image_tensor
      |> Nx.reshape({224, 224, 3})
      |> Nx.divide(255.0)
      |> Dala.ML.Preprocess.normalize(:imagenet)
      |> Dala.ML.Preprocess.to_batch()

    {:ok, preprocessed}
  end

  @doc """
  YOLO-like object detection preprocessing.

  Takes an image tensor and applies YOLO preprocessing.
  """
  @spec yolo_detect(Nx.Tensor.t()) :: {:ok, Nx.Tensor.t()} | {:error, term()}
  def yolo_detect(image_tensor) do
    preprocessed =
      image_tensor
      |> Nx.reshape({416, 416, 3})
      |> Nx.divide(255.0)
      |> Dala.ML.Preprocess.to_batch()

    {:ok, preprocessed}
  end

  @doc """
  Verifies the ML stack is working and returns status info.
  """
  @spec verify_setup() :: {:ok, map()} | {:error, term()}
  def verify_setup do
    result = Dala.ML.verify()
    status = Dala.ML.status()

    case result.status do
      :ok ->
        {:ok, %{verify: result, status: status}}

      :error ->
        {:error, result.message}
    end
  end

  @doc """
  Runs a full ML pipeline: preprocess → inspect → report.
  Useful for debugging model input/output shapes.
  """
  @spec debug_pipeline(Nx.Tensor.t(), atom()) :: map()
  def debug_pipeline(tensor, task \\ :image_classification) do
    preprocessed =
      case task do
        :image_classification -> image_classify(tensor) |> elem(1)
        :yolo_detection -> yolo_detect(tensor) |> elem(1)
      end

    %{
      input_info: Dala.ML.Debug.tensor_info(tensor),
      preprocessed_info: Dala.ML.Debug.tensor_info(preprocessed),
      backend: inspect(Nx.default_backend())
    }
  end
end
