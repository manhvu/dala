defmodule Dala.Gpu.CommandTest do
  use ExUnit.Case, async: true

  alias Dala.Gpu.Command

  describe "encode_clear/1" do
    test "prefixes command type 0x01 with rgba bytes" do
      assert <<0x01, 255, 0, 0, 255>> = Command.encode_clear(:red)
      assert <<0x01, 0, 0, 0, 0>> = Command.encode_clear(:transparent)
    end
  end

  describe "rect primitives" do
    test "encode_fill_rect uses u32 LE coords" do
      assert <<0x02, x::unsigned-little-32, y::unsigned-little-32, w::unsigned-little-32,
               h::unsigned-little-32, 1, 2, 3, 4>> =
               Command.encode_fill_rect(10, 20, 300, 400, {1, 2, 3, 4})

      assert x == 10 and y == 20 and w == 300 and h == 400
    end

    test "encode_draw_round_rect includes radius" do
      assert <<0x11, _::unsigned-little-(32 * 5), 9, 8, 7, 255>> =
               Command.encode_draw_round_rect(1, 2, 3, 4, 5, {9, 8, 7})
    end

    test "encode_fill_round_rect includes radius" do
      assert <<0x12, _::unsigned-little-(32 * 5), 0, 0, 255, 255>> =
               Command.encode_fill_round_rect(1, 2, 3, 4, 5, :blue)
    end
  end

  describe "line and circle primitives" do
    test "encode_draw_line uses i32 LE coords" do
      assert <<0x03, x1::signed-little-32, y1::signed-little-32, x2::signed-little-32,
               y2::signed-little-32, 255, 255, 255, 255>> =
               Command.encode_draw_line(-5, -6, 7, 8, :white)

      assert x1 == -5 and y1 == -6 and x2 == 7 and y2 == 8
    end

    test "encode_draw_circle and encode_fill_circle" do
      assert <<0x0D, cx::signed-little-32, cy::signed-little-32, r::unsigned-little-32, 0, 0, 0,
               255>> = Command.encode_draw_circle(-1, 2, 30, :black)

      assert cx == -1 and cy == 2 and r == 30

      assert <<0x0E, _cx::signed-little-32, _cy::signed-little-32, _r::unsigned-little-32, 255, 0,
               0, 255>> = Command.encode_fill_circle(0, 0, 10, :red)
    end

    test "encode_draw_triangle and encode_fill_triangle carry six i32 LE coords" do
      assert <<
               0x0F,
               x1::signed-little-32,
               y1::signed-little-32,
               x2::signed-little-32,
               y2::signed-little-32,
               x3::signed-little-32,
               y3::signed-little-32,
               255,
               255,
               255,
               255
             >> = Command.encode_draw_triangle(-1, 2, 3, -4, 5, 6, :white)

      assert {x1, y1, x2, y2, x3, y3} == {-1, 2, 3, -4, 5, 6}

      assert <<
               0x10,
               a1::signed-little-32,
               b1::signed-little-32,
               a2::signed-little-32,
               b2::signed-little-32,
               a3::signed-little-32,
               b3::signed-little-32,
               0,
               255,
               0,
               255
             >> = Command.encode_fill_triangle(1, 2, 3, 4, 5, 6, :green)

      assert {a1, b1, a2, b2, a3, b3} == {1, 2, 3, 4, 5, 6}
    end
  end

  describe "sprites and images" do
    test "encode_blit packs sprite id as u64 LE plus i32 coords" do
      assert <<0x04, id::unsigned-little-64, x::signed-little-32, y::signed-little-32>> =
               Command.encode_blit(77, -1, 2)

      assert id == 77 and x == -1 and y == 2
    end

    test "encode_load_sprite appends pixel data" do
      pixels = <<1, 2, 3, 4>>

      assert <<0x07, id::unsigned-little-64, w::unsigned-little-32, h::unsigned-little-32,
               ^pixels::binary>> = Command.encode_load_sprite(9, pixels, 1, 1)

      assert id == 9 and w == 1 and h == 1
    end

    test "encode_remove_sprite" do
      assert <<0x08, id::unsigned-little-64>> = Command.encode_remove_sprite(42)
      assert id == 42
    end

    test "encode_load_image / encode_remove_image use image opcodes" do
      pixels = <<5, 6, 7, 8>>

      assert <<0x17, id::unsigned-little-64, w::unsigned-little-32, h::unsigned-little-32,
               ^pixels::binary>> = Command.encode_load_image(3, pixels, 2, 2)

      assert <<0x18, rid::unsigned-little-64>> = Command.encode_remove_image(3)
      assert rid == 3
    end

    test "encode_image_blit carries position and size" do
      assert <<0x16, id::unsigned-little-64, x::signed-little-32, y::signed-little-32,
               w::unsigned-little-32, h::unsigned-little-32>> =
               Command.encode_image_blit(5, -3, 4, 100, 50)

      assert id == 5 and x == -3 and y == 4 and w == 100 and h == 50
    end
  end

  describe "surface control" do
    test "encode_present and encode_reset_clip are single-byte commands" do
      assert <<0x05>> = Command.encode_present()
      assert <<0x14>> = Command.encode_reset_clip()
    end

    test "encode_resize packs u32 LE dimensions" do
      assert <<0x06, w::unsigned-little-32, h::unsigned-little-32>> =
               Command.encode_resize(1920, 1080)

      assert w == 1920 and h == 1080
    end

    test "encode_read_pixels packs u32 LE rect" do
      assert <<0x0A, x::unsigned-little-32, y::unsigned-little-32, w::unsigned-little-32,
               h::unsigned-little-32>> = Command.encode_read_pixels(1, 2, 3, 4)

      assert {x, y, w, h} == {1, 2, 3, 4}
    end

    test "encode_set_clip encodes enabled flag as 1 or 0" do
      assert <<0x13, _::binary-size(16), 1>> = Command.encode_set_clip(0, 0, 10, 10, true)
      assert <<0x13, _::binary-size(16), 0>> = Command.encode_set_clip(0, 0, 10, 10, false)
    end
  end

  describe "shader plumbing" do
    test "encode_dispatch_compute length-prefixes source and params" do
      params = <<1.0::float-little-32>>
      cmd = Command.encode_dispatch_compute("kernel", params, {1, 2, 3})

      <<0x09, src_len::unsigned-little-32, src::binary-size(src_len),
        params_len::unsigned-little-32, ^params::binary-size(params_len), wx::unsigned-little-32,
        wy::unsigned-little-32, wz::unsigned-little-32>> = cmd

      assert :erlang.binary_to_term(src) == "kernel"
      assert src_len == byte_size(src)
      assert params_len == byte_size(params)
      assert {wx, wy, wz} == {1, 2, 3}
    end

    test "encode_load_shader length-prefixes name and source" do
      cmd = Command.encode_load_shader("blur", "float4 main(){}")

      <<0x0B, name_len::unsigned-little-32, name::binary-size(name_len),
        src_len::unsigned-little-32, src::binary-size(src_len)>> = cmd

      assert "blur" == :erlang.binary_to_term(name)
      assert "float4 main(){}" == :erlang.binary_to_term(src)
    end

    test "encode_set_uniform length-prefixes name and data" do
      data = <<9.5::float-little-32>>
      cmd = Command.encode_set_uniform("time", data)

      <<0x0C, name_len::unsigned-little-32, name::binary-size(name_len),
        data_len::unsigned-little-32, ^data::binary-size(data_len)>> = cmd

      assert "time" == :erlang.binary_to_term(name)
    end

    test "encode_batch prefixes count and concatenates sub-commands" do
      batch = Command.encode_batch([Command.encode_present(), Command.encode_present()])

      assert <<0x15, count::unsigned-little-32, rest::binary>> = batch
      assert count == 2
      assert byte_size(rest) == 2
    end
  end

  describe "color_to_rgba/1" do
    test "named colors map to RGBA bytes" do
      assert Command.color_to_rgba(:black) == <<0, 0, 0, 255>>
      assert Command.color_to_rgba(:white) == <<255, 255, 255, 255>>
      assert Command.color_to_rgba(:red) == <<255, 0, 0, 255>>
      assert Command.color_to_rgba(:green) == <<0, 255, 0, 255>>
      assert Command.color_to_rgba(:blue) == <<0, 0, 255, 255>>
      assert Command.color_to_rgba(:transparent) == <<0, 0, 0, 0>>
    end

    test "rgb tuples get full alpha, rgba tuples pass through" do
      assert Command.color_to_rgba({1, 2, 3}) == <<1, 2, 3, 255>>
      assert Command.color_to_rgba({1, 2, 3, 128}) == <<1, 2, 3, 128>>
    end
  end
end
