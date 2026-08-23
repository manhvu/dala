defmodule Dala.TestSupport.VerifierFixtureScreen do
  @moduledoc """
  Compiled fixture (real beam on disk) so `Dala.Spark.DslVerifier.defined_handlers/1`
  can exercise its beam_lib debug-info extraction in tests.
  """

  use Dala.Spark.Dsl

  dala do
    attribute(:count, :integer, default: 0)

    screen name: :verifier_fixture do
      column do
        button("Inc", on_tap: :increment)
        button("Reset", on_tap: :reset_missing)
      end
    end
  end

  def handle_event(:increment, _params, socket),
    do: {:noreply, Dala.Socket.assign(socket, :count, socket.assigns.count + 1)}

  # Handled but never referenced from the tree — unused-handler reporting.
  def handle_event(:dead_handler, _params, socket), do: {:noreply, socket}
end
