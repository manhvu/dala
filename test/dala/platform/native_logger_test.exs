defmodule Dala.Platform.NativeLoggerTest do
  use ExUnit.Case, async: false

  alias Dala.Platform.NativeLogger

  defmodule RecordingNif do
    @moduledoc false

    def log_level(level, text) do
      send(:native_logger_test_sink, {:nif_log, level, text})
      :ok
    end
  end

  defmodule RaisingNif do
    @moduledoc false

    def platform, do: raise("nif not loaded")
  end

  setup do
    Process.register(self(), :native_logger_test_sink)
    :ok
  end

  test "install/0 is a safe no-op on host (NIF unavailable)" do
    assert :ok == NativeLogger.install(nif: RaisingNif)
  end

  test "install/0 with a real platform NIF registers the handler idempotently" do
    defplatform = Module.concat(__MODULE__, PlatformNif)

    unless Code.ensure_loaded?(defplatform) do
      defmodule defplatform do
        @moduledoc false
        def platform, do: :ios

        def log_level(_level, _text), do: :ok
      end
    end

    assert :ok == NativeLogger.install(nif: defplatform)
    assert :ok == NativeLogger.install(nif: defplatform)

    handlers = Enum.map(:logger.get_handler_config(), & &1.id)
    on_exit(fn -> :logger.remove_handler(:dala_native_logger) end)

    assert :dala_native_logger in handlers
  end

  test "log/2 routes formatted messages to the NIF with mapped levels" do
    msg = %{level: :warning, msg: {:string, ["careful"]}, meta: %{}}

    :ok = NativeLogger.log(msg, %{nif: RecordingNif})

    assert_receive({:nif_log, :warning, "careful"})
  end

  test "format_msg/2 handles string, report, format and raw messages" do
    assert NativeLogger.format_msg({:string, ["a", "b"]}, %{}) == "ab"
    assert NativeLogger.format_msg({:report, %{a: 1}}, %{}) =~ "%{a: 1}"
    assert NativeLogger.format_msg({:format, "~s value=~p", ["x", 3]}, %{}) == "x value=3"
    assert NativeLogger.format_msg(:weird, %{}) == ":weird"
  end

  test "level_to_nif/1 maps OTP levels onto the three native priorities" do
    assert NativeLogger.level_to_nif(:debug) == :debug
    assert NativeLogger.level_to_nif(:info) == :info
    assert NativeLogger.level_to_nif(:notice) == :info
    assert NativeLogger.level_to_nif(:warning) == :warning
    assert NativeLogger.level_to_nif(:error) == :error
    assert NativeLogger.level_to_nif(:critical) == :error
    assert NativeLogger.level_to_nif(:emergency) == :error
    assert NativeLogger.level_to_nif(:bogus) == :info
  end
end
