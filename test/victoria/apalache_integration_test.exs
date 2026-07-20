defmodule Victoria.ApalacheIntegrationTest do
  use ExUnit.Case, async: false

  import Victoria.ExUnit

  alias Victoria.Apalache
  alias Victoria.Apalache.Plan
  alias Victoria.Apalache.Result
  alias Victoria.Spec
  alias Victoria.Test.CounterModel
  alias Victoria.Test.TrackingCounterModel

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

    manifest = read_manifest(run_directory)
    assert manifest["status"] == "completed"
    assert manifest["outcome"] == "materialized"
    assert manifest["execution"]["exit_status"] == 0
    assert manifest["artifacts"]["trace_paths"] == Enum.map(trace_paths, &Path.basename/1)

    for trace <- traces do
      assert {:ok, _report} = Victoria.verify(CounterModel, trace: trace)
    end
  end

  test "returns a successful materialization for a nonzero counterexample check", context do
    {source, config} = copy_spec(context.root, "Violation", @violation_source, @violation_config)
    {:ok, spec} = Spec.new(source: source, config: config)

    run_directory = Path.join(context.root, "check-run")

    plan =
      Plan.new(spec,
        mode: :check,
        length: 3,
        run_directory: run_directory
      )

    assert {:ok,
            %Result{
              exit_status: 12,
              trace_paths: [_trace_path | _trace_paths],
              traces: [_trace | _traces] = traces
            }} =
             Apalache.run(plan)

    manifest = read_manifest(run_directory)
    assert manifest["status"] == "completed"
    assert manifest["outcome"] == "materialized"
    assert manifest["execution"]["exit_status"] == 12

    for trace <- traces do
      assert {:ok, _report} = Victoria.verify(CounterModel, trace: trace)
    end
  end

  test "asserts conformance through a real generated workflow", context do
    {source, config} = copy_spec(context.root, "Counter", @counter_source, @counter_config)
    {:ok, spec} = Spec.new(source: source, config: config)
    artifact_root = Path.join(context.root, "workflow-runs")

    assert :ok =
             assert_conform(TrackingCounterModel, spec,
               plan: [mode: :simulate, length: 3, max_run: 1],
               artifacts: [root: artifact_root]
             )

    assert [run_name] = File.ls!(artifact_root)
    run_directory = Path.join(artifact_root, run_name)
    manifest = read_manifest(run_directory)
    trace_paths = manifest["artifacts"]["trace_paths"]

    assert run_directory |> Path.join("victoria-run.json") |> File.regular?()
    assert manifest["status"] == "completed"
    assert manifest["outcome"] == "materialized"
    assert manifest["execution"]["apalache_version"] == "0.58.3"
    assert [_trace_path | _trace_paths] = trace_paths

    for trace_path <- trace_paths do
      assert run_directory |> Path.join(trace_path) |> File.regular?()
    end

    messages = self() |> Process.info(:messages) |> elem(1)
    assert Enum.count(messages, &(&1 == :init)) == length(trace_paths)
    assert Enum.count(messages, &(&1 == :cleanup)) == length(trace_paths)
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

  defp read_manifest(run_directory) do
    run_directory
    |> Path.join("victoria-run.json")
    |> File.read!()
    |> JSON.decode!()
  end
end
