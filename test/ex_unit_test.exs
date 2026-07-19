defmodule Victoria.ExUnitTest do
  use ExUnit.Case, async: true

  import Victoria.ExUnit

  alias Victoria.Test.BrokenCounterModel
  alias Victoria.Test.CounterModel

  @fixtures Path.expand("fixtures", __DIR__)
  @traces Path.expand("traces", __DIR__)

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

  defp fixture(name), do: Path.join(@fixtures, name)
end
