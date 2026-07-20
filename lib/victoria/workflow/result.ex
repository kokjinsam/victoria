defmodule Victoria.Workflow.Result do
  @moduledoc "The complete result of a successful conformance workflow."

  alias Victoria.Apalache
  alias Victoria.Workflow.Verification

  @enforce_keys [:model, :apalache, :verifications]
  defstruct [:model, :apalache, :verifications]

  @type t :: %__MODULE__{
          model: module(),
          apalache: Apalache.Result.t(),
          verifications: [Verification.t(), ...]
        }
end
