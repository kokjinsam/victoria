defmodule Victoria.Workflow.Result do
  @moduledoc """
  Complete result of a successful conformance workflow.

  Results are constructed by Victoria and should be treated as read-only.
  """

  alias Victoria.Apalache
  alias Victoria.Workflow.Verification

  @enforce_keys [:model, :apalache, :verifications]
  defstruct [:model, :apalache, :verifications]

  @typedoc "The Apalache result and every successful trace verification."
  @type t :: %__MODULE__{
          model: module(),
          apalache: Apalache.Result.t(),
          verifications: [Verification.t(), ...]
        }
end
