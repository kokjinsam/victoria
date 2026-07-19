defmodule Victoria.Apalache.Result do
  @moduledoc "The complete context of a successful Apalache trace materialization."

  alias Victoria.Apalache.Plan
  alias Victoria.Trace

  @enforce_keys [:plan, :executable, :version, :exit_status, :output, :trace_paths, :traces]
  defstruct [:plan, :executable, :version, :exit_status, :output, :trace_paths, :traces]

  @type t :: %__MODULE__{
          plan: Plan.t(),
          executable: Path.t(),
          version: Version.t(),
          exit_status: non_neg_integer(),
          output: binary(),
          trace_paths: [Path.t(), ...],
          traces: [Trace.t(), ...]
        }
end
