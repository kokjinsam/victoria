defmodule Victoria.ExUnitTest do
  use ExUnit.Case, async: false

  import Victoria.ExUnit

  alias Victoria.Spec
  alias Victoria.Test.BrokenCounterModel
  alias Victoria.Test.CounterModel
  alias Victoria.Test.TrackingCounterModel
  alias Victoria.Workflow.Runtime

  @fixtures Path.expand("fixtures", __DIR__)
  @traces Path.expand("traces", __DIR__)
  @fixture_executable Path.join(@fixtures, "apalache/fake-apalache")
  @source Path.expand("specs/Counter.tla", __DIR__)
  @config Path.expand("specs/Counter.cfg", __DIR__)
  @generated_at ~U[2026-07-20 12:34:56Z]

  defmodule IncompleteModel do
    @moduledoc false
    def init(state), do: {:ok, state}
  end

  setup do
    root = Path.join(System.tmp_dir!(), "victoria-ex-unit-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    {:ok, spec} = Spec.new(source: @source, config: @config)
    %{root: root, spec: spec}
  end

  test "returns :ok when the trace conforms" do
    assert :ok = assert_conform(CounterModel, trace: Path.join(@traces, "counter.itf.json"))
  end

  test "converts a Runner failure using its authoritative rendering" do
    path = fixture("counter_step_mismatch.itf.json")

    error =
      assert_raise ExUnit.AssertionError, fn ->
        assert_conform(BrokenCounterModel, trace: path)
      end

    assert error.message =~ "Victoria verification failure"
    assert error.message =~ "Model:\n  Victoria.Test.BrokenCounterModel"
    assert error.message =~ "Trace:\n  #{path}"
    assert error.message =~ "Step:\n  1"
    assert error.message =~ "Action:\n  Increment"
    assert error.message =~ ~s(Expected:\n  %{"count" => 2})
    assert error.message =~ ~s(Observed:\n  %{"count" => 0})
    assert error.message =~ "Reason:\n  states differ"
  end

  test "converts an ITF loading error using its authoritative rendering" do
    path = fixture("missing.itf.json")

    error =
      assert_raise ExUnit.AssertionError, fn ->
        assert_conform(CounterModel, trace: path)
      end

    assert error.message == "read error at #{path}: :enoent"
  end

  test "lets invalid-option ArgumentError propagate" do
    victoria_ex_unit = Victoria.ExUnit
    assert_raise ArgumentError, fn -> victoria_ex_unit.assert_conform(CounterModel, []) end
  end

  test "returns :ok after generated traces receive independent lifecycles", %{root: root, spec: spec} do
    executable = install_fake(root, "multiple")
    artifact_root = Path.join(root, "artifacts")

    assert :ok =
             assert_conform(TrackingCounterModel, spec,
               plan: valid_plan(),
               apalache: [executable: executable],
               artifacts: [root: artifact_root]
             )

    assert [run_name] = File.ls!(artifact_root)
    run_directory = Path.join(artifact_root, run_name)
    assert run_directory |> Path.join("victoria-run.json") |> File.regular?()
    assert [_first_trace, _second_trace] = run_directory |> Path.join("*.itf.json") |> Path.wildcard()

    for event <- lifecycle() ++ lifecycle() do
      assert_received ^event
    end
  end

  test "preserves later verification failure diagnostics and stops before the next trace", %{root: root, spec: spec} do
    executable = install_fake(root, "workflow-stop-first")

    error =
      assert_raise ExUnit.AssertionError, fn ->
        assert_conform(TrackingCounterModel, spec,
          plan: valid_plan(),
          apalache: [executable: executable],
          artifacts: [root: Path.join(root, "artifacts")]
        )
      end

    assert error.message =~ "Victoria workflow verification failed"
    assert error.message =~ "Model:\n  Victoria.Test.TrackingCounterModel"
    assert error.message =~ "Specification:\n  #{@source}"
    assert error.message =~ "Trace index:\n  1"
    assert error.message =~ "b-mismatch.itf.json"
    assert error.message =~ "Previously verified traces:\n  1"
    assert error.message =~ "Victoria verification failure"
    assert error.message =~ "Action:\n  Increment"
    assert error.message =~ ~s(Expected:\n  %{"count" => 2})
    assert error.message =~ ~s(Observed:\n  %{"count" => 1})

    for event <- lifecycle() ++ [:init, :cleanup] do
      assert_received ^event
    end

    refute_received :init
  end

  test "preserves first verification failure diagnostics and starts no later trace", %{root: root, spec: spec} do
    executable = install_fake(root, "workflow-first-failure")

    error =
      assert_raise ExUnit.AssertionError, fn ->
        assert_conform(TrackingCounterModel, spec,
          plan: valid_plan(),
          apalache: [executable: executable],
          artifacts: [root: Path.join(root, "artifacts")]
        )
      end

    assert error.message =~ "Trace index:\n  0"
    assert error.message =~ "Previously verified traces:\n  0"
    assert error.message =~ "a-mismatch.itf.json"
    assert_received :init
    assert_received :cleanup
    refute_received :init
  end

  test "converts a representative Apalache failure without starting verification", %{root: root, spec: spec} do
    missing = Path.join(root, "missing-apalache")

    error =
      assert_raise ExUnit.AssertionError, fn ->
        assert_conform(TrackingCounterModel, spec,
          plan: valid_plan(),
          apalache: [executable: missing],
          artifacts: [root: Path.join(root, "artifacts")]
        )
      end

    assert error.message =~ "Victoria workflow failed during Apalache execution"
    assert error.message =~ "Model:\n  Victoria.Test.TrackingCounterModel"
    assert error.message =~ "Specification:\n  #{@source}"
    assert error.message =~ "executable_discovery"
    refute_received :init
  end

  test "converts collision exhaustion and performs exactly eight attempts", %{root: root, spec: spec} do
    executable = install_fake(root, "valid")
    artifact_root = Path.join(root, "artifacts")
    suffixes = Enum.map(1..8, &String.pad_leading(Integer.to_string(&1, 16), 6, "0"))

    for suffix <- suffixes do
      directory = candidate(artifact_root, suffix)
      File.mkdir_p!(directory)
      directory |> Path.join("sentinel") |> File.write!(suffix)
    end

    error =
      assert_raise ExUnit.AssertionError, fn ->
        with_runtime(suffixes, fn ->
          assert_conform(TrackingCounterModel, spec,
            plan: valid_plan(),
            apalache: [executable: executable],
            artifacts: [root: artifact_root]
          )
        end)
      end

    assert error.message =~ "Victoria workflow could not allocate a unique run directory"
    assert error.message =~ "Attempts:\n  8"
    assert error.message =~ "Specification:\n  #{@source}"
    assert error.message =~ "run_directory_already_exists"
    assert error.message =~ candidate(artifact_root, "000008")
    assert Process.get(:ex_unit_test_suffixes) == []
    refute_received :init

    for suffix <- suffixes do
      directory = candidate(artifact_root, suffix)
      assert directory |> Path.join("sentinel") |> File.read!() == suffix
      refute directory |> Path.join("argv.txt") |> File.exists?()
    end
  end

  test "converts lasso rejection without initializing the implementation", %{root: root, spec: spec} do
    executable = install_fake(root, "lasso")

    error =
      assert_raise ExUnit.AssertionError, fn ->
        assert_conform(TrackingCounterModel, spec,
          plan: valid_plan(),
          apalache: [executable: executable],
          artifacts: [root: Path.join(root, "artifacts")]
        )
      end

    assert error.message =~ "Victoria workflow verification failed"
    assert error.message =~ "Trace index:\n  0"
    assert error.message =~ "unsupported_lasso"
    refute_received :init
  end

  test "lets generated-workflow ArgumentError exceptions propagate", %{root: root, spec: spec} do
    calls = [
      fn -> assert_conform(IncompleteModel, spec, plan: valid_plan()) end,
      fn -> assert_conform(CounterModel, :not_a_spec, plan: valid_plan()) end,
      fn -> assert_conform(CounterModel, spec, []) end,
      fn -> assert_conform(CounterModel, spec, plan: valid_plan(), unknown: true) end,
      fn -> assert_conform(CounterModel, spec, plan: %{}) end,
      fn -> assert_conform(CounterModel, spec, plan: [run_directory: root]) end
    ]

    for call <- calls do
      assert_raise ArgumentError, call
    end
  end

  defp fixture(name), do: Path.join(@fixtures, name)

  defp valid_plan, do: [mode: :simulate, length: 3, max_run: 2]

  defp lifecycle do
    [:init, {:execute, 1, "Increment"}, {:execute, 2, "Increment"}, {:execute, 3, "Decrement"}, :cleanup]
  end

  defp candidate(root, suffix) do
    root
    |> Path.expand()
    |> Path.join("20260720T123456Z-counter-#{suffix}")
  end

  defp with_runtime(suffixes, function) do
    Process.put(:ex_unit_test_suffixes, suffixes)

    suffix = fn ->
      [next | rest] = Process.get(:ex_unit_test_suffixes)
      Process.put(:ex_unit_test_suffixes, rest)
      next
    end

    Runtime.with_sources(fn -> @generated_at end, suffix, function)
  end

  defp install_fake(directory, name) do
    executable = Path.join(directory, name)
    File.cp!(@fixture_executable, executable)

    "counter.itf.json"
    |> fixture()
    |> File.cp!(Path.join(directory, "valid.itf.json"))

    "counter_step_mismatch.itf.json"
    |> fixture()
    |> File.cp!(Path.join(directory, "step-mismatch.itf.json"))

    "loop.itf.json"
    |> fixture()
    |> File.cp!(Path.join(directory, "loop.itf.json"))

    File.chmod!(executable, 0o755)
    Path.expand(executable)
  end
end
