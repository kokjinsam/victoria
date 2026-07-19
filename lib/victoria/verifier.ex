defmodule Victoria.Verifier do
  @moduledoc "Compares expected and observed states."

  alias Victoria.VerificationFailure

  @spec verify(map(), map()) :: :ok | {:error, VerificationFailure.t()}
  def verify(expected, observed) when is_map(expected) and is_map(observed) and expected === observed, do: :ok

  def verify(expected, observed) when is_map(expected) and is_map(observed) do
    {:error,
     %VerificationFailure{
       expected: expected,
       observed: observed,
       reason: :states_differ
     }}
  end
end
