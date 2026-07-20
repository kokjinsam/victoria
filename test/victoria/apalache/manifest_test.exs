defmodule Victoria.Apalache.ManifestTest do
  use ExUnit.Case, async: true

  alias Victoria.Apalache.Error
  alias Victoria.Apalache.Manifest
  alias Victoria.Apalache.Plan
  alias Victoria.Apalache.Result
  alias Victoria.Spec

  @source Path.expand("../../specs/Counter.tla", __DIR__)
  @config Path.expand("../../specs/Counter.cfg", __DIR__)
  @version Version.parse!("0.58.3")

  setup do
    root = Path.join(System.tmp_dir!(), "victoria-manifest-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "builds the complete running schema with explicit nulls", %{root: root} do
    plan = plan(Path.join(root, "run"))
    started_at = ~U[2026-07-20 12:34:56.123456Z]
    manifest = Manifest.running(plan, "/opt/apalache-mc", @version, started_at)

    assert manifest |> Map.keys() |> Enum.sort() ==
             Enum.sort(
               ~w(artifacts completed_at execution failure outcome plan producer schema schema_version spec started_at status)
             )

    assert manifest["schema"] == "victoria.apalache.run"
    assert manifest["schema_version"] == 1
    assert manifest["status"] == "running"
    assert manifest["outcome"] == nil
    assert manifest["completed_at"] == nil
    assert manifest["producer"] == %{"name" => "victoria", "version" => "0.1.0"}
    assert manifest["spec"] == %{"source" => @source, "config" => @config}

    assert manifest["plan"] == %{
             "mode" => "simulate",
             "working_directory" => Path.dirname(@source),
             "run_directory" => plan.run_directory,
             "options" => %{"length" => 2, "max_run" => 1},
             "argv" => plan.argv
           }

    assert manifest["execution"] == %{
             "executable" => "/opt/apalache-mc",
             "apalache_version" => "0.58.3",
             "exit_status" => nil,
             "output" => nil
           }

    assert manifest["artifacts"] == %{"trace_paths" => []}
    assert manifest["failure"] == nil
  end

  test "uses a null config and clamps a reversed completion timestamp", %{root: root} do
    plan = plan(Path.join(root, "run"), nil)
    started_at = ~U[2026-07-20 12:34:56.123456Z]
    completed_at = DateTime.add(started_at, -1, :second)
    result = result(plan, 0, "output", [Path.join(plan.run_directory, "trace.itf.json")])

    manifest = Manifest.completed(plan, "/opt/apalache-mc", @version, started_at, completed_at, {:ok, result})

    assert manifest["status"] == "completed"
    assert manifest["outcome"] == "materialized"
    assert manifest["completed_at"] == manifest["started_at"]
    assert manifest["spec"]["config"] == nil
    assert manifest["execution"]["exit_status"] == 0

    assert manifest["execution"]["output"] == %{
             "byte_size" => 6,
             "tail" => "output",
             "tail_truncated" => false
           }

    assert manifest["artifacts"]["trace_paths"] == ["trace.itf.json"]
  end

  test "builds a compact failed manifest with a relative failing trace", %{root: root} do
    plan = plan(Path.join(root, "run"))
    path = Path.join(plan.run_directory, "bad.itf.json")

    error = %Error{
      plan: plan,
      phase: :trace_loading,
      reason: {:invalid_trace, path, :fixture},
      executable: "/opt/apalache-mc",
      version: @version,
      exit_status: 12,
      output: "failure output",
      trace_paths: [path]
    }

    manifest =
      Manifest.completed(plan, "/opt/apalache-mc", @version, DateTime.utc_now(), DateTime.utc_now(), {:error, error})

    assert manifest["status"] == "completed"
    assert manifest["outcome"] == "failed"
    assert manifest["failure"]["phase"] == "trace_loading"
    assert manifest["failure"]["reason"] == "invalid_trace"
    assert manifest["failure"]["trace_path"] == "bad.itf.json"
    assert String.valid?(manifest["failure"]["message"])
  end

  test "creates and atomically replaces newline-terminated JSON without leftover temporary files", %{root: root} do
    path = Path.join(root, "victoria-run.json")

    assert :ok = Manifest.write_atomic(path, %{"status" => "running"})
    assert {:ok, %{"status" => "running"}} = path |> File.read!() |> JSON.decode()
    assert path |> File.read!() |> String.ends_with?("\n")

    assert :ok = Manifest.write_atomic(path, %{"status" => "completed"})
    assert {:ok, %{"status" => "completed"}} = path |> File.read!() |> JSON.decode()
    assert root |> File.ls!() |> Enum.filter(&String.starts_with?(&1, ".victoria-run.json.tmp-")) == []
  end

  test "does not fall back to an in-place write when replacement fails", %{root: root} do
    path = Path.join(root, "victoria-run.json")
    File.mkdir!(path)
    sentinel = Path.join(path, "complete.json")
    File.write!(sentinel, "complete\n")

    assert {:error, {:write, _reason}} = Manifest.write_atomic(path, %{"status" => "completed"})
    assert File.read!(sentinel) == "complete\n"
    assert root |> File.ls!() |> Enum.filter(&String.starts_with?(&1, ".victoria-run.json.tmp-")) == []
  end

  test "turns JSON encoding failures into structured results", %{root: root} do
    path = Path.join(root, "victoria-run.json")

    assert {:error, {:encoding, _exception}} = Manifest.write_atomic(path, %{"unsupported" => self()})
    refute File.exists?(path)
  end

  defp plan(run_directory, config \\ @config) do
    Plan.new(%Spec{source: @source, config: config},
      mode: :simulate,
      length: 2,
      max_run: 1,
      run_directory: run_directory
    )
  end

  defp result(plan, exit_status, output, trace_paths) do
    %Result{
      plan: plan,
      executable: "/opt/apalache-mc",
      version: @version,
      exit_status: exit_status,
      output: output,
      trace_paths: trace_paths,
      traces: []
    }
  end
end
