defmodule Dala.ListTest do
  use ExUnit.Case, async: true
  import Dala.List

  @moduledoc """
  Tests for Dala.List module.
  """

  describe "expand/2" do
    test "expands list items into children" do
      list = %{
        type: :list,
        props: %{id: :my_list, items: [1, 2, 3]},
        items: [1, 2, 3],
        item: fn i ->
          %{
            type: :text,
            props: %{text: "Item #{i}"},
            children: []
          }
        end
      }

      result = expand(list, %{}, self())

      assert result.type == :lazy_list
      assert length(result.children) == 3
    end

    test "handles empty list" do
      list = %{
        type: :list,
        props: %{id: :empty_list, items: []},
        items: [],
        item: fn _ ->
          %{type: :text, props: %{}, children: []}
        end
      }

      result = expand(list, %{}, self())
      assert result.type == :lazy_list
      assert result.children == []
    end
  end

  describe "expand/3 with renderers" do
    test "uses custom renderers" do
      list = %{
        type: :list,
        props: %{id: :custom_list, items: ["A", "B"]},
        items: ["A", "B"],
        item: fn item ->
          %{
            type: :text,
            props: %{text: item},
            children: []
          }
        end
      }

      renderers = %{
        :custom_list => fn item ->
          %{
            type: :button,
            props: %{text: "Btn: #{item}"},
            children: []
          }
        end
      }

      result = expand(list, renderers, self())
      assert result.type == :lazy_list
      assert length(result.children) == 2
    end
  end

  describe "facade (Dala.List)" do
    test "put_renderer/3 stores the renderer in socket.__dala__" do
      socket = Dala.Socket.new(SomeScreen)
      renderer = fn item -> %{type: :text, props: %{text: item}, children: []} end

      socket = put_renderer(socket, :items, renderer)

      assert socket.__dala__.list_renderers[:items] == renderer
    end

    test "default_renderer/1 handles binaries, labelled maps, and fallbacks" do
      assert %{props: %{text: "plain"}} = default_renderer("plain")
      assert %{props: %{text: "labelled"}} = default_renderer(%{label: "labelled"})
      assert %{props: %{text: "titled"}} = default_renderer(%{text: "titled"})
      assert %{props: %{text: text}} = default_renderer({:tuple, 1})
      assert text =~ "tuple"
    end
  end
end
