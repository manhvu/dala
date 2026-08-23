defmodule Dala.Spark.DslVerifierInternalsTest do
  @moduledoc """
  Covers verifier pieces the DSL tests only touch indirectly:
  beam-based handler extraction, report formatting, attribute validation
  and the fuzzy prop-name matcher.
  """

  use ExUnit.Case, async: false

  # Real beam on disk (compiled via elixirc_paths :test) so the beam_lib
  # debug-info path in defined_handlers/1 is exercised.
  @fixture Dala.TestSupport.VerifierFixtureScreen

  describe "defined_handlers/1" do
    test "extracts handle_event clause heads from compiled debug info" do
      handlers = Dala.Spark.DslVerifier.defined_handlers(@fixture)
      assert :increment in handlers
      assert :dead_handler in handlers
      refute :nonexistent in handlers
    end

    test "returns [] for modules without a beam on disk" do
      assert Dala.Spark.DslVerifier.defined_handlers(:definitely_not_compiled) == []
    end

    test "unused handler is flagged via verify_module (inverse check)" do
      warnings = Dala.Spark.DslVerifier.verify_module(@fixture)

      assert %{} = dead = Enum.find(warnings, &String.contains?(&1.message, "dead_handler"))
      assert dead.type == :info
      assert String.contains?(dead.message, "never referenced")
    end

    test "missing handler is reported as a warning" do
      warnings = Dala.Spark.DslVerifier.verify_module(@fixture)

      assert %{} = missing = Enum.find(warnings, &String.contains?(&1.message, ":reset_missing"))
      assert missing.type == :warning
    end

    test "referenced-and-defined handlers produce no diagnostics" do
      warnings = Dala.Spark.DslVerifier.verify_module(@fixture)
      refute Enum.any?(warnings, &String.contains?(&1.message, ":increment"))
    end
  end

  describe "handler_warnings/1 (after_verify entry point)" do
    test "reports missing and unused handlers for a compiled fixture" do
      warnings = Dala.Spark.DslVerifier.handler_warnings(@fixture)

      assert Enum.any?(
               warnings,
               &(&1.type == :warning and String.contains?(&1.message, ":reset_missing"))
             )

      assert Enum.any?(
               warnings,
               &(&1.type == :info and String.contains?(&1.message, ":dead_handler"))
             )
    end

    test "returns [] for modules without a beam or __spark_dsl__" do
      assert Dala.Spark.DslVerifier.handler_warnings(:no_such_screen) == []
    end
  end

  describe "attribute verification" do
    test "unsupported attribute types are reported" do
      warnings =
        Dala.Spark.DslVerifier.verify_from_raw(
          SomeModule,
          [],
          [%{name: :bad, type: :nonsense_type, default: nil}],
          []
        )

      assert Enum.any?(warnings, &(&1.type == :error and String.contains?(&1.message, "bad")))
    end

    test "supported attribute types pass silently" do
      warnings =
        Dala.Spark.DslVerifier.verify_from_raw(
          SomeModule,
          [],
          [%{name: :ok, type: :integer, default: 0}],
          []
        )

      assert warnings == []
    end
  end

  describe "fuzzy prop-name suggestions (via verify_from_raw)" do
    defp verify_prop(key) do
      Dala.Spark.DslVerifier.verify_from_raw(
        SomeModule,
        [%{type: :column, props: %{key => :value}, children: [], line: 1}],
        [],
        []
      )
    end

    test "close typos get a Did-you-mean suggestion" do
      warnings = verify_prop(:gaap)

      assert %{message: msg} =
               Enum.find(warnings, &String.contains?(&1.message, "Unknown prop :gaap"))

      assert String.contains?(msg, "Did you mean")
    end

    test "unrelated prop names get no suggestion" do
      warnings = verify_prop(:zzzzzzzz)

      assert %{message: msg} =
               Enum.find(warnings, &String.contains?(&1.message, "Unknown prop :zzzzzzzz"))

      refute String.contains?(msg, "Did you mean")
    end

    test "non-atom prop keys are reported" do
      warnings =
        Dala.Spark.DslVerifier.verify_from_raw(
          SomeModule,
          [%{type: :column, props: %{"string_key" => 1}, children: [], line: 2}],
          [],
          []
        )

      assert Enum.any?(warnings, &String.contains?(&1.message, "should be an atom"))
    end
  end

  describe "print_warnings/1" do
    test "prints each warning with a type prefix via the Mix shell" do
      warnings = [
        %{type: :warning, module: Foo, line: 3, message: "watch out"},
        %{type: :info, module: Foo, line: 0, message: "fyi"}
      ]

      shell = Mix.shell()
      Mix.shell(Mix.Shell.Process)

      try do
        Dala.Spark.DslVerifier.print_warnings(warnings)
      after
        Mix.shell(shell)
      end

      assert_received {:mix_shell, :info, [warn_line]}
      assert warn_line =~ "⚠"
      assert warn_line =~ "line 3"

      assert_received {:mix_shell, :info, [info_line]}
      assert info_line =~ "ℹ"
      refute info_line =~ "line"
    end
  end
end
