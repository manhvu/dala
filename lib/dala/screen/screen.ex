defmodule Dala.Screen.Screen do
  @compile {:nowarn_undefined, [:Nx]}
  @moduledoc """
  Screen behaviour and Spark DSL entry point.

  ## Usage

      defmodule MyApp.CounterScreen do
        use Dala.Screen

        attribute :count, :integer, default: 0

        screen name: :counter do
          column gap: :space_sm do
            text "Count: @count"
            button "Increment", on_tap: :increment
          end
        end

        def handle_event(:increment, _params, socket) do
          {:noreply, Dala.Socket.assign(socket, :count, socket.assigns.count + 1)}
        end
      end

  ## Starting a screen

      Dala.Screen.start_root(MyApp.CounterScreen, %{})

  ## Dispatching events

    Dala.Screen.dispatch(pid, "increment", %{})
  """

  # Set up Spark DSL - use Dala.Spark.Dsl which registers itself as an extension

  # The __using__ macro now just needs to call `use Dala.Screen`
  defmacro __using__(_opts) do
    quote do
      use Dala.Spark.Dsl
      require Dala.Spark.Dsl
      import Dala.Spark.Dsl
      @behaviour Dala.Screen

      # Default handle_info implementation
      def handle_info(_message, socket), do: {:noreply, socket}

      def terminate(_reason, _socket), do: :ok

      def handle_event(event, _params, _socket) do
        raise "unhandled event #{inspect(event)} in #{inspect(__MODULE__)}. " <>
                "Add a handle_event/3 clause to handle it."
      end

      defoverridable handle_info: 2, terminate: 2, handle_event: 3
    end
  end

  # ── GenServer wrapper ─────────────────────────────────────────────────────

  use GenServer

  @doc """
  Start a screen process linked to the calling process.

  `params` is passed as the first argument to `mount/3`.
  """
  @spec start_link(module(), map(), keyword()) :: GenServer.on_start()
  def start_link(screen_module, params, opts \\ []) do
    GenServer.start_link(__MODULE__, {screen_module, params, :no_render, :android, nil}, opts)
  end

  @doc """
  Return the module of the currently active screen in the navigation stack.
  Intended for testing and debugging.
  """
  @spec get_current_module(pid()) :: module()
  def get_current_module(pid) do
    GenServer.call(pid, :get_current_module)
  end

  @doc """
  Return the navigation history (list of `{module, socket}` pairs, head = most recent).
  Intended for testing and debugging.
  """
  @spec get_nav_history(pid()) :: [{module(), Dala.Socket.t()}]
  def get_nav_history(pid) do
    GenServer.call(pid, :get_nav_history)
  end

  @doc """
  Send a message to a screen identified by `identifier` (id, name, or pid).

  Returns `:ok` if sent, `{:error, :not_found}` if identifier doesn't match any screen.

  ## Examples

      MyApp.MyScreen.dispatch(:my_screen, {:update, data})
      MyApp.MyScreen.dispatch(123, {:update, data})
      MyApp.MyScreen.dispatch(pid, {:update, data})
  """
  @spec dispatch(identifier :: pid | atom | integer, message :: term) ::
          :ok | {:error, :not_found}
  def dispatch(identifier, message) do
    Dala.Screen.Manager.dispatch(identifier, message)
  end

  @doc """
  List all registered screens.

  Returns a list of maps with `:id`, `:name`, `:pid`, `:module`.
  """
  @spec list() :: [%{id: integer, name: atom | nil, pid: pid, module: module}]
  def list do
    Dala.Screen.Manager.list()
  end

  # ── Navigation ────────────────────────────────────────────────────────────
  @doc """
  Start a screen as the root UI screen. Calls mount, renders the component tree
  via `Dala.Ui.Renderer`, and sends the binary tree to the native side.

  This is the main entry point for production use. `start_link/3` is for tests
  (no NIF calls).
  """
  @spec start_root(module(), map(), keyword()) :: GenServer.on_start()
  def start_root(screen_module, params \\ %{}, opts \\ []) do
    platform = Dala.Platform.Native.platform()
    GenServer.start_link(__MODULE__, {screen_module, params, :render, platform, nil}, opts)
  end

  @doc """
  Dispatch a UI event to the screen process. Returns `:ok` synchronously once
  the event has been processed and the state updated.
  """
  @spec dispatch(pid(), String.t(), map()) :: :ok
  def dispatch(pid, event, params) do
    GenServer.call(pid, {:event, event, params})
  end

  @doc """
  Return the current socket state of a running screen.
  Intended for testing and debugging — not for production app logic.
  """
  @spec get_socket(pid()) :: Dala.Socket.t()
  def get_socket(pid) do
    GenServer.call(pid, :get_socket)
  end

  # ── GenServer callbacks ───────────────────────────────────────────────────

  @impl GenServer
  def init({screen_module, params, render_mode, platform, _screen_id}) do
    socket = Dala.Socket.new(screen_module, platform: platform)

    # Register under :dala_screen so C-layer dala_handle_back() can find us.
    # Only in :render mode (production); tests use :no_render and run without a NIF.
    if render_mode == :render, do: Process.register(self(), :dala_screen)

    socket =
      if render_mode == :render do
        Dala.Socket.assign(socket, :safe_area, safe_area_for_platform(platform))
      else
        Dala.Socket.assign(socket, :safe_area, safe_area_for_platform(:android))
      end

    case screen_module.mount(params, %{}, socket) do
      {:ok, mounted_socket} ->
        final_socket =
          if render_mode == :render do
            # Check for a notification that launched the app from a killed state.
            # Send it to self() so it arrives via handle_info after init returns,
            # consistent with foreground notification delivery.
            case Dala.Platform.Native.take_launch_notification() do
              :none -> :ok
              json -> send(self(), {:dala_launch_notification, json})
            end

            do_render(screen_module, mounted_socket)
          else
            mounted_socket
          end

        # Register with screen manager
        screen_id = Dala.Screen.Manager.next_id()
        screen_name = final_socket.assigns[:name]
        Dala.Screen.Manager.register(screen_id, screen_name, self(), screen_module)

        {:ok, {screen_module, final_socket, [], render_mode, screen_id}}

      {:error, reason} ->
        Dala.Platform.Native.log(
          "Dala.Screen: mount failed for #{inspect(screen_module)}: #{inspect(reason)}"
        )

        {:stop, reason}

      {:stop, reason} ->
        Dala.Platform.Native.log(
          "Dala.Screen: mount halted for #{inspect(screen_module)}: #{inspect(reason)}"
        )

        {:stop, reason}
    end
  end

  @impl GenServer
  def terminate(reason, {module, socket, _nav_history, _render_mode, _screen_id}) do
    Dala.Screen.Manager.unregister(self())
    module.terminate(reason, socket)
  end

  @impl GenServer
  def handle_call(
        {:event, event, params},
        _from,
        {module, socket, nav_history, render_mode, screen_id}
      ) do
    case module.handle_event(event, params, socket) do
      {:noreply, new_socket} ->
        {module, new_socket, nav_history, transition} =
          apply_nav_action(module, new_socket, nav_history)

        new_socket =
          if render_mode == :render do
            do_render(module, new_socket, transition)
          else
            new_socket
          end

        {:reply, :ok, {module, new_socket, nav_history, render_mode, screen_id}}

      {:reply, _response, new_socket} ->
        {module, new_socket, nav_history, transition} =
          apply_nav_action(module, new_socket, nav_history)

        new_socket =
          if render_mode == :render do
            do_render(module, new_socket, transition)
          else
            new_socket
          end

        {:reply, :ok, {module, new_socket, nav_history, render_mode, screen_id}}
    end
  end

  @doc """
  Apply a navigation action directly. Used by `Dala.Test` to drive navigation
  programmatically without needing a UI event. Synchronous — the caller blocks
  until the navigation (and re-render, in production mode) completes.

  Valid actions mirror the `Dala.Socket` navigation functions:
  - `{:push, dest, params}` — push a new screen
  - `{:pop}` — pop to the previous screen
  - `{:pop_to, dest}` — pop to a specific screen in history
  - `{:pop_to_root}` — pop to the root of the current stack
  - `{:reset, dest, params}` — replace the entire nav stack
  """
  def handle_call(
        {:navigate, nav_action},
        _from,
        {module, socket, nav_history, render_mode, screen_id}
      ) do
    socket = Dala.Socket.put_dala(socket, :nav_action, nav_action)

    {new_module, new_socket, new_history, transition} =
      apply_nav_action(module, socket, nav_history)

    new_socket =
      if render_mode == :render do
        do_render(new_module, new_socket, transition)
      else
        new_socket
      end

    {:reply, :ok, {new_module, new_socket, new_history, render_mode, screen_id}}
  end

  def handle_call(:get_socket, _from, {_module, socket, _nav_history, _mode, _screen_id} = state) do
    {:reply, socket, state}
  end

  def handle_call(:inspect, _from, {module, socket, nav_history, _mode, _screen_id} = state) do
    tree = module.render(socket.assigns)

    info = %{
      screen: module,
      assigns: socket.assigns,
      nav_history: Enum.map(nav_history, fn {mod, _} -> mod end),
      tree: tree
    }

    {:reply, info, state}
  end

  def handle_call(
        :get_current_module,
        _from,
        {module, _socket, _nav_history, _mode, _screen_id} = state
      ) do
    {:reply, module, state}
  end

  def handle_call(
        :get_nav_history,
        _from,
        {_module, _socket, nav_history, _mode, _screen_id} = state
      ) do
    {:reply, nav_history, state}
  end

  # Notification that launched the app from a killed state.
  # Decoded from JSON and re-dispatched as the standard {:notification, map} message.
  # Hot-reload trigger sent by dala_dev after a dist push. Re-render with current code.
  @impl GenServer
  def handle_cast(:__dala_hot_reload__, {module, socket, nav_history, render_mode, screen_id}) do
    new_socket =
      if render_mode == :render do
        do_render(module, socket, :hot_reload)
      else
        socket
      end

    {:noreply, {module, new_socket, nav_history, render_mode, screen_id}}
  end

  @impl GenServer
  def handle_info(
        {:dala_launch_notification, json},
        {module, socket, nav_history, render_mode, screen_id}
      ) do
    notif = decode_notification_json(json)
    handle_info({:notification, notif}, {module, socket, nav_history, render_mode, screen_id})
  end

  # Android file/camera/photo/scan results arrive as {:dala_file_result, event, sub, json_binary}.
  # Decode the JSON and re-dispatch as the user-facing event tuple.
  def handle_info(
        {:dala_file_result, event, sub, json_binary},
        {module, socket, nav_history, render_mode, screen_id}
      ) do
    event_atom = to_atom_safe(event)
    sub_atom = to_atom_safe(sub)

    items =
      case :json.decode(json_binary) do
        list when is_list(list) ->
          Enum.map(list, fn item when is_map(item) ->
            Map.new(item, fn {k, v} -> {String.to_existing_atom(k), v} end)
          end)

        _ ->
          []
      end

    msg =
      case {event_atom, sub_atom} do
        {:camera, :photo} ->
          {:camera, :photo, List.first(items) || %{}}

        {:camera, :video} ->
          {:camera, :video, List.first(items) || %{}}

        {:camera, :cancelled} ->
          {:camera, :cancelled}

        {:photos, :picked} ->
          {:photos, :picked, items}

        {:files, :picked} ->
          {:files, :picked, items}

        {:audio, :recorded} ->
          {:audio, :recorded, List.first(items) || %{}}

        {:storage, :saved_to_library} ->
          item = List.first(items) || %{}
          {:storage, :saved_to_library, item[:path]}

        {:scan, :result} ->
          item = List.first(items) || %{}
          {:scan, :result, %{type: item[:type] |> to_atom_safe(), value: item[:value]}}

        _ ->
          {event_atom, sub_atom, items}
      end

    handle_info(msg, {module, socket, nav_history, render_mode, screen_id})
  end

  # System back gesture (Android hardware/swipe, iOS edge-pan).
  # Handled here — before the user's handle_info — so every screen gets back
  # navigation for free without implementing anything.
  # If a WebView is present and has internal history, navigate within it first
  # before popping the Dala nav stack.
  def handle_info({:dala, :back}, {module, socket, nav_history, render_mode, screen_id}) do
    if render_mode == :render && Dala.Platform.Native.webview_can_go_back() do
      Dala.Platform.Native.webview_go_back()
      {:noreply, {module, socket, nav_history, render_mode, screen_id}}
    else
      {module, new_socket, new_history, transition} =
        if nav_history == [] do
          if render_mode == :render, do: Dala.Platform.Native.exit_app()
          {module, socket, [], :none}
        else
          apply_nav_action(
            module,
            Dala.Socket.put_dala(socket, :nav_action, {:pop}),
            nav_history
          )
        end

      new_socket =
        if render_mode == :render do
          do_render(module, new_socket, transition)
        else
          new_socket
        end

      {:noreply, {module, new_socket, new_history, render_mode, screen_id}}
    end
  end

  # List row selected — intercept before the user's handle_info and convert to
  # a plain {:select, id, index} message so screens don't need to know about
  # the internal {:tap, {:list, ...}} tag format.
  def handle_info(
        {:tap, {:list, id, :select, index}},
        {module, socket, nav_history, render_mode, screen_id}
      ) do
    {:noreply, new_socket} = module.handle_info({:select, id, index}, socket)

    {module, new_socket, nav_history, transition} =
      apply_nav_action(module, new_socket, nav_history)

    new_socket =
      if render_mode == :render do
        do_render(module, new_socket, transition)
      else
        new_socket
      end

    {:noreply, {module, new_socket, nav_history, render_mode, screen_id}}
  end

  # A component's state changed — re-render so the native view gets fresh props.
  def handle_info(
        {:component_changed, _id, _module},
        {module, socket, nav_history, render_mode, screen_id}
      ) do
    new_socket =
      if render_mode == :render do
        do_render(module, socket)
      else
        socket
      end

    {:noreply, {module, new_socket, nav_history, render_mode, screen_id}}
  end

  def handle_info(message, {module, socket, nav_history, render_mode, screen_id}) do
    {:noreply, new_socket} = module.handle_info(message, socket)

    {module, new_socket, nav_history, transition} =
      apply_nav_action(module, new_socket, nav_history)

    new_socket =
      if render_mode == :render do
        do_render(module, new_socket, transition)
      else
        new_socket
      end

    {:noreply, {module, new_socket, nav_history, render_mode, screen_id}}
  end

  defp to_atom_safe(nil), do: :unknown

  defp to_atom_safe(s) when is_binary(s) do
    String.to_existing_atom(s)
  rescue
    ArgumentError -> :unknown
  end

  defp to_atom_safe(a) when is_atom(a), do: a

  # ── Navigation ────────────────────────────────────────────────────────────

  # Inspect the socket's nav_action and execute it, returning
  # {new_module, new_socket, new_nav_history, transition}.
  defp apply_nav_action(module, socket, nav_history) do
    case socket.__dala__.nav_action do
      nil ->
        {module, socket, nav_history, :none}

      {:push, dest, params} ->
        new_module = resolve_module(dest)
        platform = socket.__dala__.platform

        new_base =
          Dala.Socket.new(new_module, platform: platform)
          |> Dala.Socket.assign(:safe_area, socket.assigns.safe_area)

        {:ok, mounted} = new_module.mount(params, %{}, new_base)
        saved = {module, clear_nav_action(socket)}
        {new_module, mounted, [saved | nav_history], :push}

      {:pop} ->
        case nav_history do
          [{prev_module, prev_socket} | rest] ->
            {prev_module, prev_socket, rest, :pop}

          [] ->
            {module, clear_nav_action(socket), [], :none}
        end

      {:pop_to_root} ->
        case Enum.reverse(nav_history) do
          [{root_module, root_socket} | _] ->
            {root_module, root_socket, [], :pop}

          [] ->
            {module, clear_nav_action(socket), [], :none}
        end

      {:pop_to, dest} ->
        target = resolve_module(dest)

        case pop_to_module(nav_history, target) do
          {:found, prev_module, prev_socket, rest} ->
            {prev_module, prev_socket, rest, :pop}

          :not_found ->
            {module, clear_nav_action(socket), nav_history, :none}
        end

      {:reset, dest, params} ->
        new_module = resolve_module(dest)
        platform = socket.__dala__.platform

        new_base =
          Dala.Socket.new(new_module, platform: platform)
          |> Dala.Socket.assign(:safe_area, socket.assigns.safe_area)

        {:ok, mounted} = new_module.mount(params, %{}, new_base)
        {new_module, mounted, [], :reset}

      {:switch_tab, _tab} ->
        # Tab switching is handled renderer-side; clear the action.
        {module, clear_nav_action(socket), nav_history, :none}
    end
  end

  defp resolve_module(dest) when is_atom(dest) do
    case Code.ensure_loaded(dest) do
      {:module, ^dest} ->
        # dest is a loaded module — use it directly
        dest

      _ ->
        # dest is a registered screen name atom — look up in registry
        case Dala.Nav.Registry.lookup(dest) do
          {:ok, module} ->
            module

          {:error, :not_found} ->
            raise ArgumentError,
                  "Dala.Screen: unknown navigation destination #{inspect(dest)}. " <>
                    "Register it via Dala.Nav.Registry.register/2 or declare it in " <>
                    "your App.navigation/1."
        end
    end
  end

  defp pop_to_module([], _target), do: :not_found

  defp pop_to_module([{module, socket} | rest], target) do
    if module == target do
      {:found, module, socket, rest}
    else
      pop_to_module(rest, target)
    end
  end

  defp clear_nav_action(socket) do
    Dala.Socket.put_dala(socket, :nav_action, nil)
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp decode_notification_json(json) when is_binary(json) do
    case :json.decode(json) do
      map when is_map(map) ->
        source =
          case Map.get(map, "source", "local") do
            "push" -> :push
            _ -> :local
          end

        data =
          case Map.get(map, "data") do
            d when is_map(d) ->
              Map.new(d, fn {k, v} -> {to_atom_safe(k), v} end)

            _ ->
              %{}
          end

        %{
          id: Map.get(map, "id"),
          title: Map.get(map, "title"),
          body: Map.get(map, "body"),
          data: data,
          source: source
        }

      _ ->
        %{source: :local, data: %{}}
    end
  end

  # ── Render pipeline ───────────────────────────────────────────────────────

  defp do_render(module, socket, transition \\ :none) do
    platform = socket.__dala__.platform
    list_renderers = Map.get(socket.__dala__, :list_renderers, %{})
    socket = ensure_safe_area(socket)

    # Skip render if nothing changed (except for navigation)
    changed = socket.__dala__.changed
    has_changes = MapSet.size(changed) > 0
    is_navigation = transition != :none

    if has_changes or is_navigation do
      {tree, active_component_keys} =
        module.render(socket.assigns)
        |> Dala.Ui.List.expand(list_renderers, self(), socket.assigns)
        |> Dala.Ui.NativeView.expand(self(), platform)

      Dala.Ui.NativeView.Registry.reconcile(self(), active_component_keys)

      # Get previous tree from socket metadata
      old_tree = Dala.Socket.get_dala(socket, :last_tree)

      # Use patch-based rendering — pass the map tree directly to avoid
      # the intermediate Dala.Node struct allocation. The diff engine
      # handles both maps and structs.
      {:ok, _patches} =
        Dala.Renderer.render_patches(
          old_tree,
          tree,
          platform,
          Dala.Platform.Native,
          transition
        )

      # Store the new tree for next diff — convert to Node only once,
      # after we know the render succeeded.
      new_node = Dala.Node.from_map(tree, "root")
      socket = Dala.Socket.put_dala(socket, :last_tree, new_node)
      socket = Dala.Socket.clear_changed(socket)
      Dala.Socket.put_root_view(socket, :rendered)
    else
      # Nothing changed, keep existing UI but still clear the changed set
      # so the next render doesn't incorrectly think something changed
      socket = Dala.Socket.clear_changed(socket)
      socket
    end
  end

  @doc """
  Ensure the socket has a `:safe_area` assign populated.

  On iOS, reads the safe area insets from the platform NIF.
  On Android and in test mode, sets all insets to 0.0.

  If the socket already has a `:safe_area` assign, returns it unchanged.
  """
  @spec ensure_safe_area(Dala.Socket.t()) :: Dala.Socket.t()
  def ensure_safe_area(socket) do
    if Map.has_key?(socket.assigns, :safe_area) do
      socket
    else
      platform = socket.__dala__.platform
      safe_area = safe_area_for_platform(platform)
      Dala.Socket.assign(socket, :safe_area, safe_area)
    end
  end

  @doc """
  Return safe area insets for the given platform.

  iOS: reads from the platform NIF.
  Other: returns zeroed insets.

  Useful for testing and for code that needs safe area values without a socket.
  """
  @spec safe_area_for_platform(atom()) :: map()
  def safe_area_for_platform(:ios) do
    {t, r, b, l} = Dala.Platform.Native.safe_area()
    %{top: t, right: r, bottom: b, left: l}
  end

  def safe_area_for_platform(_) do
    %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0}
  end
end
