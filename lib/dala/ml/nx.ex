defmodule Dala.Ml.Nx do
  @compile {:nowarn_undefined, [:Nx]}
  @moduledoc """
  Nx integration helpers for Dala.

  Nx itself is pure Elixir and works on any platform. This module provides
  backend selection logic and inference helpers.
  """

  @doc """
  Initializes Nx with the best available backend for the current platform.

  Priority:
  1. EMLX (if available) - best for Apple Silicon
  2. Nx.BinaryBackend (pure Elixir fallback)
  """
  @spec init() :: :emlx | :nx_binary | {:error, :nx_not_available}
  def init do
    cond do
      not Code.ensure_loaded?(Nx) ->
        {:error, :nx_not_available}

      emlx_available?() ->
        Dala.ML.EMLX.setup()
        :emlx

      true ->
        Nx.default_backend(Nx.BinaryBackend)
        :nx_binary
    end
  end

  @doc """
  Checks if EMLX is available.
  """
  @spec emlx_available?() :: boolean()
  def emlx_available? do
    Code.ensure_loaded?(EMLX) and Code.ensure_loaded?(EMLX.Backend)
  rescue
    _ -> false
  end

  @doc """
  Creates a tensor with the platform-appropriate backend.
  """
  @spec tensor(term(), keyword()) :: Nx.Tensor.t()
  def tensor(data, opts \\ []) do
    backend = Keyword.get(opts, :backend, default_backend())
    Nx.tensor(data, Keyword.put(opts, :backend, backend))
  end

  @doc """
  Returns the default backend for the current platform.
  """
  @spec default_backend() :: module() | tuple()
  def default_backend do
    if emlx_available?() do
      {EMLX.Backend, device: Dala.ML.EMLX.default_device()}
    else
      Nx.BinaryBackend
    end
  end

  @doc """
  Runs inference with an Axon model using the best available backend.
  """
  @spec inference(term(), term(), term()) :: {:ok, term()} | {:error, term()}
  def inference(model, params, input_data) do
    backend = default_backend()
    input_tensor = Nx.tensor(input_data, backend: backend)

    try do
      output = Axon.predict(model, params, input_tensor)
      {:ok, output}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @doc """
  Checks if Axon is available.
  """
  @spec axon_available?() :: boolean()
  def axon_available? do
    Code.ensure_loaded?(Axon)
  rescue
    _ -> false
  end
end
