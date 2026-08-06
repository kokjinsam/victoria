defmodule Victoria.Trace do
  @moduledoc """
  A decoded ITF trace adapted for Victoria replay.

  Trace structs are returned by `load/1`; consumers should not construct them
  directly because loading establishes the structural and value invariants
  required by the runner.
  """

  alias Victoria.ITF
  alias Victoria.Step

  @enforce_keys [:source, :metadata, :steps, :loop_index]
  defstruct [:source, :metadata, :steps, :loop_index]

  @typedoc "Normalized trace metadata retained from the ITF document."
  @type metadata :: %{
          variables: [String.t()],
          parameters: [String.t()],
          source_format: :itf,
          itf: map()
        }

  @typedoc "A finite trace, or a loaded lasso trace that replay will reject."
  @type t :: %__MODULE__{
          source: Path.t(),
          metadata: metadata(),
          steps: [Step.t(), ...],
          loop_index: non_neg_integer() | nil
        }

  @spec load(Path.t()) :: {:ok, t()} | {:error, ITF.Error.t()}
  @doc "Loads an ITF document and adapts its trace semantics for Victoria replay."
  defdelegate load(path), to: ITF
end
