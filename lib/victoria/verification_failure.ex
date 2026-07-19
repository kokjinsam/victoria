defmodule Victoria.VerificationFailure do
  @moduledoc "Semantic failure returned when expected and observed states differ."

  @enforce_keys [:expected, :observed, :reason]
  defstruct [:expected, :observed, :reason]

  @type t :: %__MODULE__{
          expected: map(),
          observed: map(),
          reason: :states_differ
        }
end
