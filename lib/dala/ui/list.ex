defmodule Dala.Ui.List do
  @moduledoc """
  Data-driven list component.

  A `type: :list` node in your render tree is shorthand for a scrollable list
  backed by Elixir data. Dala expands it into a `lazy_list` before rendering,
  wrapping each row in a tappable container.

  ## Basic usage

  The default renderer turns each item into a text row. No setup needed:

      %{
        type:  :list,
        props: %{id: :my_list, items: assigns.names},
        children: []
      }

  Handle selections in `handle_info/2`:

      def handle_info({:select, :my_list, index}, socket) do
        item = Enum.at(socket.assigns.names, index)
        {:noreply, Dala.Socket.assign(socket, :selected, item)}
      end

  ## Custom renderer

  Register a renderer in `mount/3` to control how each item looks:

      def mount(_params, _session, socket) do
        socket =
          socket
          |> Dala.Socket.assign(:items, load_items())
          |> Dala.Ui.List.put_renderer(:my_list, fn %{name: name, subtitle: sub} ->
            %{
              type: :column,
              props: %{padding: 12},
              children: [
                %{type: :text, props: %{text: name,  text_size: :base}, children: []},
                %{type: :text, props: %{text: sub,   text_size: :sm, text_color: :gray_500}, children: []}
              ]
            }
          end)
        {:ok, socket}
      end

  ## Default renderer rules

  When no custom renderer is registered:
  - Binary → text row with the string
  - `%{label: _}` → text row with the label
  - `%{text: _}`  → text row with the text
  - Anything else → `inspect/1` fallback
  """

  @doc """
  Register a custom item renderer for a list.

  `id` must match the `:id` prop on the `type: :list` node.
  `renderer` is a 1-arity function that receives one item and returns a node map.

  Call this from `mount/3` or `handle_info/2` — it is stored in `socket.__dala__`
  and picked up at render time.
  """
  @spec put_renderer(Dala.Socket.t(), atom(), (term() -> map())) :: Dala.Socket.t()
  def put_renderer(socket, id, renderer) when is_atom(id) and is_function(renderer, 1) do
    existing = Map.get(socket.__dala__, :list_renderers, %{})
    Dala.Socket.put_dala(socket, :list_renderers, Map.put(existing, id, renderer))
  end

  @doc """
  The default item renderer. Handles binaries, maps with `:label`/`:text`, and
  falls back to `inspect/1` for anything else.
  """
  @spec default_renderer(term()) :: map()
  def default_renderer(item) when is_binary(item) do
    text_row(item)
  end

  def default_renderer(%{label: label}) do
    text_row(to_string(label))
  end

  def default_renderer(%{text: text}) do
    text_row(to_string(text))
  end

  def default_renderer(item) do
    text_row(inspect(item))
  end

  @doc """
  Walk a render tree and expand all `type: :list` nodes into `lazy_list` nodes.

  Called internally by `Dala.Screen` before passing the tree to `Dala.Ui.Renderer`.
  Accepts a single node or the list of root nodes that `render/1` returns.
  `renderers` is the `list_renderers` map from `socket.__dala__`. `pid` is the
  screen process (used as the tap target for row-select events).
  """
  @spec expand(map() | [map()], map(), pid(), map()) :: map() | [map()]
  def expand(tree, renderers, pid, assigns \\ %{})

  def expand(trees, renderers, pid, assigns) when is_list(trees),
    do:
      Enum.flat_map(
        trees,
        &(expand(&1, renderers, pid, assigns)
          |> List.wrap())
      )

  # DSL `if`/`unless` node — keep only the branch whose condition holds. Its
  # children splice in place of the conditional itself, so expansion may
  # return zero or many siblings for this one input slot.
  def expand(%{type: :conditional} = node, renderers, pid, assigns) do
    condition =
      case Map.get(node, :props, %{}) |> Map.get(:condition) do
        fun when is_function(fun, 1) -> fun.(assigns)
        other -> other
      end

    branch =
      if condition do
        Map.get(node, :then_children, [])
      else
        Map.get(node, :else_children, [])
      end

    Enum.flat_map(branch, fn child ->
      child
      |> expand(renderers, pid, assigns)
      |> List.wrap()
    end)
  end

  def expand(%{type: :list, props: props} = _node, renderers, pid, _assigns) do
    id = Map.fetch!(props, :id)
    items = Map.get(props, :items, [])
    renderer = Map.get(renderers, id, &default_renderer/1)

    children =
      items
      |> Enum.with_index()
      |> Enum.map(fn {item, index} ->
        row = renderer.(item)

        %{
          type: :box,
          props: %{on_tap: {pid, {:list, id, :select, index}}},
          children: [row]
        }
      end)

    # Drop list-specific props; pass through any others (e.g. on_end_reached)
    list_props = Map.drop(props, [:id, :items])
    %{type: :lazy_list, props: list_props, children: children}
  end

  # DSL `for` node — expand into one copy of children per item.
  def expand(
        %{type: :for, props: %{enum: enum, items_fn: items_fn}, children: []} = node,
        renderers,
        pid,
        assigns
      ) do
    parent_id = node[:id] || "for"

    items =
      case enum do
        {:dala_ref, name} -> Map.get(assigns, name, [])
        other when is_function(other, 1) -> other.(assigns) || []
        other when is_list(other) -> other
        _ -> []
      end

    children =
      items
      |> Enum.flat_map(fn item ->
        case Function.info(items_fn, :arity) do
          # Arity 3 receives assigns so deferred defui components inside the
          # loop can resolve their @ref args.
          {:arity, 3} -> items_fn.(parent_id, item, assigns)
          {:arity, 2} -> items_fn.(parent_id, item)
          {:arity, 1} -> items_fn.(item)
          _ -> []
        end
      end)

    # The for-node becomes a plain column; drop its internal enum/items_fn
    # props so they never reach the render protocol.
    expand_children(
      %{
        node
        | type: :column,
          props: Map.delete(node.props, :enum) |> Map.delete(:items_fn),
          children: children
      },
      renderers,
      pid,
      assigns
    )
  end

  # Rebuild via Map.put so extra node keys (e.g. the `:id` set by keyed
  # `for` rows for stable diffing) survive expansion. Conditionals inside
  # children may expand to zero or many siblings, hence flat_map.
  def expand(%{type: _} = node, renderers, pid, assigns) do
    children =
      node
      |> Map.get(:children, [])
      |> Enum.flat_map(fn child ->
        child
        |> expand(renderers, pid, assigns)
        |> List.wrap()
      end)

    Map.put(node, :children, children)
  end

  def expand(node, _renderers, _pid, _assigns), do: node

  defp expand_children(%{children: children} = node, renderers, pid, assigns) do
    expanded =
      Enum.flat_map(children, fn child ->
        child
        |> expand(renderers, pid, assigns)
        |> List.wrap()
      end)

    %{node | children: expanded}
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp text_row(text) do
    %{
      type: :text,
      props: %{text: text, text_size: :base, text_color: :on_surface, padding: 16},
      children: []
    }
  end
end
