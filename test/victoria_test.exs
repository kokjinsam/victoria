defmodule VictoriaTest do
  use ExUnit.Case, async: true

  alias Victoria.ITF.Error
  alias Victoria.Runner.Failure
  alias Victoria.Runner.Report
  alias Victoria.Test.BrokenCounterModel
  alias Victoria.Test.CounterModel
  alias Victoria.Trace

  @fixtures Path.expand("fixtures", __DIR__)
  @traces Path.expand("traces", __DIR__)

  test "verifies a trace path" do
    path = Path.join(@traces, "counter.itf.json")

    assert {:ok, %Report{trace_path: ^path, model: CounterModel}} =
             Victoria.verify(CounterModel, trace: path)
  end

  test "verifies an existing validated Trace" do
    path = Path.join(@traces, "counter.itf.json")
    assert {:ok, trace} = Trace.load(path)

    assert {:ok, %Report{trace_path: ^path, model: CounterModel}} =
             Victoria.verify(CounterModel, trace: trace)
  end

  test "returns Runner failures unchanged" do
    path = fixture("counter_step_mismatch.itf.json")

    assert {:error,
            %Failure{
              trace_path: ^path,
              model: BrokenCounterModel,
              phase: :step_verification,
              reason: :states_differ
            }} = Victoria.verify(BrokenCounterModel, trace: path)
  end

  test "returns ITF errors unchanged" do
    path = fixture("missing.itf.json")

    assert {:error, %Error{source: ^path, kind: :read, reason: :enoent, path: []}} =
             Victoria.verify(CounterModel, trace: path)
  end

  test "raises for a missing trace option" do
    victoria = Module.safe_concat([Victoria])
    assert_raise ArgumentError, fn -> victoria.verify(CounterModel, []) end
  end

  test "raises for duplicate trace options" do
    path = Path.join(@traces, "counter.itf.json")
    victoria = Module.safe_concat([Victoria])

    assert_raise ArgumentError, fn ->
      victoria.verify(CounterModel, trace: path, trace: path)
    end
  end

  test "raises for unknown options" do
    victoria = Module.safe_concat([Victoria])
    assert_raise ArgumentError, fn -> victoria.verify(CounterModel, unknown: :option) end
  end

  test "raises for non-keyword options" do
    victoria = Module.safe_concat([Victoria])
    assert_raise ArgumentError, fn -> victoria.verify(CounterModel, %{trace: "trace.itf.json"}) end
  end

  test "raises for unsupported trace inputs" do
    victoria = Module.safe_concat([Victoria])
    assert_raise ArgumentError, fn -> victoria.verify(CounterModel, trace: 123) end
  end

  defp fixture(name), do: Path.join(@fixtures, name)
end
