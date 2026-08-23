defmodule Dala.Setup do
  @moduledoc """
  Convenience shorthand for `Dala.Setup.Setup`.

  Provides runtime setup helpers for Bluetooth and WiFi functionality.
  """

  defdelegate check_bluetooth(), to: Dala.Setup.Setup
  defdelegate check_wifi(), to: Dala.Setup.Setup
  defdelegate ensure_bluetooth_permissions(socket), to: Dala.Setup.Setup
  defdelegate ensure_wifi_permissions(socket), to: Dala.Setup.Setup
  defdelegate diagnostic(), to: Dala.Setup.Setup
  defdelegate print_diagnostic(), to: Dala.Setup.Setup
end

defmodule Dala.Setup.Setup do
  @moduledoc """
  Runtime setup helpers for Bluetooth and WiFi functionality.

  This module provides functions that can be called from your app's startup
  code to ensure Bluetooth and WiFi are properly configured and available.

  ## Usage

  In your app's `Dala.App` module or in a screen's `mount/3`:

      def mount(_params, _session, socket) do
        # Check and request permissions at startup
        Dala.Setup.ensure_bluetooth_permissions(socket)
        Dala.Setup.ensure_wifi_permissions(socket)

        {:ok, socket}
      end

  ## Platform Notes

  - **iOS**: Requires usage descriptions in Info.plist (see `mix dala.setup_bluetooth_wifi`)
  - **Android**: Requires permissions in AndroidManifest.xml and runtime permission requests
  """

  @doc """
  Check if Bluetooth is available and properly configured.

  Returns:
      {:ok, state} - Bluetooth is available, returns current state
      {:error, reason} - Bluetooth is not available or not configured
  """
  @spec check_bluetooth() :: {:ok, Dala.Hardware.Bluetooth.state()} | {:error, term()}
  def check_bluetooth do
    case apply(Dala.Hardware.Bluetooth, :state, []) do
      :unsupported -> {:error, :bluetooth_not_supported}
      :unauthorized -> {:error, :bluetooth_permission_denied}
      state -> {:ok, state}
    end
  rescue
    _ -> {:error, :bluetooth_nif_not_available}
  end

  @doc """
  Check if WiFi is available and properly configured.

  Returns:
      {:ok, info} - WiFi is available, returns current network info
      {:error, reason} - WiFi is not available or not configured
  """
  @spec check_wifi() :: {:ok, map()} | {:error, term()}
  def check_wifi do
    case apply(Dala.Connectivity.Wifi, :current_network, []) do
      %{connected: true} = info -> {:ok, info}
      %{connected: false} -> {:ok, %{connected: false}}
      _ -> {:error, :wifi_not_available}
    end
  rescue
    _ -> {:error, :wifi_nif_not_available}
  end

  @doc """
  Ensure Bluetooth permissions are granted.

  On Android, this will trigger a runtime permission request if needed.
  On iOS, this checks if the permission is granted (must be configured in Info.plist).

  Returns the updated socket.
  """
  @spec ensure_bluetooth_permissions(Dala.Socket.t()) :: Dala.Socket.t()
  def ensure_bluetooth_permissions(socket) do
    apply(Dala.Permissions, :request, [socket, :bluetooth])
  end

  @doc """
  Ensure WiFi permissions are granted (Android only).

  On Android, WiFi scanning requires location permission.
  On iOS, WiFi info access is limited and may not require explicit permission.

  Returns the updated socket.
  """
  @spec ensure_wifi_permissions(Dala.Socket.t()) :: Dala.Socket.t()
  def ensure_wifi_permissions(socket) do
    apply(Dala.Permissions, :request, [socket, :wifi])
  end

  @doc """
  Run a full diagnostic of Bluetooth and WiFi setup.

  Returns a map with the status of each component.

  Example:

      Dala.Setup.diagnostic()
      # => %{
      #      bluetooth: %{available: true, state: :powered_on, permission: :granted},
      #      wifi: %{available: true, connected: true, ssid: "MyNetwork"}
      #    }
  """
  @spec diagnostic() :: map()
  def diagnostic do
    %{
      bluetooth: bluetooth_diagnostic(),
      wifi: wifi_diagnostic()
    }
  end

  defp bluetooth_diagnostic do
    case check_bluetooth() do
      {:ok, state} ->
        %{
          available: true,
          state: state,
          permission: :granted
        }

      {:error, :bluetooth_permission_denied} ->
        %{
          available: true,
          state: :unauthorized,
          permission: :denied
        }

      {:error, :bluetooth_not_supported} ->
        %{
          available: false,
          state: :unsupported,
          permission: :not_applicable
        }

      {:error, :bluetooth_nif_not_available} ->
        %{
          available: false,
          state: :unknown,
          permission: :unknown,
          error: "NIF not available - check native build"
        }
    end
  end

  defp wifi_diagnostic do
    case check_wifi() do
      {:ok, %{connected: true} = info} ->
        %{
          available: true,
          connected: true,
          ssid: info[:ssid],
          ip: info[:ip]
        }

      {:ok, %{connected: false}} ->
        %{
          available: true,
          connected: false
        }

      {:error, :wifi_not_available} ->
        %{
          available: false,
          connected: false
        }

      {:error, :wifi_nif_not_available} ->
        %{
          available: false,
          connected: false,
          error: "NIF not available - check native build"
        }
    end
  end

  @doc """
  Print a human-readable diagnostic report to the console.

  Useful for debugging during development.
  """
  def print_diagnostic do
    diag = diagnostic()

    Mix.shell().info("""
    ╔══════════════════════════════════════════════════════╗
    ║           Dala Bluetooth/WiFi Diagnostic             ║
    ╚══════════════════════════════════════════════════════╝
    """)

    # Bluetooth
    Mix.shell().info("Bluetooth:")
    bt = diag.bluetooth

    if bt.available do
      Mix.shell().info("  ✓ Available (state: #{bt.state})")

      if bt.permission == :granted do
        Mix.shell().info("  ✓ Permission granted")
      else
        Mix.shell().info("  ✗ Permission: #{bt.permission}")
      end
    else
      Mix.shell().info("  ✗ Not available")

      if bt[:error] do
        Mix.shell().info("    Error: #{bt.error}")
      end
    end

    Mix.shell().info("")

    # WiFi
    Mix.shell().info("WiFi:")
    wifi = diag.wifi

    if wifi.available do
      if wifi.connected do
        Mix.shell().info("  ✓ Connected to #{wifi.ssid} (#{wifi.ip})")
      else
        Mix.shell().info("  ✓ Available but not connected")
      end
    else
      Mix.shell().info("  ✗ Not available")

      if wifi[:error] do
        Mix.shell().info("    Error: #{wifi.error}")
      end
    end

    :ok
  end
end
