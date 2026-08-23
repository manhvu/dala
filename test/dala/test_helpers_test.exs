defmodule Dala.TestHelpersTest do
  @moduledoc """
  Pure helper functions of `Dala.Test` — no device or node required.
  """

  use ExUnit.Case, async: true

  alias Dala.Test

  describe "flatten_tree/1" do
    test "flattens a nested view tree into indexed paths" do
      tree = %{
        type: :window,
        children: [
          %{type: :label, label: "A", children: []},
          %{
            type: :column,
            children: [
              %{type: :button, label: "B", children: []}
            ]
          }
        ]
      }

      flat = Test.flatten_tree(tree)
      paths = Enum.map(flat, &elem(&1, 0))

      assert [] in paths
      assert [0] in paths
      assert [1] in paths
      assert [1, 0] in paths
    end

    test "strips the children key from flattened nodes but keeps everything else" do
      tree = %{type: :x, value: "v", children: [%{type: :y, children: []}]}

      [{[], root}, {[0], child}] = Test.flatten_tree(tree)

      refute Map.has_key?(root, :children)
      assert root.value == "v"
      assert child.type == :y
    end

    test "handles childless leaves and non-map input" do
      assert [{[], %{type: :leaf}}] = Test.flatten_tree(%{type: :leaf})
      assert :not_a_tree = Test.flatten_tree(:not_a_tree)
    end
  end

  describe "find_view/2 on a captured tree via flatten" do
    test "matches by label substring" do
      tree = %{
        children: [
          %{label: "Roll Dice", children: []},
          %{value: "reroll", children: []},
          %{label: "Settings", children: []}
        ]
      }

      matches =
        tree
        |> Test.flatten_tree()
        |> Enum.filter(fn {_path, node} ->
          String.contains?(to_string(node[:label] || ""), "oll") or
            String.contains?(to_string(node[:value] || ""), "oll")
        end)

      assert length(matches) == 2
    end
  end
end
