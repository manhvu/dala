defmodule DemoApp.ProfileScreen do
  @moduledoc """
  Profile screen demonstrating form inputs and image display.
  """
  use Dala.Spark.Dsl

  attributes do
    attribute(:name, :string, default: "John Doe")
    attribute(:email, :string, default: "john@example.com")
    attribute(:notifications, :boolean, default: true)
    attribute(:volume, :integer, default: 50)
  end

  screen name: :profile do
    column padding: 16, gap: 12 do
      text("Profile", text_size: :xl, font_weight: "bold")
      divider()

      # Avatar placeholder
      box width: 100, height: 100, corner_radius: 50, background: "#4A90E2", alignment: :center do
        text("JD", text_color: "#ffffff", font_weight: "bold")
      end

      # Name field
      text("Name", font_weight: "bold")
      text_field(text: @name, placeholder: "Enter name", on_change: :update_name)

      # Email field
      text("Email", font_weight: "bold")

      text_field(
        text: @email,
        placeholder: "Enter email",
        keyboard_type: :email,
        on_change: :update_email
      )

      divider()

      # Toggle
      row spacing: 12, alignment: :center do
        text("Push Notifications")
        toggle(value: @notifications, on_change: :toggle_notifications)
      end

      # Slider
      text("Volume: @volume%")
      slider(value: @volume, min_value: 0, max_value: 100, on_change: :update_volume)
    end
  end

  def handle_event(:update_name, %{"value" => name}, socket) do
    {:noreply, Dala.Socket.assign(socket, :name, name)}
  end

  def handle_event(:update_email, %{"value" => email}, socket) do
    {:noreply, Dala.Socket.assign(socket, :email, email)}
  end

  def handle_event(:toggle_notifications, %{"value" => value}, socket) do
    {:noreply, Dala.Socket.assign(socket, :notifications, value)}
  end

  def handle_event(:update_volume, %{"value" => volume}, socket) do
    {:noreply, Dala.Socket.assign(socket, :volume, volume)}
  end
end
