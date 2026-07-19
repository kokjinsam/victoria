defmodule Victoria.Trace do
  @moduledoc "A validated, normalized formal trace."

  alias Victoria.ITF
  alias Victoria.Step

  @enforce_keys [:source, :metadata, :steps, :loop_index]
  defstruct [:source, :metadata, :steps, :loop_index]

  @type metadata :: %{
          variables: [String.t()],
          parameters: [String.t()],
          source_format: :itf,
          itf: map()
        }

  @type t :: %__MODULE__{
          source: Path.t(),
          metadata: metadata(),
          steps: [Step.t(), ...],
          loop_index: non_neg_integer() | nil
        }

  @spec load(Path.t()) :: {:ok, t()} | {:error, ITF.Error.t()}
  defdelegate load(path), to: ITF
end
