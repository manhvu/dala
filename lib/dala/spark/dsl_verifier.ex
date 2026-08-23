defmodule Dala.Spark.DslVerifier do
  @moduledoc """
  Comprehensive DSL verification for Dala screen modules.

  Validates user-defined screens against the component registry and
  reports warnings/errors for:
  - Unknown component types
  - Invalid prop names
  - Missing required props
  - Event handler props that are not atoms
  - Invalid attribute types
  - Missing handle_event/3 for declared event handlers
  - Children placed inside leaf components
  - Invalid variant values
  - Deprecated prop usage
  """

  @type warning :: %{
          type: :error | :warning | :info,
          module: atom(),
          line: non_neg_integer(),
          message: String.t()
        }

  @doc """
  Verify a single screen module's DSL definition.

  Returns a list of warnings/errors found.
  """
  @spec verify_module(module()) :: [warning()]
  def verify_module(module) when is_atom(module) do
    with {:module, _} <- Code.ensure_loaded(module),
         true <- function_exported?(module, :__spark_dsl__, 0) do
      do_verify(module)
    else
      _ ->
        [
          %{
            type: :warning,
            module: module,
            line: 0,
            message:
              "Module #{inspect(module)} does not appear to be a Dala screen (no __spark_dsl__ info)"
          }
        ]
    end
  end

  def verify_module(module) do
    [
      %{
        type: :error,
        module: module,
        line: 0,
        message: "Module #{inspect(module)} is not loaded or does not exist"
      }
    ]
  end

  defp do_verify(module) do
    dsl_info = module.__spark_dsl__()
    entities = Map.get(dsl_info, :entities, [])
    attributes = Map.get(dsl_info, :attributes, [])

    # Clause heads come from the compiled beam. Modules without one (e.g.
    # defmodules inside test files) get :not_available — flagging their
    # handlers as missing would be pure noise.
    handlers =
      if beam_available?(module), do: defined_handlers(module), else: :not_available

    attr_warnings = verify_attributes(module, attributes)
    entity_warnings = verify_entities(module, entities)
    handler_warnings = verify_handlers(module, entities, handlers)

    attr_warnings ++ entity_warnings ++ handler_warnings
  end

  defp beam_available?(module) do
    case :code.which(module) do
      path when is_list(path) -> File.exists?(List.to_string(path))
      _ -> false
    end
  end

  @doc """
  Event names handled by `handle_event/3` clauses in `module`.

  Reads the module's compiled debug_info, so it works for fully-compiled
  modules (runtime verification, `mix dala.verify`). Returns `[]` when the
  beam or debug info is unavailable — e.g. from inside the compile hook,
  where only missing-handler checks are possible.
  """
  @spec defined_handlers(module()) :: [atom()]
  def defined_handlers(module) do
    with path when is_list(path) <- :code.which(module),
         {:ok, bin} <- File.read(List.to_string(path)),
         {:ok, {_m, [abstract_code: {:raw_abstract_v1, forms}]}} <-
           :beam_lib.chunks(bin, [:abstract_code]) do
      forms
      |> Enum.flat_map(fn
        {:function, _anno, :handle_event, 3, clauses} ->
          for {:clause, _a2, [{:atom, _a3, name} | _args], _guards, _body} <- clauses,
              is_atom(name),
              do: name

        _ ->
          []
      end)
      |> Enum.uniq()
    else
      _ -> []
    end
  end

  # ── Attribute verification ──────────────────────────────────────────────────

  defp verify_attributes(module, attributes) do
    valid_types = [:integer, :string, :boolean, :float, :atom, :list, :map]

    Enum.flat_map(attributes, fn attr ->
      name = Map.get(attr, :name, :unknown)
      type = Map.get(attr, :type, nil)
      line = Map.get(attr, :line, 0)

      cond do
        type == nil ->
          [
            %{
              type: :error,
              module: module,
              line: line,
              message: "Attribute :#{name} is missing a type declaration"
            }
          ]

        type not in valid_types ->
          [
            %{
              type: :error,
              module: module,
              line: line,
              message:
                "Attribute :#{name} has invalid type #{inspect(type)}. Valid types: #{Enum.map_join(valid_types, ", ", &inspect/1)}"
            }
          ]

        true ->
          []
      end
    end)
  end

  # ── Entity (component) verification ─────────────────────────────────────────

  defp verify_entities(module, entities) do
    Enum.flat_map(entities, &verify_entity(module, &1))
  end

  # Extract type, props, children, and line from an entity.
  # Entities can be either maps (from raw data verification) or structs (from persisted DSL data).
  defp extract_entity_info(entity) when is_map(entity) do
    case entity do
      %{type: :unknown_component} = marker ->
        line =
          case Map.get(marker, :line) do
            l when is_integer(l) and l > 0 -> l
            _ -> extract_line(marker)
          end

        {:unknown_component, %{name: Map.get(marker, :name)}, [], line}

      %{type: type} when is_atom(type) ->
        # Map-based entity (from raw data verification)
        {type, Map.get(entity, :props, %{}), Map.get(entity, :children, []),
         Map.get(entity, :line, 0)}

      %{__struct__: struct_module} ->
        # DSL struct (e.g., %Dala.Spark.Dsl.Column{...})
        # Extract component type from struct module name. Macro.underscore/1
        # keeps multi-word names intact (TextField → :text_field); a plain
        # downcase would mangle them (:textfield).
        type =
          struct_module
          |> Module.split()
          |> List.last()
          |> Macro.underscore()
          |> String.to_atom()

        props = Map.drop(entity, [:__spark_metadata__, :children, :__struct__])
        children = Map.get(entity, :children, [])
        line = extract_line(entity)
        {type, props, children, line}

      _ ->
        {:unknown, %{}, [], 0}
    end
  end

  defp extract_line(%{__spark_metadata__: %{anno: [{:line, line} | _]}}) when is_integer(line),
    do: line

  defp extract_line(%{__spark_metadata__: %{anno: line}}) when is_integer(line), do: line
  defp extract_line(%{__spark_metadata__: %{line: line}}) when is_integer(line), do: line
  defp extract_line(_), do: 0

  defp verify_entity(module, entity) do
    {type, props, children, line} = extract_entity_info(entity)

    component = Dala.Ui.Component.get(type)

    cond do
      # Pseudo-entities with no registry entry to check. `:component` (defui)
      # bodies are verified where they are parsed, not here.
      type in [:conditional, :list_render, :for, :component] ->
        child_warnings = verify_entities(module, children)

        branch_warnings =
          case entity do
            %{then_children: then_c, else_children: else_c} ->
              verify_entities(module, then_c) ++ verify_entities(module, else_c)

            _ ->
              []
          end

        prop_warnings = []

        prop_warnings ++ child_warnings ++ branch_warnings

      type == :unknown_component ->
        [
          %{
            type: :error,
            module: module,
            line: line,
            message:
              "Unknown component :#{props[:name]}. Run `mix dala.verify --components` to see all available components."
          }
        ]

      component == nil ->
        [
          %{
            type: :error,
            module: module,
            line: line,
            message:
              "Unknown component type :#{type}. Run `mix dala.verify --components` to see all available components."
          }
        ]

      component.category == :leaf and children != [] ->
        [
          %{
            type: :error,
            module: module,
            line: line,
            message:
              "Leaf component :#{type} does not accept children. Remove nested content or use a container component."
          }
        ]

      true ->
        prop_warnings = verify_props(module, type, props, component, line)
        child_warnings = verify_entities(module, children)
        prop_warnings ++ child_warnings
    end
  end

  @event_handler_props [
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

  defp verify_props(module, type, props, component, line) do
    valid_props = component.props

    unknown =
      Enum.flat_map(props, fn
        {key, _value} when is_atom(key) ->
          if key in valid_props or key == :__spark_metadata__ do
            []
          else
            suggestion = find_closest_match(key, valid_props)
            hint = if suggestion, do: " Did you mean :#{suggestion}?", else: ""

            [
              %{
                type: :warning,
                module: module,
                line: line,
                message:
                  "Unknown prop :#{key} on :#{type}.#{hint} Valid props: #{Enum.map_join(Enum.take(valid_props, 8), ", ", &inspect/1)}..."
              }
            ]
          end

        {key, _value} ->
          [
            %{
              type: :warning,
              module: module,
              line: line,
              message:
                "Prop key #{inspect(key)} on :#{type} should be an atom, got: #{inspect(key)}"
            }
          ]
      end)

    event_errors =
      Enum.flat_map(props, fn
        {key, value} when is_atom(key) and key in @event_handler_props ->
          if is_nil(value) or is_atom(value) or match?({_, _}, value) do
            []
          else
            [
              %{
                type: :error,
                module: module,
                line: line,
                message:
                  "Event handler :#{key} on :#{type} must be an atom (e.g. :my_handler) or a {pid, :tag} tuple, got: #{inspect(value)}"
              }
            ]
          end

        _ ->
          []
      end)

    variant_warnings = verify_variant(module, type, props, component, line)

    unknown ++ event_errors ++ variant_warnings
  end

  defp verify_variant(module, :text, props, _component, line) do
    case Map.get(props, :variant) do
      nil ->
        []

      variant when is_atom(variant) ->
        valid = text_variants()

        if variant in valid do
          []
        else
          [
            %{
              type: :warning,
              module: module,
              line: line,
              message:
                "Invalid variant :#{variant} on :text. Valid variants: #{Enum.map_join(valid, ", ", &inspect/1)}"
            }
          ]
        end

      variant ->
        [
          %{
            type: :error,
            module: module,
            line: line,
            message: "Variant on :text must be an atom, got: #{inspect(variant)}"
          }
        ]
    end
  end

  defp verify_variant(_module, _, _, _, _), do: []

  # Valid text variants come straight from the Widgets variant presets so this
  # never drifts from the runtime implementation.
  defp text_variants do
    Dala.Ui.Widgets.variant_presets() |> Map.keys()
  end

  # ── Handler verification ────────────────────────────────────────────────────

  @doc """
  Missing / unused `handle_event` warnings for a compiled module.

  Used by the `@after_verify` hook so a typo'd `on_tap` surfaces during
  `mix compile` instead of as a runtime crash or a manual `mix dala.verify`.
  Returns [] when the module or its beam is unavailable.
  """
  @spec handler_warnings(module()) :: [warning()]
  def handler_warnings(module) do
    with {:module, _} <- Code.ensure_loaded(module),
         true <- function_exported?(module, :__spark_dsl__, 0),
         true <- beam_available?(module) do
      info = module.__spark_dsl__()
      entities = Map.get(info, :entities, [])
      verify_handlers(module, entities, defined_handlers(module))
    else
      _ -> []
    end
  end

  defp verify_handlers(module, entities, defined_handlers)

  # Compile-time hook passes :not_available — handle_event clause heads aren't
  # knowable mid-compilation, so neither missing nor unused checks can run.
  # They run at runtime verification (`mix dala.verify`, verify_module/1).
  defp verify_handlers(_module, _entities, :not_available), do: []

  defp verify_handlers(module, entities, defined_handlers) do
    declared = collect_event_handlers(entities)

    undeclared =
      Enum.filter(declared, fn {handler, _line} ->
        not Enum.any?(defined_handlers, fn
          %{name: name} -> name == handler
          name when is_atom(name) -> name == handler
          _ -> false
        end)
      end)

    missing_warnings =
      Enum.map(undeclared, fn {handler, line} ->
        %{
          type: :warning,
          module: module,
          line: line,
          message:
            "Event handler :#{handler} is referenced in the UI tree but no handle_event(:#{handler}, _, _) clause is defined in #{inspect(module)}"
        }
      end)

    # Inverse check: handlers defined but never referenced from the tree are
    # usually dead code or a typo'd on_tap:
    referenced_names = MapSet.new(declared, fn {h, _} -> h end)

    unused_warnings =
      defined_handlers
      |> Enum.map(fn
        %{name: name} -> name
        name when is_atom(name) -> name
      end)
      |> Enum.reject(&(&1 in referenced_names))
      |> Enum.map(fn handler ->
        %{
          type: :info,
          module: module,
          line: 0,
          message:
            "handle_event(:#{handler}, _, _) is defined in #{inspect(module)} but never referenced from the UI tree"
        }
      end)

    missing_warnings ++ unused_warnings
  end

  defp collect_event_handlers(entities) do
    entities
    |> Enum.flat_map(fn entity ->
      props = entity_props(entity)
      children = entity_children(entity)
      line = entity_line(entity)

      from_props =
        Enum.flat_map(props, fn
          {key, value} when is_atom(key) and key in @event_handler_props ->
            # nil is an atom — unset handler props must not become phantoms.
            case value do
              v when is_atom(v) and not is_nil(v) -> [{v, line}]
              {_, v} when is_atom(v) and not is_nil(v) -> [{v, line}]
              _ -> []
            end

          _ ->
            []
        end)

      from_children = collect_event_handlers(children)
      from_props ++ from_children
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp entity_line(%{line: line}) when is_integer(line) and line > 0, do: line
  defp entity_line(entity), do: extract_line(entity)

  # Struct-based DSL entities carry their props as struct fields (no :props key).
  # Map.drop keeps :__struct__ — leaving it makes the result still a struct,
  # which breaks Enum later.
  defp entity_props(%{__struct__: struct_module} = entity) when is_atom(struct_module),
    do: Map.drop(entity, [:__struct__, :__spark_metadata__, :children])

  defp entity_props(%{props: props}) when is_map(props), do: props
  defp entity_props(_), do: %{}

  defp entity_children(%{children: children}) when is_list(children), do: children
  defp entity_children(_), do: []

  # ── Fuzzy match for typo suggestions ────────────────────────────────────────

  @doc """
  Suggest the closest valid prop for a mistyped key, or nil when nothing is
  close enough. Shared by the runtime verifier and the DSL's parse-time
  prop validation.
  """
  @spec closest_match(atom(), [atom()]) :: atom() | nil
  def closest_match(key, valid_props) do
    key_str = Atom.to_string(key)

    # "weight" vs "font_weight": Jaro alone drops below threshold on big length
    # gaps, but a whole-key substring hit is an unambiguous suggestion.
    substring_hit =
      valid_props
      |> Enum.filter(fn prop ->
        prop_str = Atom.to_string(prop)
        prop_str != key_str and String.contains?(prop_str, key_str)
      end)
      |> Enum.min_by(&byte_size(Atom.to_string(&1)), fn -> nil end)

    if substring_hit do
      substring_hit
    else
      valid_props
      |> Enum.map(fn prop ->
        {prop, String.jaro_distance(key_str, Atom.to_string(prop))}
      end)
      |> Enum.filter(fn {_, distance} -> distance > 0.7 end)
      |> Enum.sort_by(fn {_, distance} -> distance end, :desc)
      |> Enum.max_by(fn {prop, distance} ->
        # Prefer prefix matches ("gsp" → "gap") over pure Jaro distance
        bonus = if String.starts_with?(Atom.to_string(prop), key_str), do: 0.1, else: 0.0
        distance + bonus
      end)
      |> elem(0)
    end
  rescue
    _ -> nil
  end

  defp find_closest_match(key, valid_props), do: closest_match(key, valid_props)

  # ── Raw data verification (for compile-time hook) ──────────────────────────

  @doc """
  Verify DSL from raw entity/attribute/handler data (used by compile-time hook).
  """
  @spec verify_from_raw(module(), [map()], [map()], [map()]) :: [warning()]
  def verify_from_raw(module, entities, attributes, handlers) do
    attr_warnings = verify_attributes(module, attributes)
    entity_warnings = verify_entities(module, entities)
    handler_warnings = verify_handlers(module, entities, handlers)

    attr_warnings ++ entity_warnings ++ handler_warnings
  end

  # ── Formatting ──────────────────────────────────────────────────────────────

  @doc """
  Format a list of warnings into a human-readable report.
  """
  @spec format_report([warning()]) :: String.t()
  def format_report(warnings) do
    errors = Enum.filter(warnings, &(&1.type == :error))
    warns = Enum.filter(warnings, &(&1.type == :warning))
    infos = Enum.filter(warnings, &(&1.type == :info))

    header = """
    ╔══════════════════════════════════════════════════════════════╗
    ║              Dala DSL Verification Report                    ║
    ╚══════════════════════════════════════════════════════════════╝
    """

    summary =
      "\n  Found #{length(errors)} error(s), #{length(warns)} warning(s), #{length(infos)} info message(s)\n"

    sections =
      [
        format_section("Errors", errors, :red),
        format_section("Warnings", warns, :yellow),
        format_section("Info", infos, :blue)
      ]
      |> Enum.reject(&is_nil/1)

    if sections == [] do
      header <> "\n  ✓ No issues found. All DSL definitions look correct.\n"
    else
      header <> summary <> Enum.join(sections, "\n")
    end
  end

  defp format_section(_title, [], _color), do: nil

  defp format_section(title, items, _color) do
    formatted =
      items
      |> Enum.sort_by(&{&1.module, &1.line})
      |> Enum.map(fn w ->
        line_info = if w.line > 0, do: "line #{w.line}", else: ""

        "  [#{String.pad_trailing(title, 7)}] #{inspect(w.module)} #{line_info}\n    → #{w.message}"
      end)
      |> Enum.join("\n")

    "\n  #{String.pad_leading("#{length(items)} #{title}", 30)}\n\n#{formatted}"
  end

  @doc """
  Print warnings to the Mix shell with appropriate coloring.
  """
  @spec print_warnings([warning()]) :: :ok
  def print_warnings(warnings) do
    errors = Enum.filter(warnings, &(&1.type == :error))
    warns = Enum.filter(warnings, &(&1.type == :warning))

    Enum.each(warnings, fn w ->
      prefix =
        case w.type do
          :error -> "  ✗ "
          :warning -> "  ⚠ "
          :info -> "  ℹ "
        end

      line_info = if w.line > 0, do: " (line #{w.line})", else: ""
      Mix.shell().info("#{prefix}#{inspect(w.module)}#{line_info}: #{w.message}")
    end)

    if length(errors) > 0 do
      Mix.shell().error(
        "\n  #{length(errors)} DSL error(s) found. Run `mix dala.verify --dsl` for details."
      )
    end

    if length(warns) > 0 do
      Mix.shell().info("\n  #{warns |> length()} DSL warning(s) found.")
    end

    :ok
  end
end
