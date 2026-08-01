defmodule Victoria.WorkflowTest do
  use ExUnit.Case, async: false

  alias Victoria.Runner.Failure
  alias Victoria.Spec
  alias Victoria.Test.CounterModel
  alias Victoria.Test.TrackingCounterModel
  alias Victoria.Workflow
  alias Victoria.Workflow.Error
  alias Victoria.Workflow.Result
  alias Victoria.Workflow.Runtime
  alias Victoria.Workflow.Verification

  @fixture_executable Path.expand("../fixtures/apalache/fake-apalache", __DIR__)
  @valid_trace Path.expand("../fixtures/counter.itf.json", __DIR__)
  @mismatch_trace Path.expand("../fixtures/counter_step_mismatch.itf.json", __DIR__)
  @malformed_trace Path.expand("../fixtures/malformed_json.itf.json", __DIR__)
  @unsupported_trace Path.expand("../fixtures/unsupported_set.itf.json", __DIR__)
  @loop_trace Path.expand("../fixtures/loop.itf.json", __DIR__)
  @source Path.expand("../specs/Counter.tla", __DIR__)
  @config Path.expand("../specs/Counter.cfg", __DIR__)
  @generated_at ~U[2026-07-20 12:34:56Z]

  defmodule StructuralModel do
    @moduledoc false
    def init(state), do: {:ok, state}

    def execute(%Victoria.Step{action: "Increment"}, %{"count" => count} = state) do
      {:ok, %{state | "count" => count + 1}}
    end

    def execute(%Victoria.Step{action: "Decrement"}, %{"count" => count} = state) do
      {:ok, %{state | "count" => count - 1}}
    end

    def snapshot(state), do: state
    def project(%Victoria.Step{state: state}), do: state
  end

  defmodule IncompleteModel do
    @moduledoc false
    def init(state), do: {:ok, state}
  end

  defmodule StopFirstModel do
    @moduledoc false
    def init(state) do
      send(self(), :workflow_init)
      CounterModel.init(state)
    end

    def execute(step, counter), do: CounterModel.execute(step, counter)
    def snapshot(counter), do: CounterModel.snapshot(counter)
    def project(step), do: CounterModel.project(step)

    def cleanup(counter) do
      send(self(), :workflow_cleanup)
      CounterModel.cleanup(counter)
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "victoria-workflow-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    {:ok, spec} = Spec.new(source: @source, config: @config)
    %{root: root, spec: spec}
  end

  test "accepts structural models and validates all programmer-facing input before reservation", %{root: root, spec: spec} do
    executable = install_fake(root, "valid")
    artifact_root = Path.join(root, "artifacts")

    invalid_calls = [
      fn -> Workflow.run("model", spec, plan: valid_plan()) end,
      fn -> Workflow.run(Victoria.WorkflowTest.Missing, spec, plan: valid_plan()) end,
      fn -> Workflow.run(IncompleteModel, spec, plan: valid_plan()) end,
      fn -> Workflow.run(StructuralModel, %{}, plan: valid_plan()) end,
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      fn -> apply(Workflow, :run, [StructuralModel, spec, %{}]) end,
      fn -> Workflow.run(StructuralModel, spec, []) end,
      fn -> Workflow.run(StructuralModel, spec, plan: valid_plan(), plan: valid_plan()) end,
      fn -> Workflow.run(StructuralModel, spec, plan: valid_plan(), unknown: true) end,
      fn -> Workflow.run(StructuralModel, spec, plan: %{}) end,
      fn -> Workflow.run(StructuralModel, spec, plan: [mode: :check, mode: :simulate]) end,
      fn -> Workflow.run(StructuralModel, spec, plan: [run_directory: root]) end,
      fn -> Workflow.run(StructuralModel, spec, plan: valid_plan(), apalache: %{}) end,
      fn -> Workflow.run(StructuralModel, spec, plan: valid_plan(), apalache: [executable: "a", executable: "b"]) end,
      fn -> Workflow.run(StructuralModel, spec, plan: valid_plan(), apalache: [environment: []]) end,
      fn -> Workflow.run(StructuralModel, spec, plan: valid_plan(), artifacts: %{}) end,
      fn -> Workflow.run(StructuralModel, spec, plan: valid_plan(), artifacts: [root: root, root: root]) end,
      fn -> Workflow.run(StructuralModel, spec, plan: valid_plan(), artifacts: [suffix: "abcdef"]) end,
      fn ->
        Workflow.run(StructuralModel, spec,
          plan: [mode: :check, length: -1],
          apalache: [executable: executable],
          artifacts: [root: artifact_root]
        )
      end
    ]

    for call <- invalid_calls do
      assert_raise ArgumentError, call
      refute File.exists?(artifact_root)
    end

    error = assert_raise ArgumentError, fn -> Workflow.run(IncompleteModel, spec, plan: valid_plan()) end
    assert error.message =~ "execute/2"
    assert error.message =~ "project/1"
    assert error.message =~ "snapshot/1"
  end

  test "builds and runs simulate and check plans through the existing boundaries", %{root: root, spec: spec} do
    executable = install_fake(root, "valid-nonzero")

    for {name, plan_options, expected_mode} <- [
          {"simulate", valid_plan(), :simulate},
          {"check", [mode: :check, length: 3], :check}
        ] do
      artifact_root = Path.join(root, name)

      assert {:ok,
              %Result{
                model: StructuralModel,
                apalache: apalache,
                verifications: [%Verification{trace_index: 0, report: report}]
              }} =
               with_runtime(["a1b2c3"], fn ->
                 Workflow.run(StructuralModel, spec,
                   plan: plan_options,
                   apalache: [executable: executable],
                   artifacts: [root: artifact_root]
                 )
               end)

      assert apalache.plan.mode == expected_mode
      assert apalache.exit_status == 12
      assert Path.dirname(apalache.plan.run_directory) == Path.expand(artifact_root)
      assert Path.basename(apalache.plan.run_directory) == "20260720T123456Z-counter-a1b2c3"
      assert report.trace_path == hd(apalache.trace_paths)

      assert apalache.plan.run_directory
             |> Path.join("apalachex-run.json")
             |> File.regular?()
    end
  end

  test "retries only exact directory collisions with one timestamp and eight total attempts", %{root: root, spec: spec} do
    executable = install_fake(root, "valid")
    artifact_root = Path.join(root, "artifacts")
    suffixes = Enum.map(1..8, &String.pad_leading(Integer.to_string(&1, 16), 6, "0"))

    for suffix <- Enum.take(suffixes, 2) do
      directory = candidate(artifact_root, suffix)
      File.mkdir_p!(directory)
      directory |> Path.join("sentinel") |> File.write!(suffix)
    end

    assert {:ok, %Result{apalache: apalache}} =
             with_runtime(suffixes, fn ->
               Workflow.run(CounterModel, spec,
                 plan: valid_plan(),
                 apalache: [executable: executable],
                 artifacts: [root: artifact_root]
               )
             end)

    assert apalache.plan.run_directory == candidate(artifact_root, Enum.at(suffixes, 2))
    assert artifact_root |> candidate(hd(suffixes)) |> Path.join("sentinel") |> File.read!() == hd(suffixes)
    assert_received {:workflow_clock, @generated_at}
    refute_received {:workflow_clock, _other}
    assert_received {:workflow_suffix, "000001"}
    assert_received {:workflow_suffix, "000002"}
    assert_received {:workflow_suffix, "000003"}
    refute_received {:workflow_suffix, _other}

    exhaustion_root = Path.join(root, "exhaustion")

    for suffix <- suffixes do
      exhaustion_root |> candidate(suffix) |> File.mkdir_p!()
    end

    assert {:error,
            %Error{
              phase: :run_directory,
              reason: {:run_directory_allocation_exhausted, 8, last_error}
            } = error} =
             with_runtime(suffixes, fn ->
               Workflow.run(CounterModel, spec,
                 plan: valid_plan(),
                 apalache: [executable: executable],
                 artifacts: [root: exhaustion_root]
               )
             end)

    assert %Apalachex.Error{
             phase: :run_directory,
             reason: :run_directory_already_exists,
             executable: ^executable,
             version: %Version{major: 0, minor: 58, patch: 3},
             exit_status: nil,
             output: nil,
             itf_paths: [],
             manifest_failure: nil
           } = last_error

    assert last_error.plan.run_directory == candidate(exhaustion_root, "000008")
    assert Exception.message(error) =~ "Attempts:\n  8"
    assert Process.get(:workflow_test_suffixes) == []

    for suffix <- suffixes do
      refute exhaustion_root |> candidate(suffix) |> Path.join("argv.txt") |> File.exists?()
    end
  end

  test "does not retry non-collision Apalache errors", %{root: root, spec: spec} do
    artifact_root = Path.join(root, "artifacts")
    missing = Path.join(root, "missing-apalache")

    assert {:error,
            %Error{
              phase: :apalache,
              reason:
                %Apalachex.Error{
                  phase: :executable_discovery,
                  reason: {:not_found, ^missing},
                  executable: nil,
                  version: nil,
                  exit_status: nil,
                  output: nil,
                  itf_paths: [],
                  manifest_failure: nil
                } = reason
            }} =
             with_runtime(["a1b2c3", "d4e5f6"], fn ->
               Workflow.run(CounterModel, spec,
                 plan: valid_plan(),
                 apalache: [executable: missing],
                 artifacts: [root: artifact_root]
               )
             end)

    assert reason.phase == :executable_discovery
    assert_received {:workflow_suffix, "a1b2c3"}
    refute_received {:workflow_suffix, "d4e5f6"}
    refute File.exists?(artifact_root)
  end

  test "preserves non-collision run-directory and spec-conversion errors intact", %{root: root, spec: spec} do
    executable = install_fake(root, "valid")
    blocked_root = Path.join(root, "blocked")
    File.write!(blocked_root, "file")

    assert {:error,
            %Error{
              phase: :run_directory,
              reason: %Apalachex.Error{
                phase: :run_directory,
                reason: {:parent_creation_failed, _reason},
                executable: ^executable,
                version: %Version{major: 0, minor: 58, patch: 3}
              }
            }} =
             with_runtime(["a1b2c3"], fn ->
               Workflow.run(CounterModel, spec,
                 plan: valid_plan(),
                 apalache: [executable: executable],
                 artifacts: [root: blocked_root]
               )
             end)

    source = Path.join(root, "Removed.tla")
    File.write!(source, "---- MODULE Removed ----\n====\n")
    {:ok, removed_spec} = Spec.new(source: source)
    File.rm!(source)

    assert {:error,
            %Error{
              phase: :apalache,
              reason: %Apalachex.Spec.Error{field: :source, path: ^source, reason: :not_found}
            }} =
             with_runtime(["d4e5f6"], fn ->
               Workflow.run(CounterModel, removed_spec,
                 plan: valid_plan(),
                 apalache: [executable: executable],
                 artifacts: [root: Path.join(root, "removed-artifacts")]
               )
             end)
  end

  test "verifies duplicate traces sequentially with fresh lifecycles", %{root: root, spec: spec} do
    executable = install_fake(root, "multiple")

    assert {:ok, %Result{apalache: apalache, verifications: verifications}} =
             with_runtime(["a1b2c3"], fn ->
               Workflow.run(TrackingCounterModel, spec,
                 plan: valid_plan(),
                 apalache: [executable: executable],
                 artifacts: [root: Path.join(root, "artifacts")]
               )
             end)

    assert Enum.map(verifications, & &1.trace_index) == [0, 1]
    assert Enum.map(verifications, & &1.trace_path) == apalache.trace_paths
    assert length(verifications) == length(apalache.traces)

    expected_lifecycle = [
      :init,
      {:execute, 1, "Increment"},
      {:execute, 2, "Increment"},
      {:execute, 3, "Decrement"},
      :cleanup
    ]

    for event <- expected_lifecycle ++ expected_lifecycle do
      assert_received ^event
    end
  end

  test "stops on the first verification failure and retains prior reports and all traces", %{root: root, spec: spec} do
    executable = install_fake(root, "workflow-stop-first")

    assert {:error,
            %Error{
              phase: :verification,
              reason: %Failure{},
              trace_index: 1,
              trace_path: trace_path,
              completed_verifications: [%Verification{trace_index: 0}],
              apalache: apalache
            } = error} =
             with_runtime(["a1b2c3"], fn ->
               Workflow.run(StopFirstModel, spec,
                 plan: valid_plan(),
                 apalache: [executable: executable],
                 artifacts: [root: Path.join(root, "artifacts")]
               )
             end)

    assert trace_path == Enum.at(apalache.trace_paths, 1)
    assert [_first_trace, _second_trace, _third_trace] = apalache.traces
    assert_received :workflow_init
    assert_received :workflow_cleanup
    assert_received :workflow_init
    assert_received :workflow_cleanup
    refute_received :workflow_init

    message = Exception.message(error)
    assert String.valid?(message)
    assert message =~ "Trace index:\n  1"
    assert message =~ "Previously verified traces:\n  1"
  end

  test "preserves lasso rejection as a workflow verification error", %{root: root, spec: spec} do
    executable = install_fake(root, "lasso")

    assert {:error,
            %Error{
              phase: :verification,
              reason: %Failure{phase: :trace_validation, reason: {:unsupported_lasso, 1}},
              trace_index: 0,
              completed_verifications: [],
              apalache: apalache
            }} =
             with_runtime(["a1b2c3"], fn ->
               Workflow.run(CounterModel, spec,
                 plan: valid_plan(),
                 apalache: [executable: executable],
                 artifacts: [root: Path.join(root, "artifacts")]
               )
             end)

    assert [_trace] = apalache.traces
  end

  test "production suffixes are six lowercase hexadecimal characters" do
    assert Runtime.suffix() =~ ~r/\A[0-9a-f]{6}\z/
  end

  defp valid_plan, do: [mode: :simulate, length: 3, max_run: 1]

  defp candidate(root, suffix) do
    root
    |> Path.expand()
    |> Path.join("20260720T123456Z-counter-#{suffix}")
  end

  defp with_runtime(suffixes, function) do
    Process.put(:workflow_test_suffixes, suffixes)

    generated_at = fn ->
      send(self(), {:workflow_clock, @generated_at})
      @generated_at
    end

    suffix = fn ->
      [next | rest] = Process.get(:workflow_test_suffixes)
      Process.put(:workflow_test_suffixes, rest)
      send(self(), {:workflow_suffix, next})
      next
    end

    Runtime.with_sources(generated_at, suffix, function)
  end

  defp install_fake(directory, name) do
    File.mkdir_p!(directory)
    executable = Path.join(directory, name)
    File.cp!(@fixture_executable, executable)
    File.cp!(@valid_trace, Path.join(directory, "valid.itf.json"))
    File.cp!(@mismatch_trace, Path.join(directory, "step-mismatch.itf.json"))
    File.cp!(@malformed_trace, Path.join(directory, "malformed.itf.json"))
    File.cp!(@unsupported_trace, Path.join(directory, "unsupported.itf.json"))
    File.cp!(@loop_trace, Path.join(directory, "loop.itf.json"))
    File.chmod!(executable, 0o755)
    Path.expand(executable)
  end
end
