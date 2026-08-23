defmodule Dala.Ui.ListTest do
  use ExUnit.Case, async: false

  describe "expand/4" do
    test "expands each root node when given a list" do
      trees = [
        %{type: :text, props: %{text: "a"}, children: []},
        %{type: :text, props: %{text: "b"}, children: []}
      ]

      assert [%{props: %{text: "a"}}, %{props: %{text: "b"}}] =
               Dala.Ui.List.expand(trees, %{}, self(), %{})
    end

    test ":list nodes become :lazy_list with one tappable row per item" do
      node = %{
        type: :list,
        props: %{id: :todos, items: ["alpha", "beta"], on_end_reached: :more},
        children: []
      }

      expanded = Dala.Ui.List.expand(node, %{}, self(), %{})

      assert expanded.type == :lazy_list
      # list-specific props are dropped, others pass through
      assert expanded.props == %{on_end_reached: :more}
      assert length(expanded.children) == 2

      [row0, row1] = expanded.children
      assert row0.type == :box

      assert row0.props.on_tap == {self(), {:list, :todos, :select, 0}}
      assert row1.props.on_tap == {self(), {:list, :todos, :select, 1}}
    end

    test "default renderer renders items as text rows (inspect for non-strings)" do
      node = %{
        type: :list,
        props: %{id: :things, items: [%{name: "x"}]},
        children: []
      }

      expanded = Dala.Ui.List.expand(node, %{}, self(), %{})
      [only] = expanded.children
      [inner] = only.children
      assert inner.props.text == inspect(%{name: "x"})
    end

    test "custom renderers registered under the list id are used" do
      node = %{
        type: :list,
        props: %{id: :custom, items: [1, 2]},
        children: []
      }

      renderers = %{
        custom: fn item -> %{type: :icon, props: %{name: "n#{item}"}, children: []} end
      }

      expanded = Dala.Ui.List.expand(node, renderers, self(), %{})
      names = Enum.map(expanded.children, fn row -> hd(row.children).props.name end)
      assert names == ["n1", "n2"]
    end

    test "an empty items list produces a lazy_list with no rows" do
      node = %{type: :list, props: %{id: :empty, items: []}, children: []}
      expanded = Dala.Ui.List.expand(node, %{}, self(), %{})
      assert expanded.type == :lazy_list
      assert expanded.children == []
    end

    test "missing :id raises" do
      assert_raise KeyError, fn ->
        Dala.Ui.List.expand(%{type: :list, props: %{}, children: []}, %{}, self(), %{})
      end
    end

    test "default_renderer/1 handles binaries" do
      row = Dala.Ui.List.default_renderer("plain")
      assert %{type: :text, props: %{text: "plain"}} = row
      assert row.props.text_size == :base
      assert row.props.text_color == :on_surface
      assert row.children == []
    end

    test "default_renderer/1 handles :label and :text maps via to_string" do
      assert Dala.Ui.List.default_renderer(%{label: 42}).props.text == "42"
      assert Dala.Ui.List.default_renderer(%{text: :atom_text}).props.text == "atom_text"
    end
  end
end
