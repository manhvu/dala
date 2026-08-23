defmodule Dala.Spark.Dsl do
  @moduledoc """
  Spark DSL for declarative Dala screens.

  Defines attributes for screen state and UI component entities that mirror
  `Dala.Ui.Component` one-to-one. All entity structs and definitions are
  auto-generated from the central component registry via `Dala.Spark.Dsl.Entities`.
  Container entities support nested children via Spark's `entities` + `recursive_as`.

  ## Usage

      defmodule MyApp.CounterScreen do
        use Dala.Spark.Dsl

        dala do
          attribute :count, :integer, default: 0

          screen name: :counter do
            column padding: :space_md, gap: :space_sm do
              text "Count: @count", text_size: :xl
              button "Increment", on_tap: :increment
            end
          end
        end

        def handle_event(:increment, _params, socket) do
          {:noreply, Dala.Socket.assign(socket, :count, socket.assigns.count + 1)}
        end
      end
  """

  # ── Attribute section ───────────────────────────────────────────────────

  defmodule Attribute do
    @moduledoc false
    defstruct name: nil, type: nil, default: nil, __spark_metadata__: nil
  end

  @attribute %Spark.Dsl.Entity{
    name: :attribute,
    target: Attribute,
    describe: "Define a screen assign with type and default value",
    args: [:name, :type],
    schema: [
      name: [type: :atom, required: true, doc: "Assign key"],
      type: [
        type: {:one_of, [:integer, :string, :boolean, :float, :atom, :list, :map]},
        required: true,
        doc: "Value type"
      ],
      default: [type: :any, doc: "Default value (nil if omitted)"]
    ]
  }

  @attributes %Spark.Dsl.Section{
    name: :attributes,
    describe: "Declare screen state attributes",
    top_level?: true,
    entities: [@attribute]
  }

  # ── Component entities (auto-generated from Dala.Ui.Component) ──────────
  use Dala.Spark.Dsl.Entities

  # ── Screen section ──────────────────────────────────────────────────────

  @screen %Spark.Dsl.Section{
    name: :screen,
    describe: "Screen definition with UI components",
    top_level?: true,
    schema: [
      name: [type: :atom, doc: "Screen identifier"]
    ],
    entities: @all_entities
  }

  # ── PubSub section (from Dala.Spark.Pubsub) ────────────────────────────

  defmodule PubSubSubscription do
    @moduledoc false
    defstruct topic: nil, on_message: nil, __spark_metadata__: nil
  end

  @pubsub_subscription %Spark.Dsl.Entity{
    name: :subscribe,
    target: PubSubSubscription,
    describe: "Subscribe to a PubSub topic with a message handler",
    args: [:topic],
    schema: [
      topic: [type: :string, required: true, doc: "Topic to subscribe to"],
      on_message: [
        type: :atom,
        required: true,
        doc: "Handler function name to call when message arrives"
      ]
    ]
  }

  @pubsub_section %Spark.Dsl.Section{
    name: :pubsub,
    describe: "Declare PubSub subscriptions for this screen",
    entities: [@pubsub_subscription]
  }

  # ── Extension registration ──────────────────────────────────────────────

  use Spark.Dsl.Extension,
    sections: [@attributes, @screen, @pubsub_section],
    transformers: [
      Dala.Spark.Transformers.GenerateMount,
      Dala.Spark.Transformers.Render,
      Dala.Spark.Transformers.Pubsub
    ],
    verifiers: [__MODULE__.Verifier]

  use Spark.Dsl,
    many_extension_kinds: [:dala],
    default_extensions: [dala: [__MODULE__]]

  # ── Custom screen/2 and attributes/2 macros ────────────────────────────
  # Spark's build_section skips defining section macros for top-level
  # sections (top_level?: true). We define them here manually to support
  # the standard Elixir calling convention: `screen name: :foo do ... end`.

  # Build a lookup map of component name → struct module at compile time
  @component_structs (for {name, _comp} <- Dala.Ui.Component.components(), into: %{} do
                        {name,
                         Module.concat(Dala.Spark.Dsl, Macro.camelize(Atom.to_string(name)))}
                      end)

  @container_components (for {name, comp} <- Dala.Ui.Component.components(),
                             comp.category == :container,
                             into: MapSet.new() do
                           name
                         end)

  # Generate screen/2 that parses the block AST and builds entity structs directly.
  # This bypasses the entity macro modules created by Spark's Module.create,
  # which don't work correctly with require/import.
  defmacro screen(do: block) do
    screen_impl([], block, __CALLER__)
  end

  defmacro screen(opts, do: block) do
    screen_impl(opts, block, __CALLER__)
  end

  defp screen_impl(opts, block, caller_env) do
    caller_module = caller_env.module
    ensure_extensions(caller_module)

    # Validate opts against the screen section schema. `name` is optional —
    # when omitted it is inferred from the module name (MyApp.CounterScreen
    # → :counter) by stripping Screen/View/Page suffixes and snake_casing.
    screen_schema = [name: [type: :atom, doc: "Screen identifier"]]

    case Spark.Options.validate(Keyword.new(opts), screen_schema) do
      {:ok, _vopts} ->
        :ok

      {:error, error} ->
        raise Spark.Error.DslError,
          module: caller_module,
          message: error,
          path: [:screen]
    end

    validated_opts =
      case Keyword.get(opts, :name) do
        nil -> [name: infer_screen_name(caller_module)]
        name -> [name: name]
      end

    # Parse the block AST and build entity structs
    entities = parse_entities(block, caller_module)

    quote do
      # Register this section with Spark DSL state
      current_sections = Process.get({__MODULE__, :spark_sections}, [])

      unless {Dala.Spark.Dsl, [:screen]} in current_sections do
        Process.put({__MODULE__, :spark_sections}, [
          {Dala.Spark.Dsl, [:screen]} | current_sections
        ])
      end

      # Store section opts and entities in DSL state
      current_config =
        Process.get(
          {__MODULE__, :spark, [:screen]},
          Spark.Dsl.Extension.default_section_config()
        )

      Process.put(
        {__MODULE__, :spark, [:screen]},
        %{
          current_config
          | section_anno: nil,
            opts: unquote(Macro.escape(validated_opts)),
            entities: unquote(Macro.escape(entities))
        }
      )

      # Store entities as module attribute for compile-time verification
      Module.put_attribute(__MODULE__, :__dala_dsl__, true)
      Module.put_attribute(__MODULE__, :__dala_dsl_entities__, unquote(Macro.escape(entities)))

      Module.put_attribute(
        __MODULE__,
        :__dala_dsl_screen_name,
        unquote(Macro.escape(validated_opts))[:name]
      )

      # Persist DSL info for runtime access (used by Dala.Spark.Dsl.verify/1)
      @persist {:dala_dsl_entities, unquote(Macro.escape(entities))}
      @persist {:dala_dsl_screen_name, unquote(Macro.escape(validated_opts))[:name]}
    end
  end

  # Generate attributes/2 that parses the block AST and builds attribute structs.
  defmacro attributes(do: block) do
    caller_module = __CALLER__.module
    ensure_extensions(caller_module)

    # Parse the block AST and build attribute structs
    attributes = parse_attributes(block, caller_module)

    quote do
      # Register this section with Spark DSL state
      current_sections = Process.get({__MODULE__, :spark_sections}, [])

      unless {Dala.Spark.Dsl, [:attributes]} in current_sections do
        Process.put({__MODULE__, :spark_sections}, [
          {Dala.Spark.Dsl, [:attributes]} | current_sections
        ])
      end

      # Store attributes in DSL state
      current_config =
        Process.get(
          {__MODULE__, :spark, [:attributes]},
          Spark.Dsl.Extension.default_section_config()
        )

      Process.put(
        {__MODULE__, :spark, [:attributes]},
        %{
          current_config
          | section_anno: nil,
            entities: unquote(Macro.escape(attributes))
        }
      )

      # Store attributes as module attribute for compile-time verification
      Module.put_attribute(
        __MODULE__,
        :__dala_dsl_attributes__,
        unquote(Macro.escape(attributes))
      )

      # Persist DSL info for runtime access (used by Dala.Spark.Dsl.verify/1)
      @persist {:dala_dsl_attributes, unquote(Macro.escape(attributes))}
    end
  end

  # ── AST parsing for entity blocks ───────────────────────────────────────

  defp parse_entities(block_ast, caller_module) do
    calls = extract_calls_from_block(block_ast)
    Enum.flat_map(calls, &parse_entity_call(&1, caller_module, nil))
  end

  # MyApp.CounterScreen → :counter (strips Screen/View/Page suffixes).
  defp infer_screen_name(module) when is_atom(module) do
    module
    |> Module.split()
    |> List.last()
    |> strip_screen_suffix()
    |> Macro.underscore()
    |> String.to_atom()
  end

  defp strip_screen_suffix(name) do
    Enum.reduce(["Screen", "View", "Page"], name, fn suffix, acc ->
      String.replace_suffix(acc, suffix, "")
    end)
    |> case do
      "" -> "screen"
      stripped -> stripped
    end
  end

  defp extract_calls_from_block({:__block__, _, calls}), do: calls
  defp extract_calls_from_block(call) when is_tuple(call), do: [call]
  defp extract_calls_from_block(_), do: []

  defp parse_entity_call(
         {:if, meta, [condition, [do: then_block, else: else_block]]},
         caller_module,
         loop_var
       ) do
    converted = convert_condition_value(condition, loop_var, meta)

    then_children =
      Enum.flat_map(
        extract_calls_from_block(then_block),
        &parse_entity_call(&1, caller_module, loop_var)
      )

    else_children =
      Enum.flat_map(
        extract_calls_from_block(else_block),
        &parse_entity_call(&1, caller_module, loop_var)
      )

    [
      %{
        type: :conditional,
        props: %{condition: converted},
        children: [],
        then_children: then_children,
        else_children: else_children,
        __spark_metadata__: %Spark.Dsl.Entity.Meta{anno: meta, properties_anno: %{}}
      }
    ]
  end

  defp parse_entity_call({:if, meta, [condition, [do: then_block]]}, caller_module, loop_var) do
    converted = convert_condition_value(condition, loop_var, meta)

    then_children =
      Enum.flat_map(
        extract_calls_from_block(then_block),
        &parse_entity_call(&1, caller_module, loop_var)
      )

    [
      %{
        type: :conditional,
        props: %{condition: converted},
        children: [],
        then_children: then_children,
        else_children: [],
        __spark_metadata__: %Spark.Dsl.Entity.Meta{anno: meta, properties_anno: %{}}
      }
    ]
  end

  # `unless c do X end` is a conditional with the branches swapped — no
  # negation AST injection, so the condition stays a plain expression.
  defp parse_entity_call({:unless, meta, [condition, [do: then_block]]}, caller_module, loop_var) do
    converted = convert_condition_value(condition, loop_var, meta)

    else_children =
      Enum.flat_map(
        extract_calls_from_block(then_block),
        &parse_entity_call(&1, caller_module, loop_var)
      )

    [
      %{
        type: :conditional,
        props: %{condition: converted},
        children: [],
        then_children: [],
        else_children: else_children,
        __spark_metadata__: %Spark.Dsl.Entity.Meta{anno: meta, properties_anno: %{}}
      }
    ]
  end

  # `for item <- @items do ... end` — optionally keyed for stable diff
  # identity: `for item <- @items, id: item.id do ... end`
  defp parse_entity_call({:for, meta, args}, caller_module, _loop_var) do
    case args do
      [{:<-, _, [{var, _, _}, enum_ast]} | rest] when is_atom(var) ->
        {kw, block_ast} = split_for_args(rest)

        children =
          block_ast
          |> extract_calls_from_block()
          |> Enum.flat_map(&parse_entity_call(&1, caller_module, var))

        [
          %{
            type: :for,
            var: var,
            enum: convert_value(enum_ast, var),
            id_expr:
              case Keyword.get(kw, :id) do
                nil -> nil
                expr -> convert_value(expr, var)
              end,
            children: children,
            __spark_metadata__: %Spark.Dsl.Entity.Meta{anno: meta, properties_anno: %{}}
          }
        ]

      _ ->
        []
    end
  end

  defp parse_entity_call({name, meta, args}, caller_module, loop_var) when is_atom(name) do
    component_name = name

    if Map.has_key?(@component_structs, component_name) do
      {children, opts, _block_ast} = extract_children_and_opts(args, component_name)
      struct_module = Map.get(@component_structs, component_name)
      is_container = MapSet.member?(@container_components, component_name)

      parsed_children =
        if is_container and children != [] do
          container_comp = Dala.Ui.Component.get(component_name)

          Enum.each(
            children,
            &reject_prop_call!(&1, component_name, container_comp, caller_module)
          )

          Enum.flat_map(children, &parse_entity_call(&1, caller_module, loop_var))
        else
          []
        end

      entity =
        build_entity_struct(struct_module, component_name, opts, parsed_children, meta, loop_var)

      [entity]
    else
      cond do
        # Local component defined with defui — emit a deferred call node that
        # the transformer turns into a runtime `apply(__MODULE__, ...)` splice.
        defui_defined?(caller_module, name, args) ->
          validate_defui_call!(caller_module, name, args, meta)

          [
            %{
              type: :component,
              name: name,
              args: Enum.map(args, &convert_value(&1, loop_var)),
              props: %{},
              children: [],
              __spark_metadata__: %Spark.Dsl.Entity.Meta{anno: meta, properties_anno: %{}}
            }
          ]

        true ->
          # Unknown component — keep a marker so verification reports it instead
          # of silently dropping it (and the whole subtree) from the render.
          [
            %{
              type: :unknown_component,
              name: component_name,
              props: %{},
              children: [],
              __spark_metadata__: %Spark.Dsl.Entity.Meta{anno: meta, properties_anno: %{}}
            }
          ]
      end
    end
  end

  defp parse_entity_call(_, _, _), do: []

  # The old "prop call" style (`column do gap :space_sm end`) reads like a
  # child but names a prop of the enclosing container — fail with a hint that
  # points at keyword args instead of a misleading "Unknown component :gap".
  defp reject_prop_call!({name, meta, _args}, container_name, comp, caller_module)
       when is_atom(name) and name not in [:if, :unless, :for] do
    cond do
      Map.has_key?(@component_structs, name) ->
        :ok

      defui_defined?(caller_module, name, []) ->
        :ok

      name in comp.props ->
        raise CompileError,
          line: ast_line(meta),
          description:
            ":#{name} is a prop of #{inspect(container_name)}, not a child component — " <>
              "pass it as a keyword argument: #{container_name} #{name}: value do ... end"

      true ->
        :ok
    end
  end

  defp reject_prop_call!(_, _, _, _), do: :ok

  # Conditions support attribute refs (@name), plain literals and compute
  # functions — anything else would previously be baked as escaped AST data
  # that evaluated truthy forever, silently picking the wrong branch.
  defp convert_condition_value(condition, loop_var, meta) do
    value = convert_value(condition, loop_var)
    validate_condition!(value, meta)
    value
  end

  defp validate_condition!({tag, _}, _) when tag in [:dala_ref, :loop_ref], do: :ok
  defp validate_condition!({form, _, _}, _) when form in [:fn, :&], do: :ok
  defp validate_condition!(v, _) when is_function(v, 0) or is_function(v, 1), do: :ok

  defp validate_condition!(v, _)
       when is_atom(v) or is_binary(v) or is_number(v) or is_boolean(v) or is_nil(v),
       do: :ok

  defp validate_condition!(list, meta) when is_list(list),
    do: Enum.each(list, &validate_condition!(&1, meta))

  defp validate_condition!(value, meta) do
    raise CompileError,
      line: ast_line(meta),
      description:
        "unsupported condition expression #{Macro.to_string(value)} — use an attribute " <>
          "(@name), a plain literal, or compute(fn assigns -> ... end)"
  end

  defp split_for_args(rest) do
    case List.last(rest) do
      [do: block_ast] ->
        kw = rest |> List.delete(do: block_ast) |> List.flatten()
        {kw, block_ast}

      _ ->
        {[], nil}
    end
  end

  # Extract children (do block) and opts from the macro call arguments.
  # The args AST depends on how the component was called:
  #   text("Hello")               → args = ["Hello"]
  #   text "Hello"                → args = ["Hello"]
  #   text "Hello", text_size: :xl → args = ["Hello", text_size: :xl]
  #   column padding: :md do ... end → args = [padding: :md, do: block]
  #   divider()                   → args = []
  defp extract_children_and_opts(args, component_name) do
    comp = Dala.Ui.Component.get(component_name)
    is_container = MapSet.member?(@container_components, component_name)

    if is_container do
      {opts, block_ast} = extract_container_args(args)
      children = extract_children_from_block(block_ast)
      {children, opts, block_ast}
    else
      # Leaf components are called with positional args + optional keyword opts
      # e.g., text("Hello") or text "Hello", text_size: :xl
      {positional, opts} = extract_leaf_args(args, comp)
      {[], positional ++ opts, nil}
    end
  end

  defp extract_leaf_args(args, comp) do
    # For leaf components, the first prop is the primary content (e.g., text for text component)
    # If the first arg is a string/binary, it goes to the first prop
    case args do
      [first | rest] when is_binary(first) ->
        opts = List.flatten(rest)
        {[{first_prop(comp), first}], opts}

      list when is_list(list) ->
        {[], List.flatten(list)}

      _ ->
        {[], []}
    end
  end

  defp first_prop(%{props: [first | _]}), do: first
  defp first_prop(_), do: :text

  # Extract opts and block from container component args.
  # Container components are called as:
  #   column padding: :md, gap: :sm do ... end
  # Which produces AST args like:
  #   [[padding: :md, gap: :sm], [do: block_ast]]
  # Or with explicit parentheses:
  #   column(padding: :md) do ... end
  #   args = [padding: :md, do: block_ast]
  defp extract_container_args(args) when is_list(args) do
    # Check if the last element is a [do: block] keyword list
    case List.last(args) do
      [do: block_ast] ->
        # Args are like [[opts...], [do: block]]
        # The first element is the opts list
        opts =
          case List.first(args) do
            opts_list when is_list(opts_list) -> opts_list
            _ -> []
          end

        {opts, block_ast}

      _ ->
        # Args might be like [opts..., do: block] (single flat list)
        case Keyword.pop(args, :do) do
          {nil, _} -> {args, nil}
          {block_ast, opts} -> {opts, block_ast}
        end
    end
  end

  defp extract_container_args(_), do: {[], nil}

  defp extract_children_from_block(nil), do: []
  defp extract_children_from_block({:__block__, _, children}) when is_list(children), do: children
  defp extract_children_from_block(call) when is_tuple(call), do: [call]
  defp extract_children_from_block(_), do: []

  defp build_entity_struct(struct_module, component_name, opts, children, meta, loop_var) do
    comp = Dala.Ui.Component.get(component_name)
    opts = opts |> List.wrap() |> Enum.reject(&match?({:do, _}, &1))

    validate_prop_keys!(component_name, comp, opts, meta)

    field_values =
      Enum.reduce(opts, %{}, fn
        {key, value}, acc when is_atom(key) ->
          Map.put(acc, key, convert_value(value, loop_var))

        value, acc when is_binary(value) ->
          Map.put(acc, first_prop(comp), convert_value(value, loop_var))

        value, acc when is_atom(value) ->
          Map.put(acc, first_prop(comp), convert_value(value, loop_var))

        value, acc ->
          Map.put(acc, first_prop(comp), convert_value(value, loop_var))
      end)

    # Add children if present
    field_values =
      if children != [] do
        Map.put(field_values, :children, children)
      else
        field_values
      end

    # Add spark metadata
    field_values =
      Map.put(field_values, :__spark_metadata__, %Spark.Dsl.Entity.Meta{
        anno: meta,
        properties_anno: %{}
      })

    struct(struct_module, field_values)
  end

  # struct/2 silently drops keys that aren't struct fields, so a typo'd prop
  # would vanish from the rendered UI without a trace. Validate against the
  # registry BEFORE building the struct — broken screens fail the build.
  defp validate_prop_keys!(component_name, comp, opts, meta) do
    Enum.each(opts, fn
      {key, _value} when is_atom(key) ->
        unless key in comp.props do
          suggestion = Dala.Spark.DslVerifier.closest_match(key, comp.props)
          hint = if suggestion, do: " Did you mean :#{suggestion}?", else: ""

          shown = Enum.take(comp.props, 10)
          valid = Enum.map_join(shown, ", ", &":#{&1}")
          suffix = if length(comp.props) > 10, do: "…", else: ""

          raise CompileError,
            line: ast_line(meta),
            description:
              "unknown prop :#{key} on #{inspect(component_name)}.#{hint} " <>
                "Valid props: #{valid}#{suffix}"
        end

      _ ->
        :ok
    end)
  end

  # Convert prop values at DSL-parse time:
  # - `@name` attribute refs become `{:dala_ref, :name}` markers
  # - `item.field` inside `for` becomes `{:loop_ref, :item, :field}`
  # - `compute(fn ... end)` is kept as-is (emitted verbatim by the transformer)
  @ref_marker :dala_ref

  defp convert_value({:@, _, [{name, _, nil}]}, _loop_var) when is_atom(name),
    do: {@ref_marker, name}

  # defui parameter reference (`title` inside `defui card_header(title)`) —
  # pre-rewritten by scope_defui_args/2 before parsing.
  defp convert_value({:__dala_arg__, _meta, [var]}, _loop_var) when is_atom(var),
    do: {:defui_arg, var}

  # Single-level field access on a defui parameter (`text user.name`).
  defp convert_value({{:., _, [{:__dala_arg__, _meta, [var]}, field]}, _, []}, _loop_var)
       when is_atom(var) and is_atom(field),
       do: {:defui_arg_path, var, field}

  defp convert_value({:compute, _, [[do: fn_ast]]}, _loop_var), do: fn_ast

  defp convert_value({:compute, _, [fn_ast]}, _loop_var)
       when is_function(fn_ast, 1) or (is_tuple(fn_ast) and elem(fn_ast, 0) == :fn),
       do: fn_ast

  defp convert_value({{:., _, [{var, _, nil}, field]}, _, []} = _ast, loop_var)
       when is_atom(field) and is_atom(var) and var == loop_var,
       do: {:loop_ref, var, field}

  # `item.field` where `item` isn't the loop variable in scope — either used
  # outside a for block entirely or referencing an outer loop's variable.
  # Both silently baked raw AST before, producing garbage props downstream.
  defp convert_value({{:., _, [{var, meta, nil}, _field]}, _, []} = _ast, nil)
       when is_atom(var) do
    raise CompileError,
      line: ast_line(meta),
      description:
        "`#{var}.<field>` uses a loop variable outside of a `for` block — reference an attribute with @name instead"
  end

  defp convert_value({{:., _, [{var, meta, nil}, _field]}, _, []} = _ast, loop_var)
       when is_atom(var) and var != loop_var do
    raise CompileError,
      line: ast_line(meta),
      description:
        "loop variable `#{var}` is not in scope here — only `#{loop_var}` is (nested loops don't capture outer variables)"
  end

  # Bare loop variable (`text item` inside `for item <- @items`) — resolves to
  # the whole item at expansion time.
  defp convert_value({var, _meta, nil}, loop_var)
       when is_atom(loop_var) and loop_var != nil and var == loop_var,
       do: {:loop_ref, var}

  # A bare variable that isn't the loop variable (or there is no loop at all).
  defp convert_value({var, meta, ctx}, nil)
       when is_atom(var) and is_atom(ctx) and var != nil do
    raise CompileError,
      line: ast_line(meta),
      description:
        "variable `#{var}` is not in scope inside a screen block — reference an attribute with @#{var}"
  end

  # Event tuples ({:toggle_task, task.id}) and other literal tuples: convert
  # elements so refs/loop vars/defui params inside them become markers too.
  # Placed after the marker-producing clauses so markers pass through.
  defp convert_value({a, b}, loop_var),
    do: {convert_value(a, loop_var), convert_value(b, loop_var)}

  defp convert_value({:{}, meta, elems}, loop_var),
    do: {:{}, meta, Enum.map(elems, &convert_value(&1, loop_var))}

  defp convert_value(value, loop_var) when is_list(value),
    do: Enum.map(value, &convert_value(&1, loop_var))

  defp convert_value(value, loop_var) when is_map(value) do
    Map.new(value, fn {k, v} -> {convert_value(k, loop_var), convert_value(v, loop_var)} end)
  end

  defp convert_value(value, _loop_var), do: value

  # ── AST parsing for attribute blocks ────────────────────────────────────

  defp parse_attributes(block_ast, caller_module) do
    calls = extract_calls_from_block(block_ast)
    Enum.flat_map(calls, &parse_attribute_call(&1, caller_module))
  end

  defp parse_attribute_call({:attribute, meta, args}, _caller_module) when length(args) >= 2 do
    [name, type] = Enum.take(args, 2)

    default =
      case Enum.at(args, 2) do
        nil -> nil
        [default: value] -> value
        value -> value
      end

    [
      %Attribute{
        name: name,
        type: type,
        default: default,
        __spark_metadata__: %Spark.Dsl.Entity.Meta{anno: meta, properties_anno: %{}}
      }
    ]
  end

  defp parse_attribute_call(_, _), do: []

  # ── defui — local component composition ───────────────────────────────────

  @doc """
  Define a reusable local UI fragment inside a screen module.

      defui card_header(title) do
        row gap: :space_sm do
          text title, variant: :title
          spacer()
        end
      end

      screen name: :settings do
        column do
          card_header("Settings")
          text "Body"
        end
      end

  The body is parsed with the same rules as a `screen` block: `@ref`s,
  `compute(fn assigns -> ... end)` and `for` loops all work. `@ref`s resolve
  against the *caller's* assigns at render time. The function must be defined
  above its first use in the screen block (the parser resolves call sites at
  compile time). Event handlers referenced inside a `defui` body are not seen
  by compile-time handler verification.
  """
  defmacro defui(header, do: block) do
    caller_module = __CALLER__.module

    {name, args} =
      case header do
        {:^, _, _} ->
          raise ArgumentError, "defui names must be plain identifiers"

        {name, _meta, args} when is_atom(name) ->
          args = List.wrap(args || [])
          {name, args}

        other ->
          raise ArgumentError, "invalid defui header: #{Macro.to_string(other)}"
      end

    arg_vars =
      Enum.map(args, fn
        {var, _meta, nil} when is_atom(var) ->
          {var, [], nil}

        other ->
          raise ArgumentError,
                "defui arguments must be plain variables, got: #{Macro.to_string(other)}"
      end)

    ensure_extensions(caller_module)

    arg_names = MapSet.new(Enum.map(arg_vars, &elem(&1, 0)))

    entities =
      block
      |> scope_defui_args(arg_names)
      |> parse_entities(caller_module)

    nodes_ast = Dala.Spark.Transformers.Render.build_nodes_ast(entities)

    # Register for call-site resolution. The screen block may be re-expanded
    # by Spark after module attributes are consumed, so the registry lives in
    # the compiler process dictionary (same pattern as spark_sections).
    entry = {name, length(arg_vars)}
    existing = Process.get({caller_module, :dala_defui}, [])
    Process.put({caller_module, :dala_defui}, [entry | List.delete(existing, entry)])

    quote do
      @doc false
      def unquote(name)(assigns, unquote_splicing(arg_vars)) do
        unquote(nodes_ast)
      end
    end
  end

  # defui calls are positional-only: reject wrong arity, do-blocks and keyword
  # options at compile time instead of a confusing runtime failure.
  defp validate_defui_call!(caller_module, name, args, meta) do
    expected = defui_arity(caller_module, name)

    cond do
      is_nil(expected) ->
        :ok

      length(args) != expected ->
        raise CompileError,
          line: ast_line(meta),
          description:
            "#{inspect(caller_module)}.#{name}/#{expected + 1} called with #{length(args)} argument(s)"

      Enum.any?(args, &block_or_opts_arg?/1) ->
        raise CompileError,
          line: ast_line(meta),
          description:
            "defui component #{name} takes positional arguments only — no do-blocks or keyword options"

      true ->
        :ok
    end
  end

  defp block_or_opts_arg?(arg) when is_list(arg), do: Keyword.keyword?(arg)
  defp block_or_opts_arg?(_), do: false

  defp defui_arity(caller_module, name) do
    Enum.find_value(Process.get({caller_module, :dala_defui}, []), fn
      {^name, nargs} -> nargs
      _ -> nil
    end)
  end

  defp ast_line([{:line, line} | _]) when is_integer(line), do: line
  defp ast_line(meta) when is_integer(meta), do: meta
  defp ast_line(_), do: 0

  # Rewrite bare references to defui parameters (`text title`) into marker
  # calls BEFORE parsing, so convert_value turns them into {:defui_arg, var}
  # markers and the transformer emits the parameter reference instead of
  # baking raw parse-time AST.
  defp scope_defui_args(ast, args) do
    Macro.prewalk(ast, fn
      {var, meta, ctx} = node when is_atom(var) and is_atom(ctx) ->
        if var in MapSet.to_list(args), do: {:__dala_arg__, meta, [var]}, else: node

      node ->
        node
    end)
  end

  defp defui_defined?(caller_module, name, _args)
       when is_atom(caller_module) and caller_module != nil,
       do: defui_arity(caller_module, name) != nil

  defp defui_defined?(nil, _name, _args), do: false

  # ── __using__ macro for external consumers ──────────────────────────────

  defmacro __using__(_opts) do
    quote do
      require Dala.Spark.Dsl
      import Dala.Spark.Dsl

      use Spark.Dsl,
        many_extension_kinds: [:extensions],
        default_extensions: [extensions: [Dala.Spark.Dsl]]

      # Spark registers @before_compile twice (its own `use` plus ours below).
      # The second run expands generated code that reads @opts inside function
      # bodies — and Elixir clears non-persist attributes after such a read,
      # producing "undefined module attribute @opts" on every compile. Making
      # :opts persistent keeps both runs working.
      dala_opts = Module.get_attribute(__MODULE__, :opts)

      Module.register_attribute(__MODULE__, :opts, persist: true)
      Module.put_attribute(__MODULE__, :opts, dala_opts)

      @extensions [Dala.Spark.Dsl]
      @before_compile Spark.Dsl
      @before_compile Dala.Spark.DslCompileHook
      @after_verify {__MODULE__, :__dala_after_verify__}
      @spark_parent Dala.Spark.Dsl
      Module.register_attribute(__MODULE__, :persist, accumulate: true)
      @persist {:module, __MODULE__}
      @persist {:file, __ENV__.file}
      @persist {:extensions, [Dala.Spark.Dsl]}
      Module.register_attribute(__MODULE__, :__dala_dsl_entities__,
        accumulate: false,
        persist: true
      )

      Module.register_attribute(__MODULE__, :__dala_dsl_attributes__,
        accumulate: false,
        persist: true
      )

      Module.register_attribute(__MODULE__, :__dala_dsl__, accumulate: false, persist: true)

      Module.register_attribute(__MODULE__, :__dala_dsl_screen_name,
        accumulate: false,
        persist: true
      )

      @doc false
      def __spark_dsl__ do
        persisted = persisted() || %{}
        entities = Map.get(persisted, :dala_dsl_entities, [])
        attributes = Map.get(persisted, :dala_dsl_attributes, [])
        screen_name = Map.get(persisted, :dala_dsl_screen_name)

        # Gather defined handle_event handlers
        handlers =
          case __MODULE__.__info__(:functions)[:handle_event] do
            nil ->
              []

            arity when arity == 3 ->
              # We can't easily get clause patterns, so return empty
              # The mix task will do deeper analysis
              []
          end

        %{
          screen_name: screen_name,
          entities: entities,
          attributes: attributes,
          handlers: handlers
        }
      end

      @doc false
      def __dala_after_verify__(module) do
        # Beam debug_info is available here (unlike mid-compile), so missing
        # and unused handle_event clauses can be checked on every `mix compile`.
        for w <- Dala.Spark.DslVerifier.handler_warnings(module) do
          file = module.__info__(:compile)[:source] |> List.to_string()
          line = if w.line > 0, do: w.line, else: 1

          IO.write(:standard_error, "warning: #{w.message}\n  #{file}:#{line}\n")
        end

        :ok
      end
    end
  end

  # Public helper to ensure @extensions is set on a module.
  def ensure_extensions(module) do
    case Module.get_attribute(module, :extensions) do
      nil ->
        Module.put_attribute(module, :extensions, [__MODULE__])

      _ ->
        :ok
    end
  end

  @doc """
  Verify the DSL definitions of a screen module.

  Returns a list of warnings and errors found in the module's DSL.

      Dala.Spark.Dsl.verify(MyApp.HomeScreen)
      # => [%{type: :warning, module: MyApp.HomeScreen, line: 12, message: "..."}]

  See `Dala.Spark.DslVerifier` for detailed verification logic.
  """
  @spec verify(module()) :: [Dala.Spark.DslVerifier.warning()]
  def verify(module) do
    Dala.Spark.DslVerifier.verify_module(module)
  end

  # ── Verifier ────────────────────────────────────────────────────────────

  defmodule Verifier do
    @moduledoc """
    Compile-time validation for Dala Spark DSL.

    Checks:
    - All event handler props reference atoms
    - Attribute types are valid
    """

    use Spark.Dsl.Verifier

    @event_props [
      :on_tap,
      :on_long_press,
      :on_double_tap,
      :on_swipe,
      :on_swipe_left,
      :on_swipe_right,
      :on_swipe_up,
      :on_swipe_down,
      :on_press,
      :on_change,
      :on_toggle,
      :on_focus,
      :on_blur,
      :on_submit,
      :on_compose,
      :on_refresh,
      :on_end_reached,
      :on_scroll,
      :on_dismiss,
      :on_tab_select,
      :on_select,
      :on_action,
      :on_remove,
      :on_leading,
      :on_page_change,
      :on_error,
      :on_load
    ]

    @valid_attr_types [:integer, :string, :boolean, :float, :atom, :list, :map]

    @impl true
    def verify(dsl_state) do
      attr_errors = verify_attributes(dsl_state)
      entity_errors = verify_entities(dsl_state)

      case attr_errors ++ entity_errors do
        [] -> :ok
        msgs -> {:error, Enum.join(msgs, ";")}
      end
    end

    defp verify_attributes(dsl_state) do
      attributes = Spark.Dsl.Transformer.get_entities(dsl_state, [:attributes])

      Enum.flat_map(attributes, fn attr ->
        type = Map.get(attr, :type)

        if type in @valid_attr_types do
          []
        else
          ["attribute #{inspect(Map.get(attr, :name))} has invalid type: #{inspect(type)}"]
        end
      end)
    end

    defp verify_entities(dsl_state) do
      screen_entities = Spark.Dsl.Transformer.get_entities(dsl_state, [:screen])
      Enum.flat_map(screen_entities, &verify_entity/1)
    end

    defp verify_entity(%{type: :conditional} = entity) do
      then_children = Map.get(entity, :then_children, [])
      else_children = Map.get(entity, :else_children, [])
      Enum.flat_map(then_children ++ else_children, &verify_entity/1)
    end

    defp verify_entity(%{type: :list_render} = entity) do
      children = Map.get(entity, :children, [])
      Enum.flat_map(children, &verify_entity/1)
    end

    defp verify_entity(entity) do
      own_errors =
        Enum.flat_map(@event_props, fn prop ->
          case Map.get(entity, prop) do
            nil ->
              []

            value when is_atom(value) ->
              []

            value ->
              [
                "#{entity.__struct__ |> Module.split() |> List.last()}.#{prop} must be an atom, got: #{inspect(value)}"
              ]
          end
        end)

      child_errors =
        case Map.get(entity, :children) do
          nil -> []
          children -> Enum.flat_map(children, &verify_entity/1)
        end

      own_errors ++ child_errors
    end
  end

  # ── dala/1 macro ────────────────────────────────────────────────────────

  # ── dala/1 macro (deprecated) ───────────────────────────────────────────

  @doc """
  Legacy wrapper block — deprecated, kept for backward compatibility.

  Write the sections flat at the module top level instead:

      attributes do
        attribute :count, :integer, default: 0
      end

      screen name: :counter do
        text "Count: @count"
      end
  """
  defmacro dala(do: block) do
    caller_module = __CALLER__.module
    ensure_extensions(caller_module)

    calls = extract_calls_from_block(block)

    {attributes, rest} =
      Enum.split_with(calls, fn
        {:attribute, _, _} -> true
        _ -> false
      end)

    attributes = Enum.flat_map(attributes, &parse_attribute_call(&1, caller_module))

    screen_calls =
      case extract_calls_from_block({:__block__, [], rest}) do
        [] ->
          []

        screens ->
          screens
      end

    quote do
      unquote(
        Enum.map(screen_calls, fn call ->
          case call do
            {:screen, _, _} ->
              quote do: unquote(call)

            other ->
              other
          end
        end)
      )

      Module.put_attribute(
        __MODULE__,
        :__dala_dsl_attributes__,
        unquote(Macro.escape(attributes))
      )

      current_sections = Process.get({__MODULE__, :spark_sections}, [])

      unless {Dala.Spark.Dsl, [:attributes]} in current_sections do
        Process.put({__MODULE__, :spark_sections}, [
          {Dala.Spark.Dsl, [:attributes]} | current_sections
        ])
      end

      current_config =
        Process.get(
          {__MODULE__, :spark, [:attributes]},
          Spark.Dsl.Extension.default_section_config()
        )

      Process.put(
        {__MODULE__, :spark, [:attributes]},
        %{
          current_config
          | section_anno: nil,
            entities: unquote(Macro.escape(attributes))
        }
      )

      @persist {:dala_dsl_attributes, unquote(Macro.escape(attributes))}
    end
  end
end
