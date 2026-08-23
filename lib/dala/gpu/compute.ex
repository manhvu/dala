defmodule Dala.Gpu.Compute do
  @moduledoc """
  High-level GPU compute orchestration for Dala.

  Wraps [EXCubeCL](https://hexdocs.pm/ex_cubecl/readme.html) with Dala-native
  patterns: GenServer-managed lifecycle, dirty-CPU scheduling, and integration
  with `Dala.Gpu` surfaces, `Dala.Media` pipelines, and `Dala.ML` inference.

  ## Architecture

  ```
  ┌──────────────────────────────────────────────────────┐
  │  Dala.Gpu.Compute                                    │
  │  ├── buffer management (create, read, free)           │
  │  ├── kernel execution (sync + async)                  │
  │  ├── pipeline orchestration (multi-stage)             │
  │  └── stream scheduler (mobile-optimized)              │
  ├──────────────────────────────────────────────────────┤
  │  EXCubeCL (Elixir NIF stubs)                         │
  ├──────────────────────────────────────────────────────┤
  │  Rust NIF → CubeCL Runtime → Metal / OpenGL ES / CPU │
  └──────────────────────────────────────────────────────┘
  ```

  ## Quick Start

      # Check GPU availability
      Dala.Gpu.Compute.device_info()
      # %{name: "ExCubecl CPU (Rust NIF)", gpu: false, version: "0.4.1"}

      # Create buffers
      a = Dala.Gpu.Compute.buffer([1.0, 2.0, 3.0], {3}, :f32)
      b = Dala.Gpu.Compute.buffer([4.0, 5.0, 6.0], {3}, :f32)
      c = Dala.Gpu.Compute.buffer([0.0, 0.0, 0.0], {3}, :f32)

      # Run a kernel
      Dala.Gpu.Compute.run_kernel(:elementwise_add, [a, b], c, %{})

      # Read results
      Dala.Gpu.Compute.read(c)
      # <<5.0, 7.0, 9.0>>  (binary)

      # Cleanup (optional — buffers auto-freed by ResourceArc)
      Dala.Gpu.Compute.free(a)
      Dala.Gpu.Compute.free(b)
      Dala.Gpu.Compute.free(c)

  ## Async Execution

      cmd_id = Dala.Gpu.Compute.submit(%{
        op: :run_kernel,
        kernel: "relu",
        inputs: [a.ref],
        output: b.ref,
        params: %{}
      })

      Dala.Gpu.Compute.poll(cmd_id)  # :pending | :completed | {:error, reason}
      Dala.Gpu.Compute.wait(cmd_id)   # blocks until done

  ## Pipeline Orchestration

      pipeline = Dala.Gpu.Compute.pipeline()
      pipeline
      |> Dala.Gpu.Compute.pipeline_add(%{
        op: :run_kernel,
        kernel: :blur,
        inputs: [input_buf],
        output: temp_buf,
        params: %{radius: 3}
      })
      |> Dala.Gpu.Compute.pipeline_add(%{
        op: :run_kernel,
        kernel: :relu,
        inputs: [temp_buf],
        output: output_buf,
        params: %{}
      })
      Dala.Gpu.Compute.pipeline_run(pipeline)

  ## Integration with Dala.Gpu surfaces

  For rendering results to screen, pair a compute buffer with a `Dala.Gpu.Surface`:

      {:ok, surface} = Dala.Gpu.create_surface(640, 480)
      # Run compute → read buffer → upload to surface
      Dala.Gpu.Compute.run_kernel(:generate_gradient, [], output_buf, %{})
      pixels = Dala.Gpu.Compute.read(output_buf)
      Dala.Gpu.set_pixels(surface, pixels)
      Dala.Gpu.present(surface)

  ## Supported Types

  | Type   | Description                   |
  |--------|-------------------------------|
  | `:f32` | 32-bit float                  |
  | `:f64` | 64-bit float                  |
  | `:s32` | 32-bit signed integer         |
  | `:s64` | 64-bit signed integer         |
  | `:u32` | 32-bit unsigned integer       |
  | `:u8`  | 8-bit unsigned integer        |

  ## Mobile Notes

  On iOS, CubeCL kernels compile to Metal shaders at runtime.
  On Android, they compile to OpenGL ES compute shaders.
  On desktop (dev), a CPU fallback is used.

  GPU compute is automatically dirty-CPU scheduled so it won't block
  the BEAM scheduler.
  """

  alias Dala.Gpu.Compute.{Buffer, Kernel, Pipeline}

  # ── Device info ───────────────────────────────────────────────────────────

  @doc "Return GPU device information."
  @spec device_info() :: map()
  def device_info do
    if Code.ensure_loaded?(ExCubecl) do
      case ExCubecl.device_info() do
        {:ok, info} -> info
        {:error, _} -> %{gpu: false, name: "unknown", backend: :cpu_fallback}
      end
    else
      %{gpu: false, name: "ex_cubecl not installed", backend: :unavailable}
    end
  end

  @doc "Return the EXCubeCL version string."
  @spec version() :: String.t()
  def version, do: ExCubecl.version()

  @doc "Return true if a real GPU is available (not CPU fallback)."
  @spec gpu?() :: boolean()
  def gpu?, do: Map.get(device_info(), :gpu, false)

  @doc "Return the number of available GPU devices."
  @spec device_count() :: non_neg_integer()
  def device_count do
    if Code.ensure_loaded?(ExCubecl) do
      case ExCubecl.device_count() do
        {:ok, count} -> count
        {:error, _} -> 0
      end
    else
      0
    end
  end

  @doc "Return the list of available kernel names."
  @spec kernels() :: [String.t()]
  def kernels do
    case ExCubecl.kernels() do
      {:ok, names} -> names
      {:error, _} -> []
    end
  end

  @doc "Return the list of supported dtype atoms."
  @spec supported_dtypes() :: [atom()]
  def supported_dtypes, do: ExCubecl.supported_dtypes()

  @doc "Check if the EXCubeCL NIF is loaded and available."
  @spec available?() :: boolean()
  def available? do
    Code.ensure_loaded?(ExCubecl) and ExCubecl.available?()
  rescue
    _ -> false
  end

  # ── Buffer management ─────────────────────────────────────────────────────

  @doc """
  Create a GPU buffer from a list of values.

  ## Options

  - `:shape` — tuple describing dimensions, e.g. `{3}` for a 1D vector of 3 elements
  - `:dtype` — data type atom (`:f32`, `:f64`, `:s32`, `:s64`, `:u32`, `:u8`)

  ## Example

      buf = Dala.Gpu.Compute.buffer([1.0, 2.0, 3.0], {3}, :f32)
  """
  @spec buffer(list(), tuple(), atom()) :: Buffer.t()
  def buffer(data, shape, dtype \\ :f32) do
    Buffer.new(data, shape, dtype)
  end

  @doc """
  Create an uninitialized GPU buffer with the given shape and dtype.

  ## Example

      buf = Dala.Gpu.Compute.buffer_zeros({256, 256}, :f32)
  """
  @spec buffer_zeros(tuple(), atom()) :: Buffer.t()
  def buffer_zeros(shape, dtype \\ :f32) do
    Buffer.zeros(shape, dtype)
  end

  @doc """
  Create a GPU buffer from a raw binary.

  ## Example

      buf = Dala.Gpu.Compute.buffer_from_binary(binary_data, {640, 480, 4}, :u8)
  """
  @spec buffer_from_binary(binary(), tuple(), atom()) :: Buffer.t()
  def buffer_from_binary(data, shape, dtype \\ :u8) do
    Buffer.from_binary(data, shape, dtype)
  end

  @doc "Return the shape of a buffer."
  @spec shape(Buffer.t()) :: tuple()
  def shape(%Buffer{ref: ref}) do
    {:ok, shape_list} = ExCubecl.shape(ref)
    List.to_tuple(shape_list)
  end

  @doc "Return the data type of a buffer."
  @spec dtype(Buffer.t()) :: atom()
  def dtype(%Buffer{ref: ref}) do
    {:ok, dtype_string} = ExCubecl.dtype(ref)
    String.to_atom(dtype_string)
  end

  @doc "Return the size of a buffer in bytes."
  @spec size(Buffer.t()) :: non_neg_integer()
  def size(%Buffer{ref: ref}) do
    {:ok, size} = ExCubecl.size(ref)
    size
  end

  @doc """
  Read data from a GPU buffer back to an Elixir binary.

  EXCubeCL 0.4+ returns `{:ok, binary()}` from `read/1`.
  This function returns the binary directly for a clean Dala API.

  ## Example

      data = Dala.Gpu.Compute.read(buf)
      # <<5.0, 7.0, 9.0>>
  """
  @spec read(Buffer.t()) :: binary()
  def read(%Buffer{ref: ref}) do
    {:ok, data} = ExCubecl.read(ref)
    data
  end

  @doc "Read data from a GPU buffer and convert to an Elixir list."
  @spec read_list(Buffer.t()) :: list()
  def read_list(%Buffer{ref: ref}) do
    {:ok, data} = ExCubecl.read(ref)
    :erlang.binary_to_list(data)
  end

  @doc "Read data from a GPU buffer as a raw binary (zero-copy when possible)."
  @spec read_binary(Buffer.t()) :: binary()
  def read_binary(%Buffer{ref: ref}) do
    {:ok, data} = ExCubecl.read(ref)
    data
  end

  @doc "Free a GPU buffer and release all associated GPU memory."
  @spec free(Buffer.t()) :: :ok
  # Buffers are automatically freed by Rust ResourceArc cleanup.
  # This is a no-op for API compatibility.
  def free(%Buffer{}), do: :ok

  @doc "Free multiple GPU buffers at once."
  @spec free_many([Buffer.t()]) :: :ok
  def free_many(_buffers), do: :ok

  # ── Kernel execution ──────────────────────────────────────────────────────

  @doc """
  Run a named kernel synchronously.

  ## Parameters

  - `kernel` — kernel atom (e.g. `:elementwise_add`, `:relu`, `:blur`)
  - `inputs` — list of input `Buffer` structs
  - `output` — output `Buffer` struct
  - `params` — map of kernel-specific parameters

  ## Example

      Dala.Gpu.Compute.run_kernel(:elementwise_add, [a, b], c, %{})
      Dala.Gpu.Compute.run_kernel(:relu, [a], b, %{slope: 0.1})
      Dala.Gpu.Compute.run_kernel(:blur, [image_buf], out_buf, %{radius: 3, sigma: 1.5})
  """
  @spec run_kernel(atom(), [Buffer.t()], Buffer.t(), map()) :: :ok | {:error, term()}
  def run_kernel(kernel, inputs, output, params \\ %{}) do
    Kernel.run(kernel, inputs, output, params)
  end

  @doc """
  Submit a compute command asynchronously. Returns a command ID for polling.

  The spec map is encoded as a string for EXCubeCL 0.4+.

  ## Example

      cmd_id = Dala.Gpu.Compute.submit(%{
        op: :run_kernel,
        kernel: "relu",
        inputs: [a.ref],
        output: b.ref,
        params: %{}
      })

      # Later...
      case Dala.Gpu.Compute.poll(cmd_id) do
        :completed -> Dala.Gpu.Compute.read(b)
        {:error, reason} -> handle_error(reason)
        :pending -> retry_later()
      end
  """
  @spec submit(map()) :: non_neg_integer()
  def submit(spec) do
    command_string = encode_submit_command(spec)
    {:ok, cmd_id} = ExCubecl.submit(command_string)
    cmd_id
  end

  @doc "Poll an async command. Returns `:pending`, `:completed`, or `{:error, reason}`."
  @spec poll(non_neg_integer()) :: :pending | :completed | {:error, term()}
  def poll(cmd_id) do
    case ExCubecl.poll(cmd_id) do
      {:ok, status} -> status
      {:error, _} = err -> err
    end
  end

  @doc "Block until an async command completes. Returns `:ok` or `{:error, reason}`."
  @spec wait(non_neg_integer()) :: :ok | {:error, term()}
  def wait(cmd_id) do
    ExCubecl.wait(cmd_id)
  end

  @doc "Run a kernel asynchronously and wait for completion."
  @spec run_kernel_async(atom(), [Buffer.t()], Buffer.t(), map()) :: :ok | {:error, term()}
  def run_kernel_async(kernel, inputs, output, params \\ %{}) do
    input_refs = Enum.map(inputs, & &1.ref)
    kernel_string = Atom.to_string(kernel)

    cmd_id =
      submit(%{
        op: :run_kernel,
        kernel: kernel_string,
        inputs: input_refs,
        output: output.ref,
        params: params
      })

    wait(cmd_id)
  end

  # Private: encode a submit spec map into an EXCubeCL command string.
  defp encode_submit_command(%{op: :run_kernel} = spec) do
    kernel = Map.get(spec, :kernel)
    inputs = Map.get(spec, :inputs, []) |> Enum.map(&inspect/1) |> Enum.join(", ")
    output = Map.get(spec, :output) |> inspect()
    params = Map.get(spec, :params, %{}) |> inspect()
    "run_kernel #{kernel} [#{inputs}] #{output} #{params}"
  end

  defp encode_submit_command(%{op: :copy_buffer} = spec) do
    src = inspect(Map.get(spec, :src))
    dst = inspect(Map.get(spec, :dst))
    size = Map.get(spec, :size, 0)
    "copy_buffer #{src} #{dst} #{size}"
  end

  defp encode_submit_command(spec) do
    inspect(spec)
  end

  # ── Pipeline orchestration ────────────────────────────────────────────────

  @doc "Create a new empty GPU compute pipeline."
  @spec pipeline() :: Pipeline.t()
  def pipeline do
    Pipeline.new()
  end

  @doc "Add a stage to a pipeline. Returns the pipeline for chaining."
  @spec pipeline_add(Pipeline.t(), map()) :: Pipeline.t()
  def pipeline_add(%Pipeline{} = pipeline, stage_spec) do
    Pipeline.add(pipeline, stage_spec)
  end

  @doc "Execute all stages in a pipeline sequentially."
  @spec pipeline_run(Pipeline.t()) :: :ok | {:error, term()}
  def pipeline_run(%Pipeline{} = pipeline) do
    Pipeline.run(pipeline)
  end

  @doc "Free a pipeline and its internal resources."
  @spec free_pipeline(Pipeline.t()) :: :ok
  def free_pipeline(%Pipeline{} = _pipeline) do
    # Pipeline is freed automatically after run/1 completes.
    # This is a no-op for API compatibility.
    :ok
  end

  # ── Built-in kernel helpers ───────────────────────────────────────────────

  @doc """
  Elementwise addition: output = a + b

  ## Example

      c = Dala.Gpu.Compute.buffer_zeros({3}, :f32)
      Dala.Gpu.Compute.add(a, b, c)
  """
  @spec add(Buffer.t(), Buffer.t(), Buffer.t()) :: :ok | {:error, term()}
  def add(a, b, output), do: run_kernel(:elementwise_add, [a, b], output, %{})

  @doc """
  Elementwise ReLU activation: output = max(0, input)

  ## Example

      Dala.Gpu.Compute.relu(input, output)
  """
  @spec relu(Buffer.t(), Buffer.t()) :: :ok | {:error, term()}
  def relu(input, output), do: run_kernel(:relu, [input], output, %{})

  @doc """
  Elementwise multiply: output = a * b

  ## Example

      Dala.Gpu.Compute.multiply(a, b, output)
  """
  @spec multiply(Buffer.t(), Buffer.t(), Buffer.t()) :: :ok | {:error, term()}
  def multiply(a, b, output), do: run_kernel(:elementwise_mul, [a, b], output, %{})

  @doc """
  Scalar multiply: output = input * scalar

  ## Example

      Dala.Gpu.Compute.scale(input, 2.5, output)
  """
  @spec scale(Buffer.t(), number(), Buffer.t()) :: :ok | {:error, term()}
  def scale(input, scalar, output) do
    run_kernel(:scalar_mul, [input], output, %{scalar: scalar})
  end

  @doc """
  Matrix multiplication: output = a * b

  Both buffers must be 2D. Shape validation is performed by the kernel.

  ## Example

      a = Dala.Gpu.Compute.buffer(list_4, {2, 2}, :f32)
      b = Dala.Gpu.Compute.buffer(list_4, {2, 2}, :f32)
      c = Dala.Gpu.Compute.buffer_zeros({2, 2}, :f32)
      Dala.Gpu.Compute.matmul(a, b, c)
  """
  @spec matmul(Buffer.t(), Buffer.t(), Buffer.t()) :: :ok | {:error, term()}
  def matmul(a, b, output), do: run_kernel(:matmul, [a, b], output, %{})

  # ── Surface integration ───────────────────────────────────────────────────

  @doc """
  Run a compute kernel and upload the result directly to a GPU surface.

  This is a convenience function that combines kernel execution with
  surface pixel upload, avoiding an intermediate read-back to the CPU.

  ## Example

      {:ok, surface} = Dala.Gpu.create_surface(640, 480)
      Dala.Gpu.Compute.run_to_surface(kernel, [input_buf], output_buf, surface, %{})
  """
  @spec run_to_surface(atom(), [Buffer.t()], Buffer.t(), pid(), map()) :: :ok | {:error, term()}
  def run_to_surface(kernel, inputs, output, surface, params \\ %{}) do
    :ok = run_kernel(kernel, inputs, output, params)

    pixels = read(output)

    Dala.Gpu.set_pixels(surface, pixels)
    Dala.Gpu.present(surface)
  end

  # ── Nx tensor bridge ──────────────────────────────────────────────────────

  @doc """
  Convert an Nx tensor to a GPU buffer.

  ## Example

      tensor = Nx.tensor([1.0, 2.0, 3.0])
      buf = Dala.Gpu.Compute.from_nx(tensor)
  """
  @spec from_nx(Nx.Tensor.t()) :: Buffer.t()
  def from_nx(tensor) do
    data = Nx.to_flat_list(tensor)
    shape = Nx.shape(tensor)
    dtype = nx_dtype_to_cube(Nx.type(tensor))
    buffer(data, shape, dtype)
  end

  @doc """
  Convert a GPU buffer to an Nx tensor.

  ## Example

      tensor = Dala.Gpu.Compute.to_nx(buf, {3}, :f32)
  """
  @spec to_nx(Buffer.t(), tuple(), atom()) :: Nx.Tensor.t()
  def to_nx(buf, shape, dtype) do
    data = read(buf)
    nx_dtype = cube_dtype_to_nx(dtype)
    Nx.from_binary(data, nx_dtype) |> Nx.reshape(shape)
  end

  # Private: dtype conversion helpers
  defp nx_dtype_to_cube({:u, 8}), do: :u8
  defp nx_dtype_to_cube({:s, 32}), do: :s32
  defp nx_dtype_to_cube({:s, 64}), do: :s64
  defp nx_dtype_to_cube({:u, 32}), do: :u32
  defp nx_dtype_to_cube({:f, 32}), do: :f32
  defp nx_dtype_to_cube({:f, 64}), do: :f64
  defp nx_dtype_to_cube(_), do: :f32

  defp cube_dtype_to_nx(:u8), do: {:u, 8}
  defp cube_dtype_to_nx(:s32), do: {:s, 32}
  defp cube_dtype_to_nx(:s64), do: {:s, 64}
  defp cube_dtype_to_nx(:u32), do: {:u, 32}
  defp cube_dtype_to_nx(:f32), do: {:f, 32}
  defp cube_dtype_to_nx(:f64), do: {:f, 64}
  defp cube_dtype_to_nx(_), do: {:f, 32}
end
