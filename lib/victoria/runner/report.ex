defmodule Victoria.Runner.Report do
  @moduledoc "Summary of a successful fixed-trace replay."

  @enforce_keys [:trace_path, :model, :step_count, :executed_count]
  defstruct [:trace_path, :model, :step_count, :executed_count]

  @type t :: %__MODULE__{
          trace_path: Path.t(),
          model: module(),
          step_count: pos_integer(),
          executed_count: non_neg_integer()
        }
end
