defmodule Dala.Ui.NativeView.Server do
  @compile {:nowarn_undefined, [:Nx]}
  @moduledoc false
  # GenServer wrapping a Dala.Ui.NativeView module. Each native_view instance on a
  # screen gets its own process. Started unlinked (isolated from the screen).

  use GenServer

  @doc "Start a component process (not linked to the caller)."
  @spec start(keyword()) :: {:ok, pid()} | {:error, term()}
  def start(opts) do
    GenServer.start(__MODULE__, opts)
  end

  @doc "Get the current rendered props from the component."
  @spec render_props(pid()) :: map()
  def render_props(pid), do: GenServer.call(pid, :render_props)

  @doc "Get the persistent NIF handle allocated at mount time."
  @spec get_handle(pid()) :: integer()
  def get_handle(pid), do: GenServer.call(pid, :get_handle)

  @doc "Update the component with new props from the parent screen re-render."
  @spec update(pid(), map()) :: :ok
  def update(pid, props), do: GenServer.cast(pid, {:update, props})

  @doc "Deliver a native event to the component (called from the NIF callback path)."
  @spec dispatch(pid(), String.t(), map()) :: :ok
  def dispatch(pid, event, payload), do: GenServer.cast(pid, {:event, event, payload})

  # ── GenServer ──────────────────────────────────────────────────────────────

  @impl GenServer
  def init(opts) do
    module = opts[:module]
    id = opts[:id]
    screen_pid = opts[:screen_pid]
    props = opts[:props]
    platform = opts[:platform]

    socket = Dala.Socket.new(screen_module(module), platform: platform)

    case component_mount(module, props, socket) do
      {:ok, socket} ->
        Dala.Ui.NativeView.Registry.register(screen_pid, id, module, self())

        handle =
          if platform != :no_render do
            Dala.Platform.Native.register_component(self())
          else
            0
          end

        {:ok,
         %{
           module: module,
           socket: socket,
           screen_pid: screen_pid,
           id: id,
           handle: handle,
           props: props
         }}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  # Plugin components (registered via Dala.Plugin) are opaque to the BEAM:
  # the native side owns their rendering, keyed by the component type. Their
  # "module" here is the {:plugin_component, type} tuple.
  defp plugin_component?({:plugin_component, _type}), do: true
  defp plugin_component?(_), do: false

  defp screen_module({:plugin_component, type}), do: :"dala_plugin_#{type}"
  defp screen_module(module), do: module

  defp component_mount(module, props, socket) do
    if plugin_component?(module), do: {:ok, socket}, else: module.mount(props, socket)
  end

  defp component_update(module, props, socket) do
    if plugin_component?(module), do: {:ok, socket}, else: module.update(props, socket)
  end

  defp component_event(module, event, payload, socket) do
    if plugin_component?(module) do
      socket
    else
      case module.handle_event(event, payload, socket) do
        {:noreply, ns} -> ns
        {:reply, _response, ns} -> ns
      end
    end
  end

  defp handle_info_message(module, message, socket) do
    if plugin_component?(module) do
      socket
    else
      case module.handle_info(message, socket) do
        {:noreply, ns} -> ns
        {:reply, _response, ns} -> ns
      end
    end
  end

  defp component_render(module, assigns, state) do
    if plugin_component?(module), do: Map.get(state, :props, %{}), else: module.render(assigns)
  end

  @impl GenServer
  def handle_call(:render_props, _from, %{module: module, socket: socket} = state) do
    {:reply, component_render(module, socket.assigns, state), state}
  end

  def handle_call(:get_handle, _from, %{handle: handle} = state) do
    {:reply, handle, state}
  end

  @impl GenServer
  def handle_cast({:update, new_props}, %{module: module, socket: socket} = state) do
    case component_update(module, new_props, socket) do
      {:ok, new_socket} ->
        {:noreply, %{state | socket: new_socket, props: new_props}}

      {:error, reason} ->
        require Logger

        Logger.warning(
          "Dala.Ui.NativeView.Server: update failed for #{inspect(module)}: #{inspect(reason)}"
        )

        {:noreply, state}
    end
  end

  def handle_cast(
        {:event, event, payload},
        %{module: module, socket: socket, screen_pid: screen_pid, id: id} = state
      ) do
    new_socket = component_event(module, event, payload, socket)

    send(screen_pid, {:component_changed, id, module})
    {:noreply, %{state | socket: new_socket}}
  end

  @impl GenServer
  def handle_info(
        {:component_event, event, payload_json},
        %{module: module, socket: socket, screen_pid: screen_pid, id: id} = state
      ) do
    payload =
      case :json.decode(payload_json) do
        map when is_map(map) -> map
        _ -> %{}
      end

    new_socket = component_event(module, event, payload, socket)

    send(screen_pid, {:component_changed, id, module})
    {:noreply, %{state | socket: new_socket}}
  end

  def handle_info(
        message,
        %{module: module, socket: socket, screen_pid: screen_pid, id: id} = state
      ) do
    new_socket = handle_info_message(module, message, socket)

    send(screen_pid, {:component_changed, id, module})
    {:noreply, %{state | socket: new_socket}}
  end

  @impl GenServer
  def terminate(reason, %{
        module: module,
        socket: socket,
        screen_pid: screen_pid,
        id: id,
        handle: handle
      }) do
    Dala.Ui.NativeView.Registry.deregister(screen_pid, id, module)
    if handle != 0, do: Dala.Platform.Native.deregister_component(handle)
    module.terminate(reason, socket)
  end
end
