defmodule Victoria.WorkflowIntegrationTest do
  use ExUnit.Case, async: false

  import Victoria.ExUnit

  alias Victoria.Spec
  alias Victoria.Test.CounterModel
  alias Victoria.Test.TrackingCounterModel
  alias Victoria.Workflow
  alias Victoria.Workflow.Result

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

    "../../.tool-versions"
    |> Path.expand(__DIR__)
    |> File.cp!(Path.join(root, ".tool-versions"))

    on_exit(fn -> File.rm_rf!(root) end)

    %{executable: executable, root: root}
  end

  test "simulates Counter into validated traces and verifies every trace", context do
    {source, config} = copy_spec(context.root, "Counter", @counter_source, @counter_config)
    {:ok, spec} = Spec.new(source: source, config: config)
    artifact_root = Path.join(context.root, "simulate-runs")

    assert {:ok,
            %Result{
              apalache: %Apalachex.Result{
                executable: executable,
                version: %Version{major: 0, minor: 58, patch: 3},
                exit_status: 0,
                itf_paths: [_itf_path | _itf_paths] = itf_paths
              },
              verifications: [_verification | _verifications] = verifications
            }} =
             Workflow.run(CounterModel, spec,
               plan: [mode: :simulate, length: 3, max_run: 1],
               artifacts: [root: artifact_root]
             )

    assert executable == Path.expand(context.executable)
    assert length(itf_paths) == length(verifications)
    assert Enum.map(verifications, & &1.trace_path) == itf_paths

    assert [run_name] = File.ls!(artifact_root)
    run_directory = Path.join(artifact_root, run_name)
    manifest = read_manifest(run_directory)
    assert manifest["status"] == "completed"
    assert manifest["outcome"] == "materialized"
    assert manifest["execution"]["exit_status"] == 0
    assert manifest["artifacts"]["itf_paths"] == Enum.map(itf_paths, &Path.basename/1)
  end

  test "returns a successful materialization for a nonzero counterexample check", context do
    {source, config} = copy_spec(context.root, "Violation", @violation_source, @violation_config)
    {:ok, spec} = Spec.new(source: source, config: config)

    artifact_root = Path.join(context.root, "check-runs")

    assert {:ok,
            %Result{
              apalache: %Apalachex.Result{exit_status: 12, itf_paths: [_itf_path | _itf_paths]},
              verifications: [_verification | _verifications]
            }} =
             Workflow.run(CounterModel, spec,
               plan: [mode: :check, length: 3],
               artifacts: [root: artifact_root]
             )

    assert [run_name] = File.ls!(artifact_root)
    run_directory = Path.join(artifact_root, run_name)
    manifest = read_manifest(run_directory)
    assert manifest["status"] == "completed"
    assert manifest["outcome"] == "materialized"
    assert manifest["execution"]["exit_status"] == 12
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
    itf_paths = manifest["artifacts"]["itf_paths"]

    assert run_directory |> Path.join("apalachex-run.json") |> File.regular?()
    refute run_directory |> Path.join("victoria-run.json") |> File.exists?()
    assert manifest["status"] == "completed"
    assert manifest["outcome"] == "materialized"
    assert manifest["execution"]["apalache_version"] == "0.58.3"
    assert [_itf_path | _itf_paths] = itf_paths

    for itf_path <- itf_paths do
      assert run_directory |> Path.join(itf_path) |> File.regular?()
    end

    messages = self() |> Process.info(:messages) |> elem(1)
    assert Enum.count(messages, &(&1 == :init)) == length(itf_paths)
    assert Enum.count(messages, &(&1 == :cleanup)) == length(itf_paths)
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
    |> Path.join("apalachex-run.json")
    |> File.read!()
    |> JSON.decode!()
  end
end
