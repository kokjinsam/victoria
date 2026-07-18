defmodule Victoria.Step do
  @moduledoc "A single formal state and the transition that produced it."

  @enforce_keys [:index, :action, :state]
  defstruct [:index, :action, :state]

  @type t :: %__MODULE__{
          index: non_neg_integer(),
          action: String.t(),
          state: map()
        }
end
