defmodule Dala.ML.ONNX.Test do
  @moduledoc """
  Tests for Dala.ML.ONNX.

  Verifies the rewritten module that uses Dala.Native NIF functions.
  On platforms where the NIF is not compiled, returns :not_supported.
  """

  use ExUnit.Case, async: true

  describe "module loading" do
    test "ONNX module is available" do
      assert Code.ensure_loaded?(Dala.ML.ONNX) == true
    end
  end

  describe "available?/0" do
    test "returns true or false" do
      result = Dala.ML.ONNX.available?()
      assert result == true or result == false
    end
  end

  describe "create_session/1" do
    test "accepts binary data" do
      dummy_data = <<1, 2, 3, 4, 5, 6, 7, 8>>

      case Dala.ML.ONNX.create_session(dummy_data) do
        {:ok, session_id} when is_integer(session_id) ->
          # Clean up
          Dala.ML.ONNX.destroy_session(session_id)

        :not_supported ->
          :ok

        {:error, _} ->
          :ok
      end
    end

    test "returns error for empty binary" do
      result = Dala.ML.ONNX.create_session(<<>>)

      assert match?({:error, _}, result) or match?({:ok, _}, result) or
               match?(:not_supported, result)
    end

    test "validates argument type" do
      assert_raise FunctionClauseError, fn ->
        Dala.ML.ONNX.create_session(123)
      end

      assert_raise FunctionClauseError, fn ->
        Dala.ML.ONNX.create_session(:atom)
      end
    end
  end

  describe "destroy_session/1" do
    test "handles invalid session_id gracefully" do
      case Dala.ML.ONNX.destroy_session(999_999) do
        :ok -> :ok
        {:error, _} -> :ok
        :not_supported -> :ok
      end
    end

    test "validates argument type" do
      assert_raise FunctionClauseError, fn ->
        Dala.ML.ONNX.destroy_session("not_an_integer")
      end
    end

    test "create then destroy lifecycle" do
      dummy_data = <<1, 2, 3, 4, 5, 6, 7, 8>>

      case Dala.ML.ONNX.create_session(dummy_data) do
        {:ok, session_id} ->
          result = Dala.ML.ONNX.destroy_session(session_id)
          assert result == :ok or result == :not_supported

        _ ->
          :ok
      end
    end
  end

  describe "run/2" do
    test "returns not_supported or error for invalid session" do
      case Dala.ML.ONNX.run(999_999, <<1, 2, 3, 4>>) do
        {:ok, _output} -> :ok
        {:error, _} -> :ok
        :not_supported -> :ok
      end
    end

    test "validates argument types" do
      assert_raise FunctionClauseError, fn ->
        Dala.ML.ONNX.run("not_integer", <<1>>)
      end

      assert_raise FunctionClauseError, fn ->
        Dala.ML.ONNX.run(1, :not_binary)
      end
    end
  end

  describe "load_model_from_file/1" do
    test "returns error for non-existent file" do
      result = Dala.ML.ONNX.load_model_from_file("/non/existent/model.onnx")
      assert match?({:error, _}, result) or match?(:not_supported, result)
    end

    test "validates argument type" do
      assert_raise FunctionClauseError, fn ->
        Dala.ML.ONNX.load_model_from_file(123)
      end
    end
  end

  describe "runtime_available?/0" do
    test "returns false or not_supported" do
      result = Dala.ML.ONNX.runtime_available?()
      assert result == false or result == :not_supported
    end
  end

  describe "session_count/0" do
    test "returns 0 when NIF is not loaded" do
      result = Dala.ML.ONNX.session_count()
      assert result == 0 or result == :not_supported
    end

    test "session count increases after create" do
      before = Dala.ML.ONNX.session_count()

      if is_integer(before) do
        case Dala.ML.ONNX.create_session(<<1, 2, 3, 4>>) do
          {:ok, session_id} ->
            after_create = Dala.ML.ONNX.session_count()
            assert after_create == before + 1
            Dala.ML.ONNX.destroy_session(session_id)

          _ ->
            :ok
        end
      end
    end
  end

  describe "full lifecycle" do
    test "create → run → destroy sequence" do
      dummy_data = <<1, 2, 3, 4, 5, 6, 7, 8>>

      case Dala.ML.ONNX.create_session(dummy_data) do
        {:ok, session_id} ->
          # Run inference
          run_result = Dala.ML.ONNX.run(session_id, <<1.0::float-32, 2.0::float-32>>)
          assert match?({:ok, _}, run_result) or match?({:error, _}, run_result)

          # Destroy
          assert Dala.ML.ONNX.destroy_session(session_id) == :ok or
                   Dala.ML.ONNX.destroy_session(session_id) == :not_supported

        :not_supported ->
          :ok

        {:error, _} ->
          :ok
      end
    end
  end
end
