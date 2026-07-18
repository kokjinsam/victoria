defmodule Victoria.RunnerTest do
  use ExUnit.Case, async: true

  alias Victoria.ITF.Error
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

  test "replays a fixed Counter trace sequentially" do
    trace_path = fixture("counter.itf.json")

    assert {:ok,
            %Report{
              trace_path: ^trace_path,
              model: CounterModel,
              step_count: 4,
              executed_count: 3
            }} = Runner.replay(trace_path, CounterModel)
  end

  test "threads the opaque implementation and cleans up its final value once" do
    assert {:ok, %Report{executed_count: 3}} = replay("counter.itf.json", ThreadingModel)

    assert_received {:cleaned_up, 1}
    refute_received {:cleaned_up, _count}
  end

  test "reports an exact initial refinement mismatch and never executes Initial" do
    trace_path = fixture("counter_initial_mismatch.itf.json")

    assert {:error,
            %Failure{
              trace_path: ^trace_path,
              model: InitialMismatchModel,
              phase: :initial_refinement,
              step_index: 0,
              action: "Initial",
              expected: %{"count" => 3},
              observed: %{"count" => 4}
            }} = Runner.replay(trace_path, InitialMismatchModel)

    refute_received :initial_was_executed
  end

  test "stops at the first step refinement mismatch and renders useful context" do
    trace_path = fixture("counter_step_mismatch.itf.json")

    assert {:error,
            %Failure{
              trace_path: ^trace_path,
              model: BrokenCounterModel,
              phase: :step_refinement,
              step_index: 1,
              action: "Increment",
              expected: %{"count" => 2},
              observed: %{"count" => 0}
            } = failure} = Runner.replay(trace_path, BrokenCounterModel)

    message = Exception.message(failure)
    assert message =~ "Victoria refinement failure"
    assert message =~ "Model:\n  Victoria.Test.BrokenCounterModel"
    assert message =~ "Step:\n  1"
    assert message =~ "Action:\n  Increment"
    assert message =~ ~s(Expected:\n  %{"count" => 2})
    assert message =~ ~s(Observed:\n  %{"count" => 0})
    assert message =~ "Trace:\n  #{trace_path}"
  end

  test "rejects a stutter before initialization or duplicate execution" do
    assert {:error,
            %Failure{
              phase: :trace_loading,
              reason: %Error{
                kind: :shape,
                reason: :unsupported_stutter,
                state_index: 2,
                action: "Increment"
              },
              step_index: 2,
              action: "Increment"
            }} = replay("counter_stutter.itf.json", TrackingCounterModel)

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

  test "returns a structured ITF read error" do
    trace_path = fixture("missing.itf.json")

    assert {:error,
            %Failure{
              trace_path: ^trace_path,
              phase: :trace_loading,
              reason: %Error{kind: :read, reason: :enoent}
            }} = Runner.replay(trace_path, CounterModel)
  end

  test "uses exact equality for refinement comparisons" do
    assert {:error,
            %Failure{
              phase: :step_refinement,
              expected: %{"count" => 1.0},
              observed: %{"count" => 1}
            }} = replay("counter_numeric_type_mismatch.itf.json", CounterModel)
  end

  test "rejects malformed and unsupported ITF inputs explicitly" do
    assert {:error, %Failure{phase: :trace_loading, reason: %Error{kind: :decode}}} =
             replay("malformed_json.itf.json", CounterModel)

    assert {:error,
            %Failure{
              phase: :trace_loading,
              reason: %Error{
                kind: :shape,
                reason: :last_transition_must_be_a_string,
                state_index: 1
              }
            }} = replay("malformed_state.itf.json", CounterModel)

    assert {:error,
            %Failure{
              phase: :trace_loading,
              reason: %Error{
                kind: :shape,
                reason: {:unsupported_typed_value, "#bigint"},
                state_index: 0,
                action: "Initial"
              }
            }} = replay("counter_typed_value.itf.json", CounterModel)
  end

  defp fixture(name), do: Path.join(@fixtures, name)
  defp replay(name, model), do: name |> fixture() |> Runner.replay(model)
end
