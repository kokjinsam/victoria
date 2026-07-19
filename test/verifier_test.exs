defmodule Victoria.VerifierTest do
  use ExUnit.Case, async: true

  alias Victoria.VerificationFailure
  alias Victoria.Verifier

  test "accepts equal maps" do
    assert :ok = Verifier.verify(%{"count" => 1}, %{"count" => 1})
  end

  test "rejects unequal maps" do
    expected = %{"count" => 1}
    observed = %{"count" => 2}

    assert {:error,
            %VerificationFailure{
              expected: ^expected,
              observed: ^observed,
              reason: :states_differ
            }} = Verifier.verify(expected, observed)
  end

  test "uses exact equality" do
    expected = %{"count" => 1}
    observed = %{"count" => 1.0}

    assert {:error,
            %VerificationFailure{
              expected: ^expected,
              observed: ^observed,
              reason: :states_differ
            }} = Verifier.verify(expected, observed)
  end
end
