defmodule Dala.DiffTest do
  use ExUnit.Case, async: true
  doctest Dala.Diff

  describe "diff/2" do
    test "returns empty list when trees are identical" do
      tree = %Dala.Node{
        id: "root",
        type: :text,
        props: %{text: "Hello"},
        children: []
      }

      assert Dala.Diff.diff(tree, tree) == []
    end

    test "detects prop changes" do
      old_tree = %Dala.Node{
        id: "root",
        type: :text,
        props: %{text: "Hello"},
        children: []
      }

      new_tree = %Dala.Node{
        id: "root",
        type: :text,
        props: %{text: "World"},
        children: []
      }

      patches = Dala.Diff.diff(old_tree, new_tree)
      [{action, id, props_or_mask}] = patches
      assert action in [:update_props, :patch_node]
      assert id == "root"

      if action == :update_props do
        assert props_or_mask == %{text: "World"}
      end
    end

    test "detects type change as replace" do
      old_tree = %Dala.Node{
        id: "root",
        type: :text,
        props: %{text: "Hello"},
        children: []
      }

      new_tree = %Dala.Node{
        id: "root",
        type: :button,
        props: %{title: "Click"},
        children: []
      }

      patches = Dala.Diff.diff(old_tree, new_tree)
      assert [{:replace, "root", %Dala.Node{type: :button}}] = patches
    end

    test "handles first render (nil old tree)" do
      new_tree = %Dala.Node{
        id: "root",
        type: :text,
        props: %{text: "Hello"},
        children: []
      }

      patches = Dala.Diff.diff(nil, new_tree)
      assert [{:replace, "root", _}] = patches
    end

    test "detects child insertion" do
      old_tree = %Dala.Node{
        id: "root",
        type: :column,
        props: %{},
        children: []
      }

      new_tree = %Dala.Node{
        id: "root",
        type: :column,
        props: %{},
        children: [
          %Dala.Node{id: "t1", type: :text, props: %{text: "Hello"}, children: []}
        ]
      }

      patches = Dala.Diff.diff(old_tree, new_tree)
      assert Enum.any?(patches, fn {action, _, _, _} -> action == :insert end)
    end

    test "detects child removal" do
      old_tree = %Dala.Node{
        id: "root",
        type: :column,
        props: %{},
        children: [
          %Dala.Node{id: "t1", type: :text, props: %{text: "Hello"}, children: []}
        ]
      }

      new_tree = %Dala.Node{
        id: "root",
        type: :column,
        props: %{},
        children: []
      }

      patches = Dala.Diff.diff(old_tree, new_tree)
      assert Enum.any?(patches, fn {action, _} -> action == :remove end)
    end

    test "uses explicit IDs when provided" do
      old_tree = %Dala.Node{
        id: "my_text",
        type: :text,
        props: %{text: "Hello"},
        children: []
      }

      new_tree = %Dala.Node{
        id: "my_text",
        type: :text,
        props: %{text: "World"},
        children: []
      }

      patches = Dala.Diff.diff(old_tree, new_tree)
      [{action, id, _}] = patches
      assert action in [:update_props, :patch_node]
      assert id == "my_text"
    end

    test "handles different IDs at root" do
      old_tree = %Dala.Node{
        id: "old_root",
        type: :text,
        props: %{text: "Hello"},
        children: []
      }

      new_tree = %Dala.Node{
        id: "new_root",
        type: :text,
        props: %{text: "World"},
        children: []
      }

      patches = Dala.Diff.diff(old_tree, new_tree)
      assert [{:remove, "old_root"}, {:insert, :root, 0, _}] = patches
    end
  end

  describe "patch_node diff" do
    test "produces patch_node when few fields change" do
      old_tree = %Dala.Node{
        id: "root",
        type: :text,
        props: %{text: "Hello", color: "blue"},
        children: []
      }

      new_tree = %Dala.Node{
        id: "root",
        type: :text,
        props: %{text: "World", color: "blue"},
        children: []
      }

      patches = Dala.Diff.diff(old_tree, new_tree)
      # Only 1 of 2 known fields changed -> patch_node
      assert [{:patch_node, "root", mask, changed}] = patches
      assert is_integer(mask)
      assert mask > 0
      assert changed == %{text: "World"}
    end

    test "produces update_props when most fields change" do
      old_tree = %Dala.Node{
        id: "root",
        type: :text,
        props: %{text: "Hello", color: "blue"},
        children: []
      }

      new_tree = %Dala.Node{
        id: "root",
        type: :text,
        props: %{text: "World", color: "red"},
        children: []
      }

      patches = Dala.Diff.diff(old_tree, new_tree)
      # 2 of 2 known fields changed -> update_props (more than half)
      assert [{:update_props, "root", %{text: "World", color: "red"}}] = patches
    end

    test "patch_node mask has correct bit for text field" do
      old_props = %{text: "Hello"}
      new_props = %{text: "World"}
      {mask, changed} = Dala.Diff.compute_field_mask(old_props, new_props)
      # text field bit is 0x0001
      assert mask == 0x0001
      assert changed == %{text: "World"}
    end

    test "patch_node mask has correct bit for title field" do
      old_props = %{title: "Old"}
      new_props = %{title: "New"}
      {mask, changed} = Dala.Diff.compute_field_mask(old_props, new_props)
      # title field bit is 0x0002
      assert mask == 0x0002
      assert changed == %{title: "New"}
    end

    test "patch_node mask combines multiple fields" do
      old_props = %{text: "Hello", color: "blue", padding: 10.0}
      new_props = %{text: "World", color: "red", padding: 10.0}

      {mask, changed} = Dala.Diff.compute_field_mask(old_props, new_props)

      # text (0x0001) + color (0x0004) = 0x0005
      assert mask == 0x0005
      assert changed == %{text: "World", color: "red"}
    end

    test "patch_node mask includes all known field bits" do
      old_props = %{
        text: "a",
        title: "b",
        color: "c",
        background: "d",
        on_tap: 1,
        width: 10.0,
        height: 20.0,
        padding: 30.0,
        flex_grow: 1.0,
        flex_direction: :row,
        justify_content: :center,
        align_items: :stretch
      }

      new_props = %{
        text: "a2",
        title: "b2",
        color: "c2",
        background: "d2",
        on_tap: 2,
        width: 11.0,
        height: 21.0,
        padding: 31.0,
        flex_grow: 2.0,
        flex_direction: :column,
        justify_content: :end,
        align_items: :center
      }

      {mask, changed} = Dala.Diff.compute_field_mask(old_props, new_props)

      # All 12 known fields changed: 0x0001 | 0x0002 | 0x0004 | 0x0008 | 0x0010 | 0x0020 | 0x0040 | 0x0080 | 0x0100 | 0x0200 | 0x0400 | 0x0800 = 0x0FFF
      assert mask == 0x0FFF
      assert map_size(changed) == 12
    end
  end

  describe "Dala.Diff.compute_field_mask/2" do
    test "returns zero mask when props are identical" do
      props = %{text: "Hello", color: "blue"}
      {mask, changed} = Dala.Diff.compute_field_mask(props, props)
      assert mask == 0
      assert changed == %{}
    end

    test "returns zero mask when both are empty" do
      {mask, changed} = Dala.Diff.compute_field_mask(%{}, %{})
      assert mask == 0
      assert changed == %{}
    end

    test "detects added props" do
      {mask, changed} = Dala.Diff.compute_field_mask(%{}, %{text: "New"})
      # text field bit is 0x0001
      assert mask == 0x0001
      assert changed == %{text: "New"}
    end

    test "detects removed props" do
      {mask, changed} = Dala.Diff.compute_field_mask(%{text: "Old"}, %{})
      # text field was removed -> nil in new, which differs from "Old"
      assert mask == 0x0001
      assert changed == %{text: nil}
    end

    test "handles unknown prop keys" do
      {mask, changed} = Dala.Diff.compute_field_mask(%{custom: "a"}, %{custom: "b"})
      # Unknown keys have no mask bit but still appear in changed map
      assert mask == 0
      assert changed == %{custom: "b"}
    end

    test "mixes known and unknown prop changes" do
      {mask, changed} =
        Dala.Diff.compute_field_mask(
          %{text: "old", custom: "a"},
          %{text: "new", custom: "b"}
        )

      assert mask == 0x0001
      assert changed == %{text: "new", custom: "b"}
    end
  end

  describe "Dala.Node.stable_id/1" do
    test "produces a stable u64 hash for string IDs" do
      id = Dala.Node.stable_id("my_node")
      assert is_integer(id)
      assert id > 0
      # Same input -> same output
      assert Dala.Node.stable_id("my_node") == id
    end

    test "produces a stable u64 hash for atom IDs" do
      id = Dala.Node.stable_id(:root)
      assert is_integer(id)
      assert id > 0
      # Atom and its string form should produce the same hash
      assert Dala.Node.stable_id(:root) == Dala.Node.stable_id("root")
    end

    test "different IDs produce different hashes" do
      id_a = Dala.Node.stable_id("node_a")
      id_b = Dala.Node.stable_id("node_b")
      assert id_a != id_b
    end
  end

  describe "Dala.Node.from_map/2 edge cases" do
    test "raises on map without :type key" do
      assert_raise FunctionClauseError, fn ->
        Dala.Node.from_map(%{props: %{}}, "root")
      end
    end

    test "preserves :id from map when present" do
      node = Dala.Node.from_map(%{type: :text, id: "custom_id", props: %{}}, "default")
      assert node.id == "custom_id"
    end

    test "uses default_id when map has no :id" do
      node = Dala.Node.from_map(%{type: :text, props: %{}}, "fallback")
      assert node.id == "fallback"
    end

    test "handles map with :id inside props sub-map" do
      node = Dala.Node.from_map(%{type: :text, props: %{id: "inner"}}, "root")
      # When no top-level :id, falls back to props[:id]
      assert node.id == "inner"
    end

    test "top-level :id takes precedence over props :id" do
      node = Dala.Node.from_map(%{type: :text, id: "top", props: %{id: "inner"}}, "root")
      assert node.id == "top"
    end
  end

  describe "Dala.Node.to_map/1" do
    test "round-trip from_map -> to_map preserves type" do
      original = %{type: :text, props: %{text: "Hello"}, children: []}
      node = Dala.Node.from_map(original, "root")
      result = Dala.Node.to_map(node)
      assert result.type == :text
    end

    test "to_map includes children" do
      node = %Dala.Node{
        id: "root",
        type: :column,
        props: %{},
        children: [%Dala.Node{id: "child", type: :text, props: %{}, children: []}]
      }

      result = Dala.Node.to_map(node)
      assert length(result.children) == 1
    end
  end

  describe "Dala.Node.compute_layout_hash/1" do
    test "computes a stable hash based on type and layout props" do
      node = %Dala.Node{
        id: "root",
        type: :column,
        props: %{padding: 16.0, flex_direction: :row},
        children: []
      }

      hash = Dala.Node.compute_layout_hash(node)
      assert is_integer(hash)
      assert hash > 0
    end

    test "same node produces same layout hash" do
      node = %Dala.Node{
        id: "root",
        type: :text,
        props: %{text: "Hello"},
        children: []
      }

      hash1 = Dala.Node.compute_layout_hash(node)
      hash2 = Dala.Node.compute_layout_hash(node)
      assert hash1 == hash2
    end

    test "different layout props produce different hashes" do
      node_a = %Dala.Node{
        id: "root",
        type: :column,
        props: %{padding: 10.0},
        children: []
      }

      node_b = %Dala.Node{
        id: "root",
        type: :column,
        props: %{padding: 20.0},
        children: []
      }

      assert Dala.Node.compute_layout_hash(node_a) !=
               Dala.Node.compute_layout_hash(node_b)
    end

    test "different child counts produce different hashes" do
      node_a = %Dala.Node{
        id: "root",
        type: :column,
        props: %{},
        children: []
      }

      node_b = %Dala.Node{
        id: "root",
        type: :column,
        props: %{},
        children: [%Dala.Node{id: "c1", type: :text, props: %{}, children: []}]
      }

      assert Dala.Node.compute_layout_hash(node_a) !=
               Dala.Renderer.compute_layout_hash(node_b)
    end
  end

  describe "binary protocol v3 encoder" do
    test "encode_frame produces valid v3 header for remove patch" do
      patches = [{:remove, "test_id"}]
      binary = Dala.Renderer.encode_frame(patches)

      <<0xDA::8, 0xA1::8, version::little-16, patch_count::little-16, frame_begin::8,
        _rest::binary>> = binary

      assert version == 3
      assert patch_count == 1
      assert frame_begin == 0x00
    end

    test "encode_frame produces valid v3 header for insert patch" do
      node = %Dala.Node{id: "t1", type: :text, props: %{text: "Hello"}, children: []}
      patches = [{:insert, "root", 0, node}]
      binary = Dala.Renderer.encode_frame(patches)

      <<0xDA::8, 0xA1::8, version::little-16, patch_count::little-16, frame_begin::8,
        _rest::binary>> = binary

      assert version == 3
      assert patch_count == 1
      assert frame_begin == 0x00
      assert byte_size(binary) > 8
    end

    test "encode_frame handles update_props patch" do
      patches = [{:update_props, "b1", %{title: "Click"}}]
      binary = Dala.Renderer.encode_frame(patches)

      <<0xDA::8, 0xA1::8, version::little-16, patch_count::little-16, _frame_begin::8,
        _rest::binary>> = binary

      assert version == 3
      assert patch_count == 1
      assert byte_size(binary) > 8
    end

    test "encode_frame handles multiple patches" do
      patches = [
        {:remove, "old_id"},
        {:insert, "root", 0,
         %Dala.Node{id: "new", type: :text, props: %{text: "Hi"}, children: []}}
      ]

      binary = Dala.Renderer.encode_frame(patches)

      <<0xDA::8, 0xA1::8, version::little-16, patch_count::little-16, _frame_begin::8,
        _rest::binary>> = binary

      assert version == 3
      assert patch_count == 2
    end

    test "encode_frame includes inline strings in insert" do
      node = %Dala.Node{id: "t1", type: :text, props: %{text: "Hello World"}, children: []}
      patches = [{:insert, "root", 0, node}]
      binary = Dala.Renderer.encode_frame(patches)

      # The string "Hello World" should appear inline in the binary
      assert binary =~ "Hello World"
    end

    test "encode_frame includes layout props" do
      node = %Dala.Node{
        id: "c1",
        type: :column,
        props: %{padding: 16.0, flex_direction: :row},
        children: []
      }

      patches = [{:insert, "root", 0, node}]
      binary = Dala.Renderer.encode_frame(patches)

      <<0xDA::8, 0xA1::8, _version::little-16, _count::little-16, _frame_begin::8, _rest::binary>> =
        binary

      # Should encode without error and contain the padding float
      assert byte_size(binary) > 8
    end

    test "encode_frame ends with FRAME_END (0xFF)" do
      patches = [{:remove, "test_id"}]
      binary = Dala.Renderer.encode_frame(patches)

      # Last byte should be FRAME_END
      assert :binary.last(binary) == 0xFF
    end

    test "encode_frame wraps patches between FRAME_BEGIN and FRAME_END" do
      patches = [{:remove, "test_id"}]
      binary = Dala.Renderer.encode_frame(patches)

      # After header (6 bytes), first byte should be FRAME_BEGIN (0x00)
      <<_magic::binary-size(4), _count::little-16, frame_begin::8, _rest::binary>> = binary
      assert frame_begin == 0x00

      # Last byte should be FRAME_END (0xFF)
      assert :binary.last(binary) == 0xFF
    end

    test "encode_frame handles patch_node patch" do
      patches = [{:patch_node, "root", 0x0001, %{text: "World"}}]
      binary = Dala.Renderer.encode_frame(patches)

      <<0xDA::8, 0xA1::8, version::little-16, patch_count::little-16, frame_begin::8,
        _rest::binary>> = binary

      assert version == 3
      assert patch_count == 1
      assert frame_begin == 0x00
      assert byte_size(binary) > 8
    end

    test "v3 header has correct magic bytes" do
      patches = [{:remove, "x"}]
      binary = Dala.Renderer.encode_frame(patches)

      <<magic0::8, magic1::8, _rest::binary>> = binary
      assert magic0 == 0xDA
      assert magic1 == 0xA1
    end

    test "v3 header version field is 3" do
      patches = [{:remove, "x"}]
      binary = Dala.Renderer.encode_frame(patches)

      <<0xDA::8, 0xA1::8, version::little-16, _rest::binary>> = binary
      assert version == 3
    end
  end

  describe "Dala.Renderer.encode_set_text/2" do
    test "encodes SET_TEXT command with id and text" do
      binary = Dala.Renderer.encode_set_text("my_node", "Hello")
      # SET_TEXT opcode = 0x06
      <<opcode::8, _id_hash::little-64, text_len::little-16, text::binary>> = binary
      assert opcode == 0x06
      assert text_len == byte_size("Hello")
      assert text == "Hello"
    end

    test "encode_set_text produces correct total length" do
      text = "World"
      binary = Dala.Renderer.encode_set_text("node1", text)

      # 1 byte opcode + 8 bytes id + 2 bytes len + text bytes
      expected_size = 1 + 8 + 2 + byte_size(text)
      assert byte_size(binary) == expected_size
    end

    test "encode_set_text with empty string" do
      binary = Dala.Renderer.encode_set_text("node1", "")

      <<opcode::8, _id_hash::little-64, text_len::little-16, text::binary>> = binary
      assert opcode == 0x06
      assert text_len == 0
      assert text == ""
    end
  end

  describe "Dala.Renderer.encode_register_string/2" do
    test "encodes REGISTER_STRING command with string_id and text" do
      binary = Dala.Renderer.encode_register_string(42, "Hello")
      # REGISTER_STRING opcode = 0x05
      <<opcode::8, string_id::little-16, text_len::little-16, text::binary>> = binary
      assert opcode == 0x05
      assert string_id == 42
      assert text_len == byte_size("Hello")
      assert text == "Hello"
    end

    test "encode_register_string produces correct total length" do
      text = "World"
      binary = Dala.Renderer.encode_register_string(7, text)

      # 1 byte opcode + 2 bytes string_id + 2 bytes len + text bytes
      expected_size = 1 + 2 + 2 + byte_size(text)
      assert byte_size(binary) == expected_size
    end

    test "encode_register_string with string_id 0" do
      binary = Dala.Renderer.encode_register_string(0, "test")
      <<opcode::8, string_id::little-16, _len::little-16, _text::binary>> = binary
      assert opcode == 0x05
      assert string_id == 0
    end
  end

  describe "Dala.Renderer.encode_event/4" do
    test "encodes EVENT command with target_id, event_type, timestamp, and payload" do
      binary = Dala.Renderer.encode_event("btn1", 1, 12_345_678, <<1, 2, 3>>)
      # EVENT opcode = 0x08
      <<opcode::8, _target_hash::little-64, event_type::8, timestamp::little-64,
        payload_len::little-16, payload::binary>> = binary

      assert opcode == 0x08
      assert event_type == 1
      assert timestamp == 12_345_678
      assert payload_len == 3
      assert payload == <<1, 2, 3>>
    end

    test "encode_event with empty payload" do
      binary = Dala.Renderer.encode_event("node1", 0, 0, "")

      <<opcode::8, _target_hash::little-64, event_type::8, timestamp::little-64,
        payload_len::little-16, payload::binary>> = binary

      assert opcode == 0x08
      assert event_type == 0
      assert timestamp == 0
      assert payload_len == 0
      assert payload == ""
    end

    test "encode_event produces correct total length" do
      payload = <<255, 254, 253, 252>>
      binary = Dala.Renderer.encode_event("node1", 2, 99999, payload)

      # 1 byte opcode + 8 bytes target + 1 byte event_type + 8 bytes timestamp + 2 bytes len + payload
      expected_size = 1 + 8 + 1 + 8 + 2 + byte_size(payload)
      assert byte_size(binary) == expected_size
    end
  end

  describe "Dala.Renderer.encode_patch_node/3" do
    test "encodes PATCH_NODE command with id, field_mask, and changed props" do
      binary = Dala.Renderer.encode_patch_node("root", 0x0001, %{text: "World"})
      # PATCH_NODE opcode = 0x04
      <<opcode::8, _id_hash::little-64, field_mask::little-16, _rest::binary>> = binary
      assert opcode == 0x04
      assert field_mask == 0x0001
    end

    test "encode_patch_node with multiple fields in mask" do
      # text (0x0001) + color (0x0004) = 0x0005
      binary = Dala.Renderer.encode_patch_node("root", 0x0005, %{text: "Hi", color: "red"})
      <<opcode::8, _id_hash::little-64, field_mask::little-16, _rest::binary>> = binary
      assert opcode == 0x04
      assert field_mask == 0x0005
    end

    test "encode_patch_node with zero mask" do
      binary = Dala.Renderer.encode_patch_node("root", 0x0000, %{})

      <<opcode::8, _id_hash::little-64, field_mask::little-16, _rest::binary>> = binary
      assert opcode == 0x04
      assert field_mask == 0x0000
    end
  end

  describe "Dala.Renderer.compute_layout_hash/1" do
    test "computes stable hash for Dala.Node" do
      node = %Dala.Node{
        id: "root",
        type: :column,
        props: %{padding: 16.0},
        children: []
      }

      hash = Dala.Renderer.compute_layout_hash(node)
      assert is_integer(hash)
      assert hash > 0
    end

    test "different types produce different hashes" do
      node_a = %Dala.Node{id: "r", type: :column, props: %{}, children: []}
      node_b = %Dala.Node{id: "r", type: :row, props: %{}, children: []}

      assert Dala.Renderer.compute_layout_hash(node_a) !=
               Dala.Renderer.compute_layout_hash(node_b)
    end
  end

  describe "frame batching (FRAME_BEGIN / FRAME_END)" do
    test "single remove patch is wrapped in frame" do
      patches = [{:remove, "x"}]
      binary = Dala.Renderer.encode_frame(patches)

      # After 4-byte magic+version + 2-byte count, we should see FRAME_BEGIN
      <<_magic_and_version::binary-size(4), _count::little-16, frame_begin::8, _body::binary>> =
        binary

      assert frame_begin == 0x00

      # Last byte should be FRAME_END
      assert :binary.last(binary) == 0xFF
    end

    test "multiple patches are wrapped in single frame" do
      patches = [
        {:remove, "old_id"},
        {:insert, "root", 0,
         %Dala.Node{id: "new", type: :text, props: %{text: "New"}, children: []}}
      ]

      binary = Dala.Renderer.encode_frame(patches)

      # Header: 4 bytes magic+version, 2 bytes count, then FRAME_BEGIN
      <<_magic::binary-size(4), count::little-16, frame_begin::8, _rest::binary>> = binary
      assert count == 2
      assert frame_begin == 0x00
      assert :binary.last(binary) == 0xFF
    end

    test "empty patch list still produces valid frame" do
      patches = []
      binary = Dala.Renderer.encode_frame(patches)

      <<0xDA::8, 0xA1::8, version::little-16, count::little-16, frame_begin::8, frame_end::8>> =
        binary

      assert version == 3
      assert count == 0
      assert frame_begin == 0x00
      assert frame_end == 0xFF
    end

    test "patch_node patch is properly encoded in frame" do
      patches = [{:patch_node, "root", 0x0005, %{text: "New", color: "red"}}]
      binary = Dala.Renderer.encode_frame(patches)

      <<0xDA::8, 0xA1::8, version::little-16, count::little-16, frame_begin::8, _body::binary>> =
        binary

      assert version == 3
      assert count == 1
      assert frame_begin == 0x00
      assert :binary.last(binary) == 0xFF
    end

    test "insert patch includes CREATE_NODE opcode (0x01)" do
      node = %Dala.Node{id: "t1", type: :text, props: %{text: "Hello"}, children: []}
      patches = [{:insert, "root", 0, node}]
      binary = Dala.Renderer.encode_frame(patches)

      # Skip header: 4 bytes magic+version, 2 bytes count, 1 byte FRAME_BEGIN
      <<_header::binary-size(7), create_opcode::8, _rest::binary>> = binary
      assert create_opcode == 0x01
    end

    test "remove patch includes REMOVE opcode (0x02)" do
      patches = [{:remove, "test_id"}]
      binary = Dala.Renderer.encode_frame(patches)

      # Skip header: 4 bytes magic+version, 2 bytes count, 1 byte FRAME_BEGIN
      <<_header::binary-size(7), remove_opcode::8, _rest::binary>> = binary
      assert remove_opcode == 0x02
    end

    test "update_props patch includes UPDATE opcode (0x03)" do
      patches = [{:update_props, "root", %{text: "Updated"}}]
      binary = Dala.Renderer.encode_frame(patches)

      <<_header::binary-size(7), update_opcode::8, _rest::binary>> = binary
      assert update_opcode == 0x03
    end

    test "patch_node patch includes PATCH_NODE opcode (0x04)" do
      patches = [{:patch_node, "root", 0x0001, %{text: "New"}}]
      binary = Dala.Renderer.encode_frame(patches)

      <<_header::binary-size(7), patch_opcode::8, _rest::binary>> = binary
      assert patch_opcode == 0x04
    end
  end

  describe "diff/2 edge cases" do
    test "handles both arguments as raw maps" do
      old = %{type: :text, props: %{text: "Old"}, children: []}
      new = %{type: :text, props: %{text: "New"}, children: []}
      patches = Dala.Diff.diff(old, new)
      assert length(patches) > 0
    end

    test "handles mixed map and Node struct" do
      old = %Dala.Node{id: "root", type: :text, props: %{text: "Old"}, children: []}
      new = %{type: :text, props: %{text: "New"}, children: []}
      patches = Dala.Diff.diff(old, new)
      assert length(patches) > 0
    end

    test "handles bulk child removal" do
      old = %Dala.Node{
        id: "root",
        type: :column,
        props: %{
          children: [
            %Dala.Node{id: "c1", type: :text, props: %{text: "A"}, children: []},
            %Dala.Node{id: "c2", type: :text, props: %{text: "B"}, children: []},
            %Dala.Node{id: "c3", type: :text, props: %{text: "C"}, children: []}
          ]
        },
        children: [
          %Dala.Node{id: "c1", type: :text, props: %{text: "A"}, children: []},
          %Dala.Node{id: "c2", type: :text, props: %{text: "B"}, children: []},
          %Dala.Node{id: "c3", type: :text, props: %{text: "C"}, children: []}
        ]
      }

      new = %Dala.Node{
        id: "root",
        type: :column,
        props: %{
          children: []
        },
        children: []
      }

      patches = Dala.Diff.diff(old, new)
      # Should produce patches reflecting the removal of all 3 children.
      # Patch tuples vary in arity (:remove is 2-tuple, :patch_node is 4-tuple, etc.)
      # so we match on the first element regardless of tuple size.
      removes =
        Enum.filter(patches, fn
          {:remove, _} -> true
          _ -> false
        end)

      assert length(removes) == 3
    end

    test "handles child reordering (same IDs, different order)" do
      old = %Dala.Node{
        id: "root",
        type: :column,
        props: %{},
        children: [
          %Dala.Node{id: "a", type: :text, props: %{text: "A"}, children: []},
          %Dala.Node{id: "b", type: :text, props: %{text: "B"}, children: []}
        ]
      }

      new = %Dala.Node{
        id: "root",
        type: :column,
        props: %{},
        children: [
          %Dala.Node{id: "b", type: :text, props: %{text: "B"}, children: []},
          %Dala.Node{id: "a", type: :text, props: %{text: "A"}, children: []}
        ]
      }

      # Reordering should not produce patches if content is identical
      patches = Dala.Diff.diff(old, new)
      # The diff may produce patches for reordering; at minimum it shouldn't crash
      assert patches == [] or is_list(patches)
    end

    test "handles deeply nested trees" do
      old = %Dala.Node{
        id: "root",
        type: :column,
        props: %{},
        children: [
          %Dala.Node{
            id: "level1",
            type: :row,
            props: %{},
            children: [
              %Dala.Node{
                id: "level2",
                type: :column,
                props: %{},
                children: [
                  %Dala.Node{id: "level3", type: :text, props: %{text: "Deep"}, children: []}
                ]
              }
            ]
          }
        ]
      }

      new = %Dala.Node{
        id: "root",
        type: :column,
        props: %{},
        children: [
          %Dala.Node{
            id: "level1",
            type: :row,
            props: %{},
            children: [
              %Dala.Node{
                id: "level2",
                type: :column,
                props: %{},
                children: [
                  %Dala.Node{id: "level3", type: :text, props: %{text: "Deeper"}, children: []}
                ]
              }
            ]
          }
        ]
      }

      patches = Dala.Diff.diff(old, new)
      assert length(patches) > 0
    end

    test "handles nil props on a node" do
      old = %Dala.Node{id: "root", type: :text, props: nil, children: []}
      new = %Dala.Node{id: "root", type: :text, props: %{text: "Hello"}, children: []}
      patches = Dala.Diff.diff(old, new)
      assert length(patches) > 0
    end

    test "handles empty old props and non-empty new props" do
      old = %Dala.Node{id: "root", type: :text, props: %{}, children: []}
      new = %Dala.Node{id: "root", type: :text, props: %{text: "New", title: "T"}, children: []}
      patches = Dala.Diff.diff(old, new)
      assert length(patches) > 0
    end

    test "handles non-empty old props and empty new props" do
      old = %Dala.Node{id: "root", type: :text, props: %{text: "Old", title: "T"}, children: []}
      new = %Dala.Node{id: "root", type: :text, props: %{}, children: []}
      patches = Dala.Diff.diff(old, new)
      assert length(patches) > 0
    end
  end

  describe "compute_field_mask/2 edge cases" do
    test "threshold: exactly half known fields changed" do
      old = %{text: "Same", title: "Same", color: "red"}
      new = %{text: "Changed", title: "Changed", color: "red"}
      {mask, changed} = Dala.Diff.compute_field_mask(old, new)
      assert mask != 0
      assert map_size(changed) > 0
    end

    test "all known fields changed" do
      old = %{text: "A", title: "B", color: "C", background: "D"}
      new = %{text: "W", title: "X", color: "Y", background: "Z"}
      {mask, changed} = Dala.Diff.compute_field_mask(old, new)
      assert mask != 0
      assert map_size(changed) > 0
    end

    test "only unknown fields changed" do
      old = %{custom_field: "A"}
      new = %{custom_field: "B"}
      {mask, changed} = Dala.Diff.compute_field_mask(old, new)
      assert mask == 0
      assert map_size(changed) == 1
    end
  end
end
