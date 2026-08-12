defmodule Victoria.RunnerTest do
  use ExUnit.Case, async: true

  alias Victoria.Runner
  alias Victoria.Runner.Failure
  alias Victoria.Runner.Report
  alias Victoria.Test.BrokenCounterModel
  alias Victoria.Test.CleanupErrorModel
  alias Victoria.Test.CounterModel
  alias Victoria.Test.ExecuteErrorModel
  alias Victoria.Test.InitErrorModel
  alias Victoria.Test.InitialMismatchModel
  alias Victoria.Test.InvalidSnapshotModel
  alias Victoria.Test.RaisedProjectModel
  alias Victoria.Test.ThreadingModel
  alias Victoria.Test.TrackingCounterModel

  @fixtures Path.expand("fixtures", __DIR__)
  @traces Path.expand("traces", __DIR__)

  defmodule NumericProjectionModel do
    @moduledoc false
    @behaviour Victoria.Model

    @impl Victoria.Model
    defdelegate init(state), to: CounterModel

    @impl Victoria.Model
    defdelegate execute(step, counter), to: CounterModel

    @impl Victoria.Model
    defdelegate snapshot(counter), to: CounterModel

    @impl Victoria.Model
    def project(%Victoria.Step{action: "Initial", state: state}), do: state
    def project(%Victoria.Step{state: %{"count" => count}}), do: %{"count" => count * 1.0}

    @impl Victoria.Model
    defdelegate cleanup(counter), to: CounterModel
  end

  defmodule ParameterModel do
    @moduledoc false
    @behaviour Victoria.Model

    @impl Victoria.Model
    def init(state) do
      send(self(), {:initialized_with, state})
      {:ok, state}
    end

    @impl Victoria.Model
    def execute(%Victoria.Step{state: state}, _implementation), do: {:ok, state}

    @impl Victoria.Model
    def snapshot(state), do: state

    @impl Victoria.Model
    def project(%Victoria.Step{state: state}), do: state
  end

  test "replays real Apalache output through the complete Counter vertical slice" do
    trace_path = Path.join(@traces, "counter.itf.json")
    assert {:ok, trace} = Victoria.Trace.load(trace_path)

    assert {:ok,
            %Report{
              trace_path: ^trace_path,
              model: CounterModel,
              step_count: 4,
              executed_count: 3
            }} = Runner.replay(trace, CounterModel)
  end

  test "passes normalized parameters and variables together to Model.init/1" do
    assert {:ok, %Report{step_count: 2, executed_count: 1}} =
             replay("formal_values.itf.json", ParameterModel)

    assert_received {:initialized_with,
                     %{
                       "Limit" => 123,
                       "value" => %{
                         "opaque" => "UNIT",
                         "uninterpreted" => "Node(1)",
                         "nested" => [true, %{"number" => -12}]
                       }
                     }}
  end

  test "threads the opaque implementation and cleans up its final value once" do
    assert {:ok, %Report{executed_count: 3}} = replay("counter.itf.json", ThreadingModel)

    assert_received {:cleaned_up, 1}
    refute_received {:cleaned_up, _count}
  end

  test "reports an exact initial verification failure and never executes Initial" do
    trace_path = fixture("counter_initial_mismatch.itf.json")
    assert {:ok, trace} = Victoria.Trace.load(trace_path)

    assert {:error,
            %Failure{
              trace_path: ^trace_path,
              model: InitialMismatchModel,
              phase: :initial_verification,
              reason: :states_differ,
              step_index: 0,
              action: "Initial",
              expected: %{"count" => 3},
              observed: %{"count" => 4}
            }} = Runner.replay(trace, InitialMismatchModel)

    refute_received :initial_was_executed
  end

  test "stops at the first step verification failure and renders useful context" do
    trace_path = fixture("counter_step_mismatch.itf.json")
    assert {:ok, trace} = Victoria.Trace.load(trace_path)

    assert {:error,
            %Failure{
              trace_path: ^trace_path,
              model: BrokenCounterModel,
              phase: :step_verification,
              reason: :states_differ,
              step_index: 1,
              action: "Increment",
              expected: %{"count" => 2},
              observed: %{"count" => 0}
            } = failure} = Runner.replay(trace, BrokenCounterModel)

    message = Exception.message(failure)
    assert message =~ "Victoria verification failure"
    assert message =~ "Model:\n  Victoria.Test.BrokenCounterModel"
    assert message =~ "Step:\n  1"
    assert message =~ "Action:\n  Increment"
    assert message =~ ~s(Expected:\n  %{"count" => 2})
    assert message =~ ~s(Observed:\n  %{"count" => 0})
    assert message =~ "Reason:\n  states differ"
    assert message =~ "Trace:\n  #{trace_path}"
  end

  test "rejects a lasso before init, execute, or cleanup" do
    assert {:ok, trace} = "loop.itf.json" |> fixture() |> Victoria.Trace.load()

    assert {:error,
            %Failure{
              phase: :trace_validation,
              reason: {:unsupported_lasso, 1},
              step_index: nil,
              action: nil
            }} = Runner.replay(trace, TrackingCounterModel)

    refute_received :init
    refute_received {:execute, _index, _action}
    refute_received :cleanup
  end

  test "rejects a parameterized initial stutter before init, execute, or cleanup" do
    result =
      with {:ok, trace} <- "parameterized_initial_stutter.itf.json" |> fixture() |> Victoria.Trace.load() do
        Runner.replay(trace, TrackingCounterModel)
      end

    assert {:error,
            %Victoria.Trace.Error{
              reason: :unsupported_stutter,
              state_index: 1,
              action: "Initial",
              path: ["states", 1]
            }} = result

    refute_received :init
    refute_received {:execute, _index, _action}
    refute_received :cleanup
  end

  test "returns tagged init errors without owing cleanup" do
    assert {:error,
            %Failure{
              phase: :initialization,
              reason: :cannot_start,
              step_index: 0,
              action: "Initial"
            }} = replay("counter.itf.json", InitErrorModel)

    refute_received :cleanup
  end

  test "returns tagged execute errors and cleans up once" do
    assert {:error,
            %Failure{
              phase: :execution,
              reason: :command_failed,
              step_index: 1,
              action: "Increment"
            }} = replay("counter.itf.json", ExecuteErrorModel)

    assert_received :cleanup
    refute_received :cleanup
  end

  test "rejects a non-map snapshot and retains a secondary cleanup error" do
    assert {:error,
            %Failure{
              phase: :snapshot,
              reason: {:invalid_return, :not_a_map},
              step_index: 0,
              cleanup_error: :cleanup_failed
            }} = replay("counter.itf.json", InvalidSnapshotModel)

    assert_received :cleanup
    refute_received :cleanup
  end

  test "returns a cleanup failure after an otherwise successful replay" do
    assert {:error,
            %Failure{
              phase: :cleanup,
              reason: :cleanup_failed,
              step_index: nil
            }} = replay("counter.itf.json", CleanupErrorModel)
  end

  test "turns a raised projection into a failure and cleans up once" do
    assert {:error,
            %Failure{
              phase: :projection,
              reason: {:raised, %RuntimeError{message: "projection failed"}},
              step_index: 0,
              action: "Initial"
            }} = replay("counter.itf.json", RaisedProjectModel)

    assert_received :cleanup
    refute_received :cleanup
  end

  test "uses exact equality for verification" do
    assert {:error,
            %Failure{
              phase: :step_verification,
              reason: :states_differ,
              expected: %{"count" => 1.0},
              observed: %{"count" => 1}
            }} = replay("counter.itf.json", NumericProjectionModel)
  end

  defp fixture(name), do: Path.join(@fixtures, name)

  defp replay(name, model) do
    assert {:ok, trace} = name |> fixture() |> Victoria.Trace.load()
    Runner.replay(trace, model)
  end
end
