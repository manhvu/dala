defmodule Dala.Spark.Transformers.RenderTest do
  @moduledoc """
  Direct unit tests for the public AST builder used by both `render/1`
  generation and `defui` local components.
  """

  use ExUnit.Case, async: false

  alias Dala.Spark.Transformers.Render

  # build_value_ast emits `assigns` hygienically (context-bound to Render).
  # Strip the context so Code.eval_quoted accepts a normal binding.
  defp eval(ast) do
    ast =
      Macro.prewalk(ast, fn
        {var, meta, Dala.Spark.Transformers.Render} -> {var, meta, nil}
        node -> node
      end)

    Code.eval_quoted(ast, assigns: %{count: 7}) |> elem(0)
  end

  describe "build_nodes_ast/1" do
    test "empty entity list evaluates to an empty node list" do
      assert eval(Render.build_nodes_ast([])) == []
    end

    test "literal props survive evaluation unchanged" do
      text = %Dala.Spark.Dsl.Text{text: "hello"}
      nodes = eval(Render.build_nodes_ast([text]))

      assert [%{type: :text, props: %{text: "hello"}, children: []}] = nodes
    end

    test "@ref markers become assigns lookups" do
      text = %Dala.Spark.Dsl.Text{text: {:dala_ref, :count}}
      # The marker compiles to a hygienic `assigns` reference — inspect the
      # emitted source rather than evaluating (hygiene blocks direct binding).
      src = Render.build_nodes_ast([text]) |> Macro.to_string()
      assert src =~ "assigns[:count]"
    end

    test "unknown_component markers evaluate to nil and are dropped" do
      marker = %{
        type: :unknown_component,
        name: :colum,
        props: %{},
        children: [],
        __spark_metadata__: %Spark.Dsl.Entity.Meta{anno: [], properties_anno: %{}}
      }

      assert eval(Render.build_nodes_ast([marker])) == []
    end

    test ":list_render entities pass their props through (minus metadata)" do
      entity = %{
        type: :list_render,
        props: %{id: :items, __spark_metadata__: :leak},
        children: [],
        for_args: [var: :item]
      }

      [node] = eval(Render.build_nodes_ast([entity]))

      assert node.type == :list_render
      assert node.props == %{id: :items}
      refute Map.has_key?(node.props, :__spark_metadata__)
    end

    test "conditional entities carry then/else branches" do
      cond_entity = %{
        type: :conditional,
        props: %{condition: true},
        children: [],
        then_children: [%Dala.Spark.Dsl.Text{text: "then!"}],
        else_children: [],
        __spark_metadata__: %Spark.Dsl.Entity.Meta{anno: [], properties_anno: %{}}
      }

      [node] = eval(Render.build_nodes_ast([cond_entity]))

      assert node.type == :conditional
      assert [%{props: %{text: "then!"}}] = node.then_children
      assert node.else_children == []
    end
  end

  describe "Dala.Spark.Dsl.verify/1" do
    test "delegates to the verifier and returns warnings" do
      warnings = Dala.Spark.Dsl.verify(Dala.TestSupport.VerifierFixtureScreen)

      # The fixture intentionally has an unused (:dead_handler) and a missing
      # (:reset_missing) handler — verify/1 surfaces them as diagnostics.
      assert Enum.any?(warnings, &(&1.type == :warning))
      assert Enum.any?(warnings, &(&1.type == :info))
    end

    test "returns a not-a-screen warning for non-DSL modules" do
      warnings = Dala.Spark.Dsl.verify(String)
      assert Enum.any?(warnings, &String.contains?(&1.message, "does not appear"))
    end
  end
end
