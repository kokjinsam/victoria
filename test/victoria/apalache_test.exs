defmodule Victoria.ApalacheTest do
  use ExUnit.Case, async: false

  alias Victoria.Apalache
  alias Victoria.Apalache.Error
  alias Victoria.Apalache.Plan
  alias Victoria.Apalache.Result
  alias Victoria.ITF
  alias Victoria.Spec

  @fixture_executable Path.expand("../fixtures/apalache/fake-apalache", __DIR__)
  @source Path.expand("../specs/Counter.tla", __DIR__)
  @config Path.expand("../specs/Counter.cfg", __DIR__)

  setup do
    root = Path.join(System.tmp_dir!(), "victoria-apalache-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "raises for compatibility-facade API misuse", %{root: root} do
    plan = plan(Path.join(root, "run"))

    for call <- [
          fn -> Apalache.run(%{}, []) end,
          fn -> Apalache.run(plan, %{executable: "tool"}) end,
          fn -> Apalache.run(plan, executable: "a", executable: "b") end,
          fn -> Apalache.run(plan, unknown: true) end,
          fn -> Apalache.run(plan, executable: "") end
        ] do
      assert_raise ArgumentError, call
    end
  end

  test "preserves Victoria results for successful simulate and check runs", %{root: root} do
    executable = install_fake(root, "valid-nonzero")

    for {mode, options} <- [
          simulate: [mode: :simulate, length: 3, max_run: 2],
          check: [mode: :check, length: 3]
        ] do
      run_directory = Path.join(root, Atom.to_string(mode))
      original_plan = plan(run_directory, options)

      assert {:ok,
              %Result{
                plan: ^original_plan,
                executable: ^executable,
                version: %Version{major: 0, minor: 58, patch: 3},
                exit_status: 12,
                output: output,
                trace_paths: [trace_path],
                traces: [trace]
              }} = Apalache.run(original_plan, executable: executable)

      assert output == "standard output\nstandard error\n"
      assert trace.source == trace_path
      assert Path.dirname(trace_path) == run_directory

      assert %{
               "outcome" => "materialized",
               "plan" => %{"mode" => manifest_mode},
               "execution" => %{"exit_status" => 12},
               "artifacts" => %{"itf_paths" => ["trace.itf.json"]}
             } = read_manifest(run_directory)

      assert manifest_mode == Atom.to_string(mode)
      refute run_directory |> Path.join("victoria-run.json") |> File.exists?()
    end
  end

  test "loads Apalachex ITF paths in their returned order", %{root: root} do
    executable = install_fake(root, "multiple")

    assert {:ok, %Result{trace_paths: paths, traces: traces}} =
             root
             |> Path.join("run")
             |> plan()
             |> Apalache.run(executable: executable)

    assert Enum.map(paths, &Path.basename/1) == ["a.itf.json", "z.itf.json"]
    assert Enum.map(traces, & &1.source) == paths

    assert root |> Path.join("run") |> read_manifest() |> get_in(["artifacts", "itf_paths"]) ==
             ["a.itf.json", "z.itf.json"]
  end

  test "returns Victoria's trace-loading error while retaining materialized execution evidence", %{root: root} do
    executable = install_fake(root, "mixed")
    run_directory = Path.join(root, "run")
    original_plan = plan(run_directory)

    assert {:error,
            %Error{
              plan: ^original_plan,
              phase: :trace_loading,
              reason: {:invalid_trace, invalid_path, %ITF.Error{source: invalid_path}},
              executable: ^executable,
              version: %Version{major: 0, minor: 58, patch: 3},
              exit_status: 0,
              output: "standard output\nstandard error\n",
              trace_paths: paths
            }} = Apalache.run(original_plan, executable: executable)

    assert Enum.map(paths, &Path.basename/1) == ["a-valid.itf.json", "b-invalid.itf.json"]
    assert Path.basename(invalid_path) == "b-invalid.itf.json"

    assert %{
             "outcome" => "materialized",
             "artifacts" => %{"itf_paths" => ["a-valid.itf.json", "b-invalid.itf.json"]},
             "failure" => nil
           } = read_manifest(run_directory)

    refute run_directory |> Path.join("victoria-run.json") |> File.exists?()
  end

  test "returns upstream execution errors intact", %{root: root} do
    missing = Path.join(root, "missing-apalache")
    original_plan = plan(Path.join(root, "run"))

    assert {:error,
            %Apalachex.Error{
              phase: :executable_discovery,
              reason: {:not_found, ^missing},
              executable: nil,
              version: nil,
              exit_status: nil,
              output: nil,
              itf_paths: [],
              manifest_failure: nil
            } = error} = Apalache.run(original_plan, executable: missing)

    assert error.plan.spec.source == original_plan.spec.source
    assert error.plan.run_directory == original_plan.run_directory
  end

  test "returns upstream spec conversion errors intact", %{root: root} do
    source = Path.join(root, "Removed.tla")
    File.write!(source, "---- MODULE Removed ----\n====\n")

    original_plan =
      Plan.new(%Spec{source: source, config: nil}, mode: :check, length: 1, run_directory: Path.join(root, "run"))

    File.rm!(source)

    assert {:error, %Apalachex.Spec.Error{field: :source, path: ^source, reason: :not_found}} =
             Apalache.run(original_plan, executable: Path.join(root, "unused"))
  end

  defp plan(run_directory, options \\ [mode: :simulate, length: 3, max_run: 2]) do
    Plan.new(
      %Spec{source: @source, config: @config},
      Keyword.put(options, :run_directory, run_directory)
    )
  end

  defp install_fake(directory, name) do
    executable = Path.join(directory, name)
    File.cp!(@fixture_executable, executable)

    for {source, target} <- [
          {"counter.itf.json", "valid.itf.json"},
          {"malformed_json.itf.json", "malformed.itf.json"},
          {"counter_step_mismatch.itf.json", "step-mismatch.itf.json"},
          {"loop.itf.json", "loop.itf.json"}
        ] do
      "../fixtures/#{source}"
      |> Path.expand(__DIR__)
      |> File.cp!(Path.join(directory, target))
    end

    File.chmod!(executable, 0o755)
    Path.expand(executable)
  end

  defp read_manifest(run_directory) do
    run_directory
    |> Path.join("apalachex-run.json")
    |> File.read!()
    |> JSON.decode!()
  end
end
