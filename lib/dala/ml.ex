defmodule Dala.ML do
  @moduledoc """
  Unified ML API for Dala apps on iOS and Android.

  Single entry point for machine learning in Dala, integrating:

  - **Nx** - Core tensor library (pure Elixir, works everywhere)
  - **Scholar** - Traditional ML (regression, clustering, SVM, etc.)
  - **NxSignal** - Digital signal processing (audio, time series)
  - **Axon** - Neural networks (deep learning)
  - **EMLX** - Apple Silicon GPU acceleration (iOS only, auto-configured)
  - **CoreML** - iOS-native ML framework (Neural Engine, iOS only)
  - **ONNX Runtime** - Cross-platform inference engine (iOS/Android)
  - **GPU Compute (EXCubeCL)** - GPU compute via CubeCL (iOS/Android/desktop)
  - **ExBurn (Burn)** - Burn deep learning framework via Rust NIF (Metal/Vulkan/CUDA)

  ## Quick Start

      # Zero-config setup (call once at app startup)
      Dala.ML.setup()

      # Now use any of the integrated libraries
      tensor = Nx.tensor([1.0, 2.0, 3.0])
      Nx.sum(tensor)

  ## GPU Compute

  For heavy workloads (image processing, custom kernels, realtime effects),
  use the GPU compute backend via EXCubeCL:

      # Check GPU availability
      Dala.Gpu.Compute.device_info()

      # Create buffers and run kernels
      a = Dala.Gpu.Compute.buffer([1.0, 2.0, 3.0], {3}, :f32)
      b = Dala.Gpu.Compute.buffer([4.0, 5.0, 6.0], {3}, :f32)
      c = Dala.Gpu.Compute.buffer_zeros({3}, :f32)
      Dala.Gpu.Compute.add(a, b, c)
      Dala.Gpu.Compute.read(c)

  ## Platform Support

  | Library | iOS Device | iOS Sim | Android |
  |---------|-----------|--------|---------|
  | Nx | ✅ | ✅ | ✅ |
  | Scholar | ✅ | ✅ | ✅ |
  | NxSignal | ✅ | ✅ | ✅ |
  | Axon | ✅ | ✅ | ✅ |
  | EMLX (GPU) | ✅ | ✅ | ❌ |
  | CoreML | ✅ | ✅ | ❌ |
  | ONNX Runtime | ✅ | ✅ | ✅ |
  | GPU Compute (CubeCL) | ✅ | ✅ | ✅ |
  | ExBurn (Burn) | ✅ | ✅ | ✅ |
  """

  @doc """
  Sets up the ML stack for the current platform.

  Call once at app startup. Detects platform and configures the best
  available backend automatically.

  Returns `{:error, :nx_not_available}` if Nx is not a dependency of the app.
  """
  @spec setup() :: :ok | {:error, :nx_not_available}
  def setup do
    if nx_available?() do
      cond do
        ios?() ->
          if Dala.ML.EMLX.available?(), do: Dala.ML.EMLX.setup()
          # Also configure ExBurn if available (Metal GPU via Burn)
          if Dala.ML.Burn.available?() do
            Dala.ML.Burn.configure!(device: :gpu)
          end

          :ok

        android?() ->
          Nx.default_backend(Nx.BinaryBackend)
          # Configure ExBurn with Vulkan if available
          if Dala.ML.Burn.available?() do
            Dala.ML.Burn.configure!(device: :gpu)
          end

          :ok

        true ->
          Nx.default_backend(Nx.BinaryBackend)
          :ok
      end
    else
      {:error, :nx_not_available}
    end
  end

  @doc """
  Returns `true` if running on any iOS platform (device or simulator).
  """
  @spec ios?() :: boolean()
  def ios? do
    Dala.Platform.Native.platform() == :ios
  rescue
    _ -> false
  end

  @doc """
  Returns `true` if running on a real iOS device (not simulator).
  """
  @spec ios_device?() :: boolean()
  def ios_device? do
    Dala.ML.EMLX.ios_device?()
  end

  @doc """
  Returns `true` if running in iOS Simulator.
  """
  @spec ios_simulator?() :: boolean()
  def ios_simulator? do
    Dala.ML.EMLX.ios_simulator?()
  end

  @doc """
  Returns `true` if running on Android.
  """
  @spec android?() :: boolean()
  def android? do
    Dala.Platform.Native.platform() == :android
  rescue
    _ -> false
  end

  @doc """
  Returns `true` if Nx is loaded (i.e. the app depends on `:nx`).
  """
  @spec nx_available?() :: boolean()
  def nx_available?, do: Code.ensure_loaded?(Nx)

  @doc """
  Gets the current ML stack status.
  """
  @spec status() :: map()
  def status do
    platform =
      cond do
        ios_device?() -> :ios_device
        ios_simulator?() -> :ios_simulator
        android?() -> :android
        true -> :other
      end

    %{
      platform: platform,
      backend: Dala.Ml.Nx.default_backend(),
      emlx_available: Dala.ML.EMLX.available?(),
      coreml_available:
        ios?() and Code.ensure_loaded?(Dala.Native) and
          function_exported?(Dala.Native, :coreml_load_model, 2),
      onnx_available: Dala.ML.ONNX.available?(),
      gpu_compute_available: Code.ensure_loaded?(ExCubecl) and Dala.Gpu.Compute.available?(),
      gpu_compute_version:
        if(Code.ensure_loaded?(ExCubecl), do: Dala.Gpu.Compute.version(), else: nil),
      gpu_device:
        if(Code.ensure_loaded?(ExCubecl), do: Dala.Gpu.Compute.device_info(), else: nil),
      gpu_device_count:
        if(Code.ensure_loaded?(ExCubecl), do: Dala.Gpu.Compute.device_count(), else: 0),
      gpu_kernels: if(Code.ensure_loaded?(ExCubecl), do: Dala.Gpu.Compute.kernels(), else: []),
      burn_available: Dala.ML.Burn.available?(),
      burn_nif_loaded: Dala.ML.Burn.nif_loaded?(),
      burn_gpu: Dala.ML.Burn.gpu?(),
      burn_device: Dala.ML.Burn.default_device(),
      burn_device_name: Dala.ML.Burn.device_name(),
      burn_cuda: Dala.ML.Burn.cuda_available?(),
      burn_backends: Dala.ML.Burn.available_backends(),
      libraries: %{
        nx: Code.ensure_loaded?(Nx),
        scholar: Code.ensure_loaded?(Scholar),
        nx_signal: Code.ensure_loaded?(NxSignal),
        axon: Code.ensure_loaded?(Axon),
        emlx: Code.ensure_loaded?(EMLX),
        ex_burn: Dala.ML.Burn.available?()
      }
    }
  end

  @doc """
  Quick verification that the ML stack is working.
  """
  @spec verify() :: map()
  def verify do
    if nx_available?() do
      tensor = Nx.tensor([1.0, 2.0, 3.0])
      sum = Nx.sum(tensor) |> Nx.to_number()
      %{status: :ok, sum: sum, backend: Dala.Ml.Nx.default_backend()}
    else
      %{status: :error, message: "Nx not available — add {:nx, \"~> 0.12\"} to your deps"}
    end
  rescue
    e -> %{status: :error, message: Exception.message(e)}
  end

  @doc """
  Runs a smoke test of the ExBurn pipeline.

  Returns `:ok` if ExBurn is working, or `{:error, reason}` if not.
  """
  @spec burn_smoke_test() :: :ok | {:error, String.t()}
  def burn_smoke_test do
    Dala.ML.Burn.smoke_test()
  end

  @doc """
  Returns a formatted summary of the ExBurn environment.
  """
  @spec burn_summary() :: String.t()
  def burn_summary do
    Dala.ML.Burn.summary()
  end

  @doc """
  Enables the ExBurn defn compiler for GPU-accelerated Nx.Defn expressions.

  After calling this, all `defn` functions will be compiled through
  ExBurn's custom defn compiler and executed on the GPU via Burn.
  """
  @spec enable_burn_defn!() :: :ok
  def enable_burn_defn! do
    Dala.ML.Burn.enable_defn_compiler!()
  end

  @doc """
  Returns a list of available ML backends for the current platform.
  """
  @spec available_backends() :: [atom()]
  def available_backends do
    backends = [:nx]

    backends =
      if Dala.ML.EMLX.available?() do
        [:emlx | backends]
      else
        backends
      end

    backends =
      if ios?() and Code.ensure_loaded?(Dala.Native) and
           function_exported?(Dala.Native, :coreml_load_model, 2) do
        [:coreml | backends]
      else
        backends
      end

    backends =
      if Dala.ML.ONNX.available?() do
        [:onnx | backends]
      else
        backends
      end

    backends =
      if Code.ensure_loaded?(ExCubecl) do
        [:gpu_compute | backends]
      else
        backends
      end

    backends =
      if Dala.ML.Burn.available?() do
        [:burn | backends]
      else
        backends
      end

    Enum.reverse(backends)
  end

  @doc """
  Benchmarks a simple ML operation on the current backend.

  Returns `%{time_ms: float, backend: term, gflops: float}`.
  """
  @spec benchmark(keyword()) :: map()
  def benchmark(opts \\ []) do
    if nx_available?() do
      size = Keyword.get(opts, :size, 100)
      iterations = Keyword.get(opts, :iterations, 10)

      setup()

      {a, b} = bench_matrices(size)

      # Warmup
      Nx.dot(a, b) |> Nx.to_binary()

      {total_us, _} =
        :timer.tc(fn ->
          for _ <- 1..iterations do
            Nx.dot(a, b) |> Nx.to_binary()
          end
        end)

      avg_ms = total_us / iterations / 1000
      ops = 2 * size * size * size
      gflops = ops / (avg_ms / 1000) / 1.0e9

      result = %{
        time_ms: Float.round(avg_ms, 3),
        backend: Nx.default_backend(),
        gflops: Float.round(gflops, 3),
        matrix_size: size,
        iterations: iterations
      }

      # Include Burn benchmark if available and NIF is functional.
      # ExBurn's Nx fallback can loop indefinitely on incompatible Nx versions,
      # so isolate it — a broken burn backend must not hang the whole benchmark.
      if Dala.ML.Burn.available?() and Dala.ML.Burn.nif_loaded?() do
        case safe_burn_benchmark(size, iterations) do
          {:ok, burn_result} -> Map.put(result, :burn, burn_result)
          :error -> result
        end
      else
        result
      end
    else
      %{error: :nx_not_available}
    end
  end

  @burn_benchmark_timeout_ms 10_000

  defp safe_burn_benchmark(size, iterations) do
    parent = self()
    ref = make_ref()

    pid =
      spawn(fn ->
        try do
          send(parent, {ref, {:ok, benchmark_backend(ExBurn.Backend, size, iterations)}})
        rescue
          _ -> send(parent, {ref, :error})
        end
      end)

    receive do
      {^ref, {:ok, burn_result}} -> {:ok, burn_result}
      {^ref, :error} -> :error
    after
      @burn_benchmark_timeout_ms ->
        Process.exit(pid, :kill)
        :error
    end
  end

  defp benchmark_backend(backend, size, iterations) do
    Nx.default_backend(backend)

    {a, b} = bench_matrices(size)

    # Warmup
    Nx.dot(a, b) |> Nx.to_binary()

    {total_us, _} =
      :timer.tc(fn ->
        for _ <- 1..iterations do
          Nx.dot(a, b) |> Nx.to_binary()
        end
      end)

    avg_ms = total_us / iterations / 1000
    ops = 2 * size * size * size
    gflops = ops / (avg_ms / 1000) / 1.0e9

    %{
      time_ms: Float.round(avg_ms, 3),
      gflops: Float.round(gflops, 3)
    }
  after
    # Restore default backend
    Nx.default_backend(Nx.BinaryBackend)
  end

  # Nx.Random's threefry PRNG breaks under nx >= 0.13 on some backends, and
  # benchmarking doesn't need randomness — use deterministic values.
  defp bench_matrices(size) do
    a = Nx.iota({size, size}, type: :f32) |> Nx.divide(size)
    b = Nx.iota({size, size}, type: :f32) |> Nx.subtract(1.0)
    {a, b}
  end

  @doc """
  Runs inference using the best available backend.

  Dispatches based on model type:
  - Binary (string) on iOS → CoreML
  - Integer → ONNX session
  - Tuple → Axon model
  """
  @spec predict(term(), term()) :: {:ok, term()} | {:error, term()}
  def predict(model, input) do
    cond do
      is_binary(model) and ios?() ->
        Dala.ML.CoreML.predict(model, input)

      is_integer(model) ->
        Dala.ML.ONNX.run(model, input)

      is_tuple(model) ->
        Dala.Ml.Nx.inference(elem(model, 0), elem(model, 1), input)

      is_struct(model, ExBurn.Model) ->
        Dala.ML.Burn.predict(model, input)

      true ->
        {:error, "Unsupported model type: #{inspect(model)}"}
    end
  rescue
    e in UndefinedFunctionError -> {:error, "Dependency not available: #{inspect(e.module)}"}
  end
end
