defmodule Victoria.ApalacheIntegrationTest do
  use ExUnit.Case, async: false

  alias Victoria.Apalache
  alias Victoria.Apalache.Manifest
  alias Victoria.Apalache.Plan
  alias Victoria.Apalache.Result
  alias Victoria.Spec
  alias Victoria.Test.CounterModel
  alias Victoria.Test.TrackingCounterModel
  alias Victoria.Workflow

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

  test "runs the complete generated conformance workflow", context do
    {source, config} = copy_spec(context.root, "Counter", @counter_source, @counter_config)
    {:ok, spec} = Spec.new(source: source, config: config)
    artifact_root = Path.join(context.root, "workflow-runs")

    assert {:ok,
            %Workflow.Result{
              model: TrackingCounterModel,
              apalache:
                %Result{
                  version: %Version{major: 0, minor: 58, patch: 3},
                  trace_paths: [_trace_path | _trace_paths] = trace_paths,
                  traces: [_trace | _traces] = traces
                } = apalache,
              verifications: [%Workflow.Verification{} | _verifications] = verifications
            }} =
             Workflow.run(TrackingCounterModel, spec,
               plan: [mode: :simulate, length: 3, max_run: 1],
               artifacts: [root: artifact_root]
             )

    assert Path.dirname(apalache.plan.run_directory) == Path.expand(artifact_root)
    assert apalache.plan |> Manifest.path() |> File.regular?()
    assert length(verifications) == length(traces)
    assert Enum.map(verifications, & &1.trace_path) == trace_paths
    assert Enum.map(verifications, & &1.trace_index) == Enum.to_list(0..(length(traces) - 1))

    messages = self() |> Process.info(:messages) |> elem(1)
    assert Enum.count(messages, &(&1 == :init)) == length(traces)
    assert Enum.count(messages, &(&1 == :cleanup)) == length(traces)
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
