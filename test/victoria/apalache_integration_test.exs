defmodule Victoria.ApalacheIntegrationTest do
  use ExUnit.Case, async: false

  alias Victoria.Apalache
  alias Victoria.Apalache.Plan
  alias Victoria.Apalache.Result
  alias Victoria.Spec
  alias Victoria.Test.CounterModel

  @moduletag :apalache

  @counter_source Path.expand("../specs/Counter.tla", __DIR__)
  @counter_config Path.expand("../specs/Counter.cfg", __DIR__)
  @violation_source Path.expand("../apalache/Violation.tla", __DIR__)
  @violation_config Path.expand("../apalache/Violation.cfg", __DIR__)

  setup do
    executable =
      System.find_executable("apalache-mc") ||
        flunk("Apalache v0.58.3 must be installed on PATH for @tag :apalache tests")

    root = Path.join(System.tmp_dir!(), "victoria-real-apalache-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    %{executable: executable, root: root}
  end

  test "simulates Counter into validated traces and verifies every trace", context do
    {source, config} = copy_spec(context.root, "Counter", @counter_source, @counter_config)
    {:ok, spec} = Spec.new(source: source, config: config)
    run_directory = Path.join(context.root, "simulate-run")

    plan =
      Plan.new(spec,
        mode: :simulate,
        length: 3,
        max_run: 1,
        run_directory: run_directory
      )

    assert {:ok,
            %Result{
              executable: executable,
              version: %Version{major: 0, minor: 58, patch: 3},
              exit_status: 0,
              trace_paths: [_trace_path | _trace_paths] = trace_paths,
              traces: [_trace | _traces] = traces
            }} = Apalache.run(plan)

    assert executable == Path.expand(context.executable)
    assert length(trace_paths) == length(traces)

    for trace <- traces do
      assert {:ok, _report} = Victoria.verify(CounterModel, trace: trace)
    end
  end

  test "returns a successful materialization for a nonzero counterexample check", context do
    {source, config} = copy_spec(context.root, "Violation", @violation_source, @violation_config)
    {:ok, spec} = Spec.new(source: source, config: config)

    plan =
      Plan.new(spec,
        mode: :check,
        length: 3,
        run_directory: Path.join(context.root, "check-run")
      )

    assert {:ok,
            %Result{
              exit_status: 12,
              trace_paths: [_trace_path | _trace_paths],
              traces: [_trace | _traces] = traces
            }} =
             Apalache.run(plan)

    for trace <- traces do
      assert {:ok, _report} = Victoria.verify(CounterModel, trace: trace)
    end
  end

  defp copy_spec(root, name, source, config) do
    directory = Path.join(root, String.downcase(name))
    File.mkdir_p!(directory)
    copied_source = Path.join(directory, "#{name}.tla")
    copied_config = Path.join(directory, "#{name}.cfg")
    File.cp!(source, copied_source)
    File.cp!(config, copied_config)
    {copied_source, copied_config}
  end
end
