defmodule Dala.Spark.Transformers.Render do
  @moduledoc """
  Spark transformer that generates the `render/1` function from DSL entities.

  Walks the entity tree (screen → container children → leaves) and produces
  a `render/1` that builds the same node maps `Dala.Ui.Widgets` functions return:

      %{type: :column, props: %{...}, children: [...]}

  Container entities carry a `:children` field populated by Spark's
  `recursive_as` mechanism. Leaf entities have no children.

  Type mapping is derived dynamically from `Dala.Ui.Component` registry at
  compile time — when a component is added to the registry, the DSL render
  transformer picks it up automatically.
  """

  use Spark.Dsl.Transformer

  # Regex compiled at runtime to avoid OTP 28 compile-time literal issue
  # (AGENTS.md rule #9).
  @at_ref_regex Regex.compile!("@([a-zA-Z_]\\w*)")

  # Struct → type mapping derived from Component registry at compile time.
  @struct_to_type (for {name, comp} <- Dala.Ui.Component.components(), into: %{} do
                     struct_module =
                       Module.concat(Dala.Spark.Dsl, Macro.camelize(Atom.to_string(name)))

                     {struct_module, comp.type}
                   end)

  @impl true
  def transform(dsl_state) do
    entities = Spark.Dsl.Transformer.get_entities(dsl_state, [:screen])
    attributes = Spark.Dsl.Transformer.get_entities(dsl_state, [:attributes])

    warn_undeclared_refs(dsl_state, entities, attributes)

    case entities do
      [] ->
        {:ok, dsl_state}

      screen_entities ->
        render_ast = build_children_ast(screen_entities)

        render_fn =
          quote do
            def render(assigns) do
              unquote(render_ast)
            end
          end

        {:ok, Spark.Dsl.Transformer.eval(dsl_state, [], render_fn)}
    end
  end

  # A typo'd @ref silently renders as "" — compare every ref against the
  # declared attributes (plus framework-provided refs) and warn at compile time.
  @framework_refs MapSet.new([:safe_area])

  defp warn_undeclared_refs(dsl_state, entities, attributes) do
    declared =
      attributes
      |> Enum.map(& &1.name)
      |> MapSet.new()
      |> MapSet.union(@framework_refs)

    module = Spark.Dsl.Transformer.get_persisted(dsl_state, :module)

    entities
    |> collect_refs([])
    |> Enum.reject(&MapSet.member?(declared, &1))
    |> Enum.uniq()
    |> Enum.each(fn {ref, line} ->
      known = Enum.map_join(MapSet.to_list(declared), ", ", &":#{&1}")

      IO.write(
        :standard_error,
        "warning: @#{ref} is not a declared attribute — declare it in `attributes do` " <>
          "or it renders empty. Declared: #{known}\n" <>
          if(module, do: "  #{inspect(module)}:#{line}\n", else: "")
      )
    end)
  end

  defp collect_refs(values, acc) when is_list(values),
    do: Enum.reduce(values, acc, &collect_refs(&1, &2))

  defp collect_refs(entity, acc) when is_map(entity) and not is_struct(entity) do
    line = entity |> Map.get(:__spark_metadata__) |> anno_line()

    entity
    |> Map.drop([:__spark_metadata__])
    |> Map.values()
    |> collect_refs(acc, line)
  end

  defp collect_refs(entity, acc) when is_struct(entity) do
    line = entity |> Map.get(:__spark_metadata__) |> anno_line()

    entity
    |> Map.from_struct()
    |> Map.drop([:__spark_metadata__])
    |> Map.values()
    |> collect_refs(acc, line)
  end

  defp collect_refs(values, acc, line) when is_list(values),
    do: Enum.reduce(values, acc, &collect_refs(&1, &2, line))

  defp collect_refs(value, acc, line) when is_map(value),
    do: value |> Map.to_list() |> collect_refs(acc, line)

  defp collect_refs({:dala_ref, name}, acc, line) when is_atom(name),
    do: [{name, line} | acc]

  defp collect_refs({:loop_ref, _, _} = _marker, acc, _line), do: acc
  defp collect_refs({:loop_ref, _} = _marker, acc, _line), do: acc

  defp collect_refs(value, acc, line) when is_binary(value) do
    matches =
      Regex.scan(@at_ref_regex, value, capture: :all_but_first)
      |> List.flatten()

    Enum.map(matches, &{String.to_atom(&1), line}) ++ acc
  end

  # compute fns are opaque AST here — refs inside them can't be checked
  # statically; skip tuples that aren't our simple markers.
  defp collect_refs(_other, acc, _line), do: acc

  defp anno_line(%{anno: [{:line, line} | _]}) when is_integer(line), do: line
  defp anno_line(%{anno: line}) when is_integer(line), do: line
  defp anno_line(_), do: 0

  # ── AST builders ──────────────────────────────────────────────────────────

  @doc """
  Build quoted AST that evaluates to the list of render nodes for `entities`.

  Public so `Dala.Spark.Dsl.defui/2` can emit local-component functions using
  exactly the same node construction as the generated `render/1`.
  """
  @spec build_nodes_ast([map()]) :: Macro.t()
  def build_nodes_ast([]), do: quote(do: [])

  def build_nodes_ast(entities) when is_list(entities) do
    nodes = Enum.map(entities, &build_node_ast/1)

    quote do
      unquote(nodes)
      |> Enum.flat_map(&List.wrap/1)
    end
  end

  defp build_children_ast([]) do
    quote do: []
  end

  # Each element is either a literal node map, nil (unknown component), or —
  # for `defui` components — a runtime expression returning a list of nodes.
  # List.wrap/1 normalises all three (and drops the nils).
  defp build_children_ast(entities) when is_list(entities) do
    nodes = Enum.map(entities, &build_node_ast/1)
    quote do: Enum.flat_map(unquote(nodes), &List.wrap/1)
  end

  # Unknown components are dropped from the render (verification reports them
  # as compile errors), but the transformer must not crash on the marker.
  defp build_node_ast(%{type: :unknown_component}), do: quote(do: nil)

  # `defui` component — splice the local component function's node list at
  # render time. Args were converted at parse time (refs, loop refs, compute).
  defp build_node_ast(%{type: :component} = entity) do
    name = Map.fetch!(entity, :name)
    args = entity |> Map.get(:args, []) |> Enum.map(&build_value_ast(&1, nil))

    quote do
      apply(__MODULE__, unquote(name), [assigns | unquote(args)])
    end
  end

  defp build_node_ast(%{type: :conditional} = entity) do
    props_ast = build_conditional_props_ast(entity)
    then_ast = build_children_ast(Map.get(entity, :then_children, []))
    else_ast = build_children_ast(Map.get(entity, :else_children, []))

    quote do
      %{
        type: :conditional,
        props: unquote(props_ast),
        children: [],
        then_children: unquote(then_ast),
        else_children: unquote(else_ast)
      }
    end
  end

  defp build_node_ast(%{type: :list_render} = entity) do
    props_ast = build_list_render_props_ast(entity)
    for_args = Map.get(entity, :for_args)

    quote do
      %{
        type: :list_render,
        props: unquote(props_ast),
        children: [],
        for_args: unquote(Macro.escape(for_args))
      }
    end
  end

  # `for item <- @items, id: item.id do ... end` — expands at render time so
  # each row gets a stable id ("<parent>:item-<key>") for keyed diffing.
  # Children are emitted as code inside the per-item closure so `item`
  # (and `@ref`s) resolve naturally. `defui` components inside the loop are
  # baked as `:deferred_component` markers and applied by the closure, which
  # has both the item and the screen assigns.
  defp build_node_ast(%{type: :for} = entity) do
    var = Map.fetch!(entity, :var)
    enum_ast = Map.fetch!(entity, :enum)
    id_expr = Map.get(entity, :id_expr)
    children_entities = Map.get(entity, :children, [])

    child_nodes =
      Enum.map(children_entities, fn
        %{type: :component} = c ->
          # A runtime call can't be evaluated at transform time — defer it.
          # Args stay as plain values; the surrounding Macro.escape handles
          # embedding, and the per-row substitution matches the raw markers.
          # Defui params can't pass through a loop boundary (the row closure
          # has no scope for them), so reject instead of baking garbage.
          args = Map.get(c, :args, [])

          if contains_defui_arg?(args) do
            raise CompileError,
              description:
                "defui parameters cannot cross into `for` blocks — compute the value before the loop or read it from the item"
          end

          %{
            type: :deferred_component,
            name: Map.fetch!(c, :name),
            args: args
          }

        entity ->
          entity
          |> build_node_ast()
          |> case do
            nil ->
              []

            ast ->
              # build_node_ast returns quoted AST; evaluate it to a concrete node map
              {result, _binding} = Code.eval_quoted(ast, assigns: [], var: nil)
              result
          end
      end)
      |> Enum.flat_map(&List.wrap/1)

    escaped_child_nodes = Macro.escape(child_nodes)

    id_key_ast =
      case id_expr do
        {:loop_ref, ^var, field} ->
          quote do: to_string(Map.get(unquote({var, [], nil}), unquote(field), "nil"))

        _ ->
          nil
      end

    row_body =
      quote do
        unquote(escaped_child_nodes)
        |> Enum.flat_map(fn
          # Deferred defui component: substitute markers against the item and
          # assigns, then call it. __MODULE__ is the screen module here.
          %{type: :deferred_component} = deferred ->
            resolved_args =
              Enum.map(
                deferred.args,
                &Dala.Spark.Transformers.Render.substitute_markers(
                  &1,
                  unquote({var, [], nil}),
                  assigns
                )
              )

            apply(__MODULE__, deferred.name, [assigns | resolved_args])
            |> Enum.flat_map(&List.wrap/1)
            |> Enum.map(
              &Dala.Spark.Transformers.Render.resolve_loop_refs(
                &1,
                unquote({var, [], nil}),
                row_id
              )
            )

          child ->
            [
              Dala.Spark.Transformers.Render.resolve_loop_refs(
                child,
                unquote({var, [], nil}),
                row_id
              )
            ]
        end)
      end

    children_fn =
      if id_key_ast do
        quote do
          fn parent_id, unquote({var, [], nil}), assigns ->
            key = unquote(id_key_ast)
            row_id = "#{parent_id}:item-#{key}"
            unquote(row_body)
          end
        end
      else
        quote do
          fn parent_id, unquote({var, [], nil}), assigns ->
            # No user key — fall back to a content-addressed id, which stays
            # stable across renders of the same data.
            row_id = "#{parent_id}:item-#{:erlang.phash2(unquote({var, [], nil}))}"
            unquote(row_body)
          end
        end
      end

    quote do
      %{
        type: :for,
        props: %{enum: unquote(enum_ast), items_fn: unquote(children_fn)},
        children: []
      }
    end
  end

  defp build_node_ast(entity) do
    type = struct_to_type(entity.__struct__)
    props_ast = build_props_ast(entity)
    children = Map.get(entity, :children, [])
    children_ast = build_children_ast(children)

    quote do
      %{type: unquote(type), props: unquote(props_ast), children: unquote(children_ast)}
    end
  end

  # Replace `{:loop_ref, var, field}` markers left by the DSL parser with the
  # actual value from the current loop item. Runs inside the per-item closure.
  @doc false
  def resolve_loop_refs(node, var, row_id) when is_map(node) do
    node
    |> Map.put(:id, row_id)
    |> Map.update(:props, %{}, &resolve_loop_props(&1, var))
    |> Map.update(:children, [], fn children ->
      Enum.map(children, &resolve_loop_refs(&1, var, "#{row_id}:c"))
    end)
  end

  def resolve_loop_refs(other, _var, _row_id), do: other

  # Substitute {:dala_ref}/{:loop_ref} markers — including ones nested inside
  # event tuples like {:toggle_task, task.id} — with runtime values.
  @doc false
  @spec substitute_markers(term(), map(), map()) :: term()
  def substitute_markers({:dala_ref, ref}, _item, assigns), do: Map.get(assigns, ref)

  def substitute_markers({:loop_ref, _marker, field}, item, _assigns) when is_atom(field),
    do: Map.get(item, field)

  def substitute_markers({:loop_ref, _marker}, item, _assigns), do: item

  def substitute_markers({a, b}, item, assigns),
    do: {substitute_markers(a, item, assigns), substitute_markers(b, item, assigns)}

  def substitute_markers({:{}, meta, elems}, item, assigns),
    do: {:{}, meta, Enum.map(elems, &substitute_markers(&1, item, assigns))}

  def substitute_markers(value, item, assigns) when is_list(value),
    do: Enum.map(value, &substitute_markers(&1, item, assigns))

  def substitute_markers(value, item, assigns) when is_map(value) and not is_struct(value) do
    Map.new(value, fn {k, v} ->
      {substitute_markers(k, item, assigns), substitute_markers(v, item, assigns)}
    end)
  end

  def substitute_markers(value, _item, _assigns), do: value

  defp resolve_loop_props(props, var) when is_map(props) do
    Map.new(props, fn {k, v} -> {k, resolve_loop_value(v, var)} end)
  end

  # Deep scan for defui-parameter markers, including ones nested inside event
  # tuples ({:toggle_task, user.id}) and lists/maps.
  defp contains_defui_arg?(value)

  defp contains_defui_arg?({:defui_arg, _}), do: true
  defp contains_defui_arg?({:defui_arg_path, _, _}), do: true

  defp contains_defui_arg?(value) when is_tuple(value) and not is_map(value) do
    value |> Tuple.to_list() |> Enum.any?(&contains_defui_arg?/1)
  end

  defp contains_defui_arg?(value) when is_list(value),
    do: Enum.any?(value, &contains_defui_arg?/1)

  defp contains_defui_arg?(value) when is_map(value),
    do: Enum.any?(Map.values(value), &contains_defui_arg?/1)

  defp contains_defui_arg?(_), do: false

  defp resolve_loop_value({:loop_ref, _marker_var, field}, var) when is_atom(field),
    do: Map.get(var, field)

  defp resolve_loop_value({:loop_ref, _marker_var}, var), do: var

  defp resolve_loop_value({a, b}, var),
    do: {resolve_loop_value(a, var), resolve_loop_value(b, var)}

  defp resolve_loop_value({:{}, meta, elems}, var),
    do: {:{}, meta, Enum.map(elems, &resolve_loop_value(&1, var))}

  defp resolve_loop_value(value, _var) when is_list(value),
    do: Enum.map(value, &resolve_loop_value(&1, nil))

  defp resolve_loop_value(value, _var) when is_map(value) do
    Map.new(value, fn {k, v} ->
      {resolve_loop_value(k, nil), resolve_loop_value(v, nil)}
    end)
  end

  defp resolve_loop_value(value, _var), do: value

  # ── Type mapping (dynamic from Component registry) ─────────────────────────

  defp struct_to_type(struct_module) do
    Map.get_lazy(@struct_to_type, struct_module, fn ->
      struct_module
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
      |> String.to_atom()
    end)
  end

  # ── Props building ────────────────────────────────────────────────────────

  defp build_props_ast(entity) do
    struct_module = entity.__struct__

    fields =
      struct_module.__struct__()
      |> Map.from_struct()
      |> Map.keys()
      |> Enum.filter(&(&1 not in [:__spark_metadata__, :children]))

    pairs =
      fields
      |> Enum.filter(&(Map.get(entity, &1) != nil))
      |> Enum.map(fn field ->
        value = Map.get(entity, field)
        key = field
        val_ast = build_value_ast(value, key)
        {key, val_ast}
      end)

    {:%{}, [], pairs}
  end

  defp build_conditional_props_ast(entity) do
    props = Map.get(entity, :props, %{})
    pairs = Enum.map(props, fn {key, value} -> {key, build_value_ast(value, key)} end)
    {:%{}, [], pairs}
  end

  defp build_list_render_props_ast(entity) do
    props =
      entity
      |> Map.get(:props, %{})
      |> Map.drop([:__spark_metadata__])

    pairs = Enum.map(props, fn {key, value} -> {key, build_value_ast(value, key)} end)
    {:%{}, [], pairs}
  end

  defp build_value_ast(value, _key) when is_binary(value) do
    case process_at_refs_in_string(value) do
      {:literal, literal} -> literal
      {:interpolated, ast} -> ast
    end
  end

  # `@name` attribute ref (converted at DSL-parse time)
  defp build_value_ast({:dala_ref, name}, _key), do: quote(do: assigns[unquote(name)])

  # `item` loop ref — kept as a marker; resolved at expansion time by
  # `resolve_loop_refs/3` inside the per-item closure.
  defp build_value_ast({:loop_ref, _var, _field} = marker, _key), do: Macro.escape(marker)

  defp build_value_ast({:loop_ref, _var} = marker, _key), do: Macro.escape(marker)

  # `compute(fn ... end)` — emitted verbatim, called with assigns at render time.
  # The renderer resolves 1-arity fns in props by calling them with assigns.
  defp build_value_ast(value, _key) when is_function(value, 1),
    do: quote(do: Dala.Ui.Renderer.resolve_prop(unquote(Macro.escape(value)), assigns))

  # Bare defui parameter reference (`text title` inside `defui f(title)`)
  defp build_value_ast({:defui_arg, var}, _key) when is_atom(var),
    do: {var, [], nil}

  # Single-level field access on a defui parameter (`text user.name`)
  defp build_value_ast({:defui_arg_path, var, field}, _key)
       when is_atom(var) and is_atom(field),
       do: quote(do: Map.get(unquote({var, [], nil}), unquote(field)))

  # compute/1 with a do-block arrives as a quoted fn AST — emit it verbatim
  defp build_value_ast({:fn, _, _} = fn_ast, _key),
    do: quote(do: Dala.Ui.Renderer.resolve_prop(unquote(fn_ast), assigns))

  # Tuples (event args like {:toggle_task, task.id}): rebuild element-wise so
  # marker elements resolve through their own clauses and literals escape.
  defp build_value_ast({a, b}, _key) do
    quote do: {unquote(build_value_ast(a, nil)), unquote(build_value_ast(b, nil))}
  end

  defp build_value_ast({:{}, _, elems}, _key) do
    asts = Enum.map(elems, &build_value_ast(&1, nil))
    {:{}, [], asts}
  end

  defp build_value_ast(value, _key) when is_list(value) do
    Enum.map(value, &build_value_ast(&1, nil))
  end

  defp build_value_ast(value, _key) when is_map(value) do
    pairs =
      Enum.map(value, fn {k, v} ->
        {build_value_ast(k, nil), build_value_ast(v, nil)}
      end)

    {:%{}, [], pairs}
  end

  defp build_value_ast(value, _key) do
    Macro.escape(value)
  end

  # ── @ref processing ───────────────────────────────────────────────────────

  defp process_at_refs_in_string(string) do
    matches =
      Regex.scan(@at_ref_regex, string, return: :index)
      |> Enum.map(fn [{start, len}, {key_start, key_len}] ->
        %{
          full_start: start,
          full_end: start + len,
          key_start: key_start,
          key_len: key_len
        }
      end)

    if matches == [] do
      {:literal, Macro.escape(string)}
    else
      parts = build_interpolation_parts(string, matches)
      {:interpolated, parts}
    end
  end

  defp build_interpolation_parts(string, matches) do
    segments =
      matches
      |> Enum.reduce({0, []}, fn match, {offset, acc} ->
        literal_before = binary_part(string, offset, match.full_start - offset)
        key = binary_part(string, match.key_start, match.key_len)
        key_atom = String.to_atom(key)

        acc =
          acc
          |> maybe_add_literal(literal_before)
          |> Kernel.++([quote(do: to_string(assigns[unquote(key_atom)]))])

        {match.full_end, acc}
      end)
      |> then(fn {offset, acc} ->
        trailing = binary_part(string, offset, byte_size(string) - offset)
        maybe_add_literal(acc, trailing)
      end)

    case segments do
      [single] -> single
      multiple -> combine_with_concat(multiple)
    end
  end

  defp maybe_add_literal(acc, ""), do: acc
  defp maybe_add_literal(acc, literal), do: acc ++ [literal]

  defp combine_with_concat([a, b | rest]) do
    base = quote(do: unquote(a) <> unquote(b))

    Enum.reduce(rest, base, fn part, acc ->
      quote(do: unquote(acc) <> unquote(part))
    end)
  end
end
