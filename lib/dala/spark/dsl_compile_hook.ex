defmodule Dala.Spark.DslCompileHook do
  @moduledoc """
  Compile-time hook that verifies DSL definitions when screen modules are compiled.

  This module is used via `@before_compile` in `Dala.Spark.Dsl` and runs
  verification on the module's DSL state after all transformers have completed.
  Warnings are printed to the compiler output.
  """

  @doc """
  Called automatically by the `@before_compile` mechanism.
  """
  defmacro __before_compile__(env) do
    module = env.module

    # Only verify modules that use Dala.Spark.Dsl
    if Module.get_attribute(module, :__dala_dsl__) do
      verify_and_warn(module, env)
    end

    quote do
      # no runtime code injected
    end
  end

  defp verify_and_warn(module, env) do
    # Gather DSL info from module attributes
    entities = Module.get_attribute(module, :__dala_dsl_entities__) || []
    attributes = Module.get_attribute(module, :__dala_dsl_attributes__) || []

    # Clause heads can't be extracted mid-compilation; handler checks run at
    # runtime verification instead (see DslVerifier.defined_handlers/1).
    warnings =
      Dala.Spark.DslVerifier.verify_from_raw(module, entities, attributes, :not_available)

    if warnings != [] do
      file = env.file
      line = 1

      Enum.each(warnings, fn w ->
        w_line = if w.line > 0, do: w.line, else: line

        # Emit a compiler diagnostic on stderr (same shape as Elixir's own
        # "warning:" output) so editors surface it inline. Errors raise so
        # broken screens fail the build instead of silently rendering an
        # empty/partial UI.
        IO.write(:standard_error, "warning: #{w.message}\n  #{file}:#{w_line}\n")

        if w.type == :error do
          raise CompileError,
            file: file,
            line: w_line,
            description: w.message
        end
      end)
    end
  end
end
