defmodule Dala.Spark.DslMatrixTest do
  use ExUnit.Case, async: false

  @moduledoc """
  Compiles a screen exercising every registered component: every leaf at top
  level, every leaf inside every container, and one nested container pair.

  Generated from `Dala.Ui.Component` metadata so newly added components are
  swept automatically. Guards against a component becoming un-parseable in
  some container context (each pair has its own generated Spark entity).
  """

  @leaves Dala.Ui.Component.leaf_components() |> Keyword.keys() |> Enum.sort()
  @containers Dala.Ui.Component.container_components() |> Keyword.keys() |> Enum.sort()

  test "every leaf parses inside every container" do
    mod = compile_matrix_screen()

    entities = mod.__spark_dsl__().entities

    container_entities =
      Enum.filter(entities, fn entity ->
        name = entity.__struct__ |> Module.split() |> List.last() |> Macro.underscore()
        String.to_atom(name) in @containers
      end)

    assert length(container_entities) >= length(@containers)

    names =
      Enum.map(container_entities, fn entity ->
        entity.__struct__
        |> Module.split()
        |> List.last()
        |> Macro.underscore()
        |> String.to_atom()
      end)

    assert Enum.sort(Enum.uniq(names)) == Enum.sort(@containers),
           "every container should appear as a top-level block"

    for entity <- container_entities do
      name = entity.__struct__ |> Module.split() |> List.last() |> Macro.underscore()

      assert length(entity.children) == length(@leaves),
             "container #{name} should contain all #{length(@leaves)} leaves"

      child_types =
        entity.children
        |> Enum.map(&(&1.__struct__ |> Module.split() |> List.last() |> Macro.underscore()))
        |> Enum.uniq()
        |> Enum.sort()

      assert child_types == Enum.map(@leaves, &Atom.to_string/1) |> Enum.sort(),
             "container #{name} children mismatch"
    end
  end

  test "generated screen exposes the expected screen name" do
    mod = compile_matrix_screen()

    assert :dsl_matrix = mod.__spark_dsl__().screen_name
  end

  test "pubsub section generates handle_info forwarding to the handler" do
    source = """
    defmodule Dala.Spark.DslMatrixTest.PubsubScreen do
      use Dala.Spark.Dsl

      dala do
        pubsub do
          subscribe "matrix:topic", on_message: :handle_matrix_message
        end

        screen name: :pubsub_matrix do
          column do
            text "hello"
          end
        end
      end

      def handle_matrix_message(_msg, socket), do: {:noreply, socket}
    end
    """

    [{mod, _beam}] = Code.compile_string(source, "dala_spark_dsl_matrix_pubsub.ex")

    # The transformer wires subscriptions into handle_info/2
    assert {:noreply, :sentinel_socket} == mod.handle_info({:chat, "hi"}, :sentinel_socket)
  end

  test "containers nest inside containers (recursive_as)" do
    source = """
    defmodule Dala.Spark.DslMatrixTest.NestedScreen do
      use Dala.Spark.Dsl

      screen name: :nested do
        column do
          row do
            text()
          end
        end
      end
    end
    """

    [{mod, _beam}] = Code.compile_string(source, "dala_spark_dsl_matrix_nested.ex")

    [column] =
      Enum.filter(mod.__spark_dsl__().entities, fn e ->
        e.__struct__ == Dala.Spark.Dsl.Column
      end)

    [row] = column.children
    assert row.__struct__ == Dala.Spark.Dsl.Row
    assert [%{__struct__: Dala.Spark.Dsl.Text}] = row.children
  end

  # ── Generation ──────────────────────────────────────────────────────────────

  defp compile_matrix_screen do
    body =
      Enum.map_join(@containers, "\n", fn container ->
        """
        #{container} do
        #{Enum.map_join(@leaves, "\n", &"  #{&1}()")}
        end
        """
      end)

    source = """
    defmodule Dala.Spark.DslMatrixTest.GeneratedScreen do
      use Dala.Spark.Dsl

      screen name: :dsl_matrix do
      #{body}
      end
    end
    """

    case Code.compile_string(source, "dala_spark_dsl_matrix.ex") do
      [{mod, _beam}] -> mod
      other -> raise "matrix screen failed to compile: #{inspect(other)}"
    end
  end
end
