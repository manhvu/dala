defmodule Mix.Tasks.Dala.Verify do
  @shortdoc "Verify Dala DSL definitions and project configuration"

  @moduledoc """
  Verifies Dala DSL definitions in the current project and reports any issues.

  ## Usage

      mix dala.verify              # Run all verifications
      mix dala.verify --dsl        # Verify DSL definitions only
      mix dala.verify --components # List all available components
      mix dala.verify --strict     # Exit with error code on warnings

  ## What it checks

  When `--dala.verify --dsl` is used, the following checks are performed:

  - **Unknown component types** — component atoms not in the registry
  - **Invalid prop names** — props not accepted by the component (with typo suggestions)
  - **Event handler types** — event handler props that are not atoms or {pid, tag} tuples
  - **Leaf with children** — children placed inside leaf components
  - **Invalid attribute types** — attribute types not in the valid set
  - **Missing handlers** — event handlers referenced in UI but no handle_event/3 clause
  - **Invalid variants** — invalid variant values on text components

  ## Examples

      mix dala.verify --dsl
      mix dala.verify --dsl --strict
      mix dala.verify --components
  """

  use Mix.Task

  @switches [
    dsl: :boolean,
    components: :boolean,
    strict: :boolean,
    markdown_output: :string
  ]

  @impl Mix.Task
  def run(argv) do
    # OptionParser strict mode only accepts hyphenated flags; the documented
    # underscore spelling was silently dropped as invalid.
    argv =
      Enum.map(argv, fn
        "--markdown_output" -> "--markdown-output"
        arg -> arg
      end)

    {opts, _rest, _invalid} = OptionParser.parse(argv, strict: @switches)

    cond do
      opts[:components] && opts[:markdown_output] ->
        list_components_markdown(opts[:markdown_output])

      opts[:components] ->
        list_components()

      opts[:dsl] ->
        verify_dsl(opts)

      true ->
        verify_all(opts)
    end
  end

  # ── DSL verification ────────────────────────────────────────────────────────

  defp verify_dsl(opts) do
    Mix.shell().info("\n🔍 Verifying Dala DSL definitions...\n")

    modules = find_dala_screens()

    if modules == [] do
      Mix.shell().info("  No Dala screen modules found in the current project.")
      Mix.shell().info("  Make sure your screens use `Dala.Screen` or `Dala.Spark.Dsl`.")
    else
      all_warnings =
        Enum.flat_map(modules, fn module ->
          Mix.shell().info("  Checking #{inspect(module)}...")
          Dala.Spark.DslVerifier.verify_module(module)
        end)

      report(all_warnings, opts)
    end
  end

  # ── All verification ────────────────────────────────────────────────────────

  defp verify_all(opts) do
    Mix.shell().info("\n🔍 Running all Dala verifications...\n")

    dsl_warnings =
      case find_dala_screens() do
        [] ->
          Mix.shell().info("  No Dala screen modules found.")
          []

        modules ->
          Enum.flat_map(modules, &Dala.Spark.DslVerifier.verify_module/1)
      end

    report(dsl_warnings, opts)
  end

  # ── Report ───────────────────────────────────────────────────────────────────

  defp report([], _opts) do
    Mix.shell().info("\n  ✓ All DSL definitions look correct. No issues found.\n")
  end

  defp report(warnings, opts) do
    errors = Enum.filter(warnings, &(&1.type == :error))
    warns = Enum.filter(warnings, &(&1.type == :warning))

    Dala.Spark.DslVerifier.print_warnings(warnings)

    Mix.shell().info("\n#{Dala.Spark.DslVerifier.format_report(warnings)}")

    strict? = Keyword.get(opts, :strict, false)

    if strict? and (errors != [] or warns != []) do
      Mix.raise(
        "DSL verification failed with #{length(errors)} error(s) and #{length(warns)} warning(s)"
      )
    end

    if errors != [] do
      exit({:shutdown, 1})
    end
  end

  # ── Component listing ───────────────────────────────────────────────────────

  defp list_components do
    components = Dala.Ui.Component.all()
    leaf_count = Enum.count(components, fn {_, c} -> c.category == :leaf end)
    container_count = Enum.count(components, fn {_, c} -> c.category == :container end)

    Mix.shell().info("""

    ╔══════════════════════════════════════════════════════════════╗
    ║           Dala UI Component Registry                         ║
    ║           #{leaf_count} leaf + #{container_count} container = #{length(components)} total components                    ║
    ╚══════════════════════════════════════════════════════════════╝
    """)

    Mix.shell().info("  Container components:")

    components
    |> Enum.filter(fn {_, c} -> c.category == :container end)
    |> Enum.sort_by(fn {name, _} -> name end)
    |> Enum.each(fn {name, comp} ->
      props = Enum.take(comp.props, 5) |> Enum.map_join(", ", &"#{&1}")
      extra = if length(comp.props) > 5, do: "...", else: ""
      Mix.shell().info("    :#{name} — #{comp.doc} (#{props}#{extra})")
    end)

    Mix.shell().info("\n  Leaf components:")

    components
    |> Enum.filter(fn {_, c} -> c.category == :leaf end)
    |> Enum.sort_by(fn {name, _} -> name end)
    |> Enum.each(fn {name, comp} ->
      props = Enum.take(comp.props, 5) |> Enum.map_join(", ", &"#{&1}")
      extra = if length(comp.props) > 5, do: "...", else: ""
      Mix.shell().info("    :#{name} — #{comp.doc} (#{props}#{extra})")
    end)

    Mix.shell().info("")
  end

  # ── Markdown component reference (generated from the registry) ──────────────

  defp list_components_markdown(path) do
    components = Dala.Ui.Component.all()

    sections =
      [:container, :leaf]
      |> Enum.map_join("\n", fn category ->
        title = if category == :container, do: "Containers", else: "Leaves"

        body =
          components
          |> Enum.filter(fn {_, c} -> c.category == category end)
          |> Enum.sort_by(fn {name, _} -> name end)
          |> Enum.map_join("\n\n", fn {name, comp} -> component_section(name, comp) end)

        "## #{title}\n\n#{body}"
      end)

    doc = """
    <!-- Generated by `mix dala.verify --components --format markdown`. Do not edit by hand. -->

    # Dala UI Component Reference

    #{length(components)} components, generated from `Dala.Ui.Component` (the single source of truth).

    #{sections}
    """

    File.write!(path, doc)
    Mix.shell().info("✓ Wrote #{path} (#{length(components)} components)")
  end

  defp component_section(name, comp) do
    usage =
      case comp.examples do
        [example | _] -> example
        [] -> ":#{name}"
      end

    rows =
      comp.props
      |> Enum.map_join("\n", fn prop ->
        default = Map.get(comp.defaults, prop)
        default_cell = if default == nil, do: "", else: " (default: `#{inspect(default)}`)"
        "| `#{prop}` |#{default_cell} |"
      end)

    """
    ### `#{name}`

    #{comp.doc}

    ```dala
    #{usage}
    ```

    | Prop | Notes |
    |------|-------|
    #{rows}
    """
  end

  # ── Screen module discovery ──────────────────────────────────────────────────

  defp find_dala_screens do
    # Find all loaded modules that use Dala.Spark.Dsl
    :code.all_loaded()
    |> Enum.map(fn {mod, _} -> mod end)
    |> Enum.filter(fn mod ->
      Code.ensure_loaded?(mod) and
        function_exported?(mod, :__spark_dsl__, 0)
    end)
    |> Enum.sort()
  end
end
