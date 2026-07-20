defmodule Victoria.Step do
  @moduledoc """
  A normalized formal state and the transition that produced it.

  Steps are produced while loading a trace and should normally be treated as
  read-only values rather than constructed directly.
  """

  @enforce_keys [:index, :action, :state]
  defstruct [:index, :action, :state]

  @typedoc "A zero-based trace step with its action and projected state."
  @type t :: %__MODULE__{
          index: non_neg_integer(),
          action: String.t(),
          state: map()
        }
end
