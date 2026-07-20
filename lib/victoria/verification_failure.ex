defmodule Victoria.VerificationFailure do
  @moduledoc """
  The semantic mismatch returned directly by `Victoria.Verifier.verify/2`.

  This struct is return-only. Consumers may inspect it but should not construct
  it themselves.
  """

  @enforce_keys [:expected, :observed, :reason]
  defstruct [:expected, :observed, :reason]

  @typedoc "An exact expected/observed state mismatch."
  @type t :: %__MODULE__{
          expected: map(),
          observed: map(),
          reason: :states_differ
        }
end
