defmodule Dala.Ui.NativeView do
  @moduledoc """
  Behaviour for native view components.

  A component is a stateful Elixir process paired with a platform-native view
  registered by name on iOS/Android. The BEAM owns the state; the native side
  owns the rendering.

  ## Lifecycle

  1. The parent screen declares `Dala.Ui.Widgets.native_view(MyComponent, id: :my_id, ...)`
  2. On first render, a `Dala.Ui.NativeView.Server` process is started and `mount/2` is called
  3. `render/1` is called to get the props map forwarded to the native factory
  4. On subsequent renders, `update/2` is called with new props from the parent
  5. When the native view fires an event, `handle_event/3` is called
  6. After any state change, `render/1` is re-called and native props are updated
  7. When the component leaves the tree, the process is stopped and `terminate/2` is called

  ## Usage

      defmodule MyApp.ChartComponent do
        use Dala.Ui.NativeView

        def mount(props, socket) do
          {:ok, Dala.Socket.assign(socket, :data, props[:data])}
        end

        def render(assigns) do
          %{data: assigns.data}
        end

        def handle_event("segment_tapped", %{"index" => i}, socket) do
          {:noreply, Dala.Socket.assign(socket, :selected, i)}
        end
      end

  ## Native registration

  Register the view factory at app startup:

      # iOS (Swift) — strip "Elixir." prefix and replace "." with "_":
      dalaNativeViewRegistry.shared.register("MyApp_ChartComponent") { props, send in
          AnyView(ChartView(data: props["data"]) { index in
              send("segment_tapped", ["index": index])
          })
      }

      # Android (Kotlin):
      dalaNativeViewRegistry.register("MyApp_ChartComponent") { props, send ->
          ChartView(data = props["data"]) { index ->
              send("segment_tapped", mapOf("index" to index))
          }
      }

  ## Declaration

      Dala.Ui.Widgets.native_view(MyApp.ChartComponent, id: :revenue_chart, data: @points)

  The `:id` must be unique per screen. Duplicate ids on the same screen raise at render time.

  ## Stateless components

  If a component has no internal state, omit `mount/2` and `handle_info/2`. The
  default `handle_event/3` raises for any event — add clauses for the events your
  native view fires, or delegate to the parent screen by forwarding via `send/2`.

  ## Plugin Components

  Plugin components are registered via `Dala.Plugin` and use string type names
  instead of atoms. They are automatically expanded using the same lifecycle
  as native_view components, but without requiring a custom Elixir module.

  Example:

      %{type: "video", props: %{source: "...", autoplay: true}, children: []}
  """

  @callback mount(props :: map(), socket :: Dala.Socket.t()) ::
              {:ok, Dala.Socket.t()} | {:error, term()}

  @callback update(props :: map(), socket :: Dala.Socket.t()) ::
              {:ok, Dala.Socket.t()}

  @doc """
  Render the component's current props.

  Returns a flat **prop map** — not a node. The result is merged into the
  `:native_view` node's props alongside the injected `:module`, `:id` and
  `:component_handle` keys before being sent to native.
  """
  @callback render(assigns :: map()) :: map()

  @callback handle_event(event :: String.t(), payload :: map(), socket :: Dala.Socket.t()) ::
              {:noreply, Dala.Socket.t()}

  @callback handle_info(message :: term(), socket :: Dala.Socket.t()) ::
              {:noreply, Dala.Socket.t()}

  @callback terminate(reason :: term(), socket :: Dala.Socket.t()) :: term()

  @optional_callbacks [update: 2, handle_event: 3, handle_info: 2, terminate: 2]

  defmacro __using__(_opts) do
    quote do
      @behaviour Dala.Ui.NativeView

      def mount(props, socket), do: {:ok, socket}

      def update(props, socket), do: mount(props, socket)

      def handle_event(event, _payload, _socket) do
        raise RuntimeError,
              "unhandled component event #{inspect(event)} in #{inspect(__MODULE__)}. " <>
                "Add a handle_event/3 clause to handle it."
      end

      def handle_info(_message, socket), do: {:noreply, socket}
      def terminate(_reason, _socket), do: :ok

      defoverridable mount: 2, update: 2, handle_event: 3, handle_info: 2, terminate: 2
    end
  end

  # ── Tree expansion ────────────────────────────────────────────────────────

  @doc """
  Walk a node tree, expanding `:native_view` nodes into serialisable form.

  Starts or updates component processes, collects their rendered props, and
  injects the NIF handle. Returns `{expanded_tree, active_keys}` where
  `active_keys` is a `MapSet` of `{id, module}` pairs seen in this render —
  used by the screen to stop components that have left the tree.

  Also expands plugin-based components (registered via Dala.Plugin).
  """
  @spec expand(map() | [map()], pid(), atom()) :: {map() | [map()], MapSet.t()}
  def expand(tree, screen_pid, platform) when is_list(tree) do
    active = MapSet.new()
    Enum.map_reduce(tree, active, &walk(&1, screen_pid, platform, &2))
  end

  def expand(tree, screen_pid, platform) do
    active = MapSet.new()
    walk(tree, screen_pid, platform, active)
  end

  defp walk(%{type: :native_view, props: props} = node, screen_pid, platform, active) do
    module = props[:module]
    id = props[:id]

    # is_atom(nil) is true — exclude nil explicitly so a missing :module or
    # :id fails with this error instead of an obscure crash inside the server.
    unless is_atom(module) and not is_nil(module) and is_atom(id) and not is_nil(id) do
      raise ArgumentError,
            "Dala.Ui.Widgets.native_view requires :module and :id as atoms, got: #{inspect(props)}"
    end

    component_pid = ensure_started(screen_pid, id, module, props, platform)

    rendered_props = Dala.Ui.NativeView.Server.render_props(component_pid)
    handle = Dala.Ui.NativeView.Server.get_handle(component_pid)

    enriched =
      Map.merge(rendered_props, %{
        module: module_name(module),
        id: Atom.to_string(id),
        component_handle: handle
      })

    active = MapSet.put(active, {id, module})
    {%{node | props: enriched}, active}
  end

  defp walk(%{type: type, props: props} = node, screen_pid, platform, active)
       when is_binary(type) do
    # Check if this is a plugin component
    case Dala.Plugin.Registry.lookup_component(type) do
      {:ok, _plugin} ->
        # Plugin component - treat as native_view with auto-generated module
        id =
          props[:id] ||
            raise ArgumentError,
                  "Plugin component #{type} requires :id prop"

        # Use a tuple key instead of dynamic atom to avoid atom table pollution
        module = {:plugin_component, type}

        component_pid = ensure_started(screen_pid, id, module, props, platform)
        rendered_props = Dala.Ui.NativeView.Server.render_props(component_pid)
        handle = Dala.Ui.NativeView.Server.get_handle(component_pid)

        enriched =
          Map.merge(rendered_props, %{
            module: type,
            id: to_string(id),
            component_handle: handle
          })

        active = MapSet.put(active, {id, module})
        {%{node | props: enriched}, active}

      {:error, :not_found} ->
        # Not a plugin component, continue normal walk
        walk_children(node, screen_pid, platform, active)
    end
  end

  defp walk(%{children: _children} = node, screen_pid, platform, active) do
    walk_children(node, screen_pid, platform, active)
  end

  defp walk(node, _screen_pid, _platform, active), do: {node, active}

  defp walk_children(%{children: children} = node, screen_pid, platform, active) do
    {new_children, active} =
      Enum.map_reduce(children, active, fn child, acc ->
        walk(child, screen_pid, platform, acc)
      end)

    {%{node | children: new_children}, active}
  end

  defp ensure_started(screen_pid, id, module, props, platform) do
    case Dala.Ui.NativeView.Registry.lookup(screen_pid, id, module) do
      {:ok, pid} ->
        Dala.Ui.NativeView.Server.update(pid, props)
        pid

      {:error, :not_found} ->
        {:ok, pid} =
          Dala.Ui.NativeView.Server.start(
            module: module,
            id: id,
            screen_pid: screen_pid,
            props: props,
            platform: platform
          )

        pid
    end
  end

  # "Elixir.MyApp.ChartComponent" → "MyApp_ChartComponent"
  # Cached per-module since the same module appears on every render.
  defp module_name(module) do
    case :ets.lookup(:dala_module_names, module) do
      [{^module, name}] ->
        name

      [] ->
        name =
          module
          |> Atom.to_string()
          |> String.replace_prefix("Elixir.", "")
          |> String.replace(".", "_")

        :ets.insert(:dala_module_names, {module, name})
        name
    end
  end

  @doc false
  @spec init_module_name_cache() :: :ok
  def init_module_name_cache do
    case :ets.whereis(:dala_module_names) do
      :undefined ->
        :ets.new(:dala_module_names, [:set, :public, :named_table, read_concurrency: true])

      _ ->
        :ok
    end

    :ok
  end
end
