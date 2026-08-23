defmodule Mix.Tasks.Dala.VerifyTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  defp run_task_and_capture(args) do
    capture_io(:stdio, fn ->
      Mix.Task.rerun("dala.verify", args)
    end)
  end

  test "--components lists the component vocabulary" do
    output = run_task_and_capture(["--components"])
    text = output

    assert text =~ "column"
    assert text =~ "text"
    assert text =~ "button"
  end

  test "--dsl reports on compiled screen modules" do
    output = run_task_and_capture(["--dsl"])
    text = output

    # The dala project compiles many Spark screens — either they are checked
    # or (if none loaded yet) a friendly hint is printed.
    assert text =~ ~r/Verifying Dala DSL|No Dala screen modules/
  end

  test "default run performs all verifications without crashing" do
    output = run_task_and_capture([])
    text = output

    assert text =~ "Running all Dala verifications"
  end

  test "--components --markdown_output emits a markdown table" do
    output =
      run_task_and_capture([
        "--components",
        "--markdown_output",
        "/tmp/dala_verify_components.md"
      ])

    text = output

    assert File.exists?("/tmp/dala_verify_components.md")
    on_exit(fn -> File.rm("/tmp/dala_verify_components.md") end)

    assert text =~ "Wrote /tmp/dala_verify_components.md"
  end
end
