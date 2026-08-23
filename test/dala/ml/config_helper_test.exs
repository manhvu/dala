defmodule Dala.ML.ConfigHelperTest do
  use ExUnit.Case, async: true

  alias Dala.ML.ConfigHelper

  test "recommended_deps/0 lists the core ML stack" do
    deps = ConfigHelper.recommended_deps()
    names = Enum.map(deps, &elem(&1, 0))

    assert :nx in names
    assert :axon in names
    assert :scholar in names
    assert :nx_signal in names
    assert :polaris in names

    Enum.each(deps, fn {name, req} ->
      assert "#{name}" != ""
      assert is_binary(req) and String.starts_with?(req, "~>")
    end)
  end

  test "quantized_model_config/0 describes both quantized models" do
    config = ConfigHelper.quantized_model_config()

    assert %{models: [net, yolo], note: note} = config
    assert net.name == "dalailenet_v2_quantized"
    assert net.input_size == {224, 224, 3}
    assert net.output_classes == 1000
    assert yolo.name == "yolo_nano_quantized"
    assert yolo.input_size == {416, 416, 3}
    assert is_binary(note) and byte_size(note) > 0
  end

  test "recommended_config/0 disables JIT and selects the EMLX backend" do
    config = ConfigHelper.recommended_config()

    assert config =~ ~s(config :emlx, jit_enabled: false)
    assert config =~ "EMLX.Backend"
  end

  test "build_env_vars/0 pins MLX build settings" do
    env = ConfigHelper.build_env_vars()

    assert %{"LIBMLX_ENABLE_JIT" => "false", "LIBMLX_VERSION" => version} = env
    assert version =~ ~r/^\d+\.\d+\.\d+$/
  end

  test "print_mix_deps/0 renders a valid deps snippet" do
    snippet = ConfigHelper.print_mix_deps()

    assert snippet =~ "defp deps do"

    for {name, _req} <- ConfigHelper.recommended_deps() do
      assert snippet =~ Atom.to_string(name)
    end
  end

  test "print_config/0 echoes recommended_config/0" do
    assert ConfigHelper.print_config() == ConfigHelper.recommended_config()
  end
end
