defmodule Dala.Setup.SetupTest do
  use ExUnit.Case, async: true

  alias Dala.Setup.Setup

  describe "Dala.Setup facade" do
    test "delegates check_bluetooth/0, check_wifi/0 and diagnostic/0" do
      assert Dala.Setup.check_bluetooth() == Setup.check_bluetooth()
      assert Dala.Setup.check_wifi() == Setup.check_wifi()
      assert Dala.Setup.diagnostic() == Setup.diagnostic()
    end
  end

  defp assert_documented_result(result, allowed_reasons) do
    case result do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        unless reason in allowed_reasons do
          flunk("unexpected error reason: #{inspect(reason)}")
        end

      other ->
        flunk("unexpected result: #{inspect(other)}")
    end
  end

  describe "check_bluetooth/0" do
    test "returns an ok tuple or a documented error" do
      assert_documented_result(Setup.check_bluetooth(), [
        :bluetooth_not_supported,
        :bluetooth_permission_denied,
        :bluetooth_nif_not_available
      ])
    end
  end

  describe "check_wifi/0" do
    test "returns an ok tuple or a documented error" do
      assert_documented_result(Setup.check_wifi(), [
        :wifi_not_available,
        :wifi_nif_not_available
      ])
    end
  end

  describe "diagnostic/0" do
    test "mirrors the bluetooth check" do
      diag = Setup.diagnostic()
      assert %{bluetooth: bt, wifi: _} = diag

      case Setup.check_bluetooth() do
        {:ok, state} ->
          assert bt == %{available: true, state: state, permission: :granted}

        {:error, :bluetooth_not_supported} ->
          assert bt == %{available: false, state: :unsupported, permission: :not_applicable}

        {:error, :bluetooth_permission_denied} ->
          assert bt == %{available: true, state: :unauthorized, permission: :denied}

        {:error, :bluetooth_nif_not_available} ->
          assert bt.available == false
          assert bt.state == :unknown
          assert byte_size(bt.error) > 0
      end
    end

    test "mirrors the wifi check" do
      diag = Setup.diagnostic()
      assert %{bluetooth: _, wifi: wifi} = diag

      case Setup.check_wifi() do
        {:ok, %{connected: true}} ->
          assert wifi.available == true
          assert wifi.connected == true

        {:ok, %{connected: false}} ->
          assert wifi == %{available: true, connected: false}

        {:error, :wifi_not_available} ->
          assert wifi == %{available: false, connected: false}

        {:error, :wifi_nif_not_available} ->
          assert wifi.available == false
          assert wifi.connected == false
          assert byte_size(wifi.error) > 0
      end
    end
  end
end
