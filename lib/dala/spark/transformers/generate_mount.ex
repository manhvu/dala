defmodule Dala.Spark.Transformers.GenerateMount do
  @moduledoc """
  Spark transformer that generates the `mount/3` function from DSL attributes.

  Each `attribute` declaration becomes a `Dala.Socket.assign/3` call
  initialized with its default value. If no attributes are declared, a
  default mount that returns `{:ok, socket}` is generated.
  """

  use Spark.Dsl.Transformer

  @impl true
  def transform(dsl_state) do
    attributes = Spark.Dsl.Transformer.get_entities(dsl_state, [:attributes])

    if Enum.any?(attributes) do
      assign_calls =
        Enum.map(attributes, fn attr ->
          name = Map.get(attr, :name)
          default = Map.get(attr, :default)

          quote do
            socket = Dala.Socket.assign(socket, unquote(name), unquote(default))
          end
        end)

      mount_fn =
        quote do
          def mount(_params, _session, socket) do
            unquote_splicing(assign_calls)
            {:ok, socket}
          end
        end

      {:ok, Spark.Dsl.Transformer.eval(dsl_state, [], mount_fn)}
    else
      mount_fn =
        quote do
          def mount(_params, _session, socket) do
            {:ok, socket}
          end
        end

      {:ok, Spark.Dsl.Transformer.eval(dsl_state, [], mount_fn)}
    end
  end
end
