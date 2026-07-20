defmodule Victoria.Verifier do
  @moduledoc "Compares expected and observed states using exact Elixir equality (`===`)."

  alias Victoria.VerificationFailure

  @spec verify(map(), map()) :: :ok | {:error, VerificationFailure.t()}
  @doc "Returns `:ok` for exact equality or a public `Victoria.VerificationFailure`."
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
