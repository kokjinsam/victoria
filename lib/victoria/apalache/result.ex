defmodule Victoria.Apalache.Result do
  @moduledoc """
  Complete Apalachex execution context after Victoria loaded every retained ITF artifact.

  Results are constructed by Victoria and should be treated as read-only. The
  `output` field contains complete raw subprocess bytes and may not be UTF-8.
  """

  alias Victoria.Apalache.Plan
  alias Victoria.Trace

  @enforce_keys [:plan, :executable, :version, :exit_status, :output, :trace_paths, :traces]
  defstruct [:plan, :executable, :version, :exit_status, :output, :trace_paths, :traces]

  @typedoc "An Apalachex run with ordered trace paths and Victoria-loaded traces."
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
