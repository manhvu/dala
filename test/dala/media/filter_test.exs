defmodule Dala.Media.FilterTest do
  use ExUnit.Case, async: true

  alias Dala.Media.Filter

  describe "apply_filter/3 without a surface (param encoding)" do
    test "encodes blur radius as little-endian f32" do
      assert <<2.0::float-little-32>> = Filter.apply_filter(nil, :blur, %{radius: 2.0})
    end

    test "encodes sharpen amount" do
      assert <<0.5::float-little-32>> = Filter.apply_filter(nil, :sharpen, %{amount: 0.5})
    end

    test "encodes beauty strength" do
      assert <<strength::float-little-32>> = Filter.apply_filter(nil, :beauty, %{strength: 0.8})
      assert_in_delta strength, 0.8, 1.0e-6
    end

    test "encodes denoise threshold" do
      assert <<0.25::float-little-32>> = Filter.apply_filter(nil, :denoise, %{threshold: 0.25})
    end

    test "lut and edge_detect take no params" do
      assert <<>> = Filter.apply_filter(nil, :lut, %{lut_path: "x.png"})
      assert <<>> = Filter.apply_filter(nil, :edge_detect, %{})
    end
  end

  describe "shader_source/1" do
    test "returns shader source for every filter type" do
      for type <- [:blur, :sharpen, :lut, :beauty, :denoise, :edge_detect] do
        source = Filter.shader_source(type)
        assert is_binary(source)
        refute source == ""
      end
    end
  end
end
