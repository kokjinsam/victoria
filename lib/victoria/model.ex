defmodule Victoria.Model do
  @moduledoc """
  Defines the implementation lifecycle used while replaying a trace.

  The implementation value is opaque to Victoria. It may be a value, PID,
  database context, client, or any other implementation handle. State zero is
  passed to `c:init/1` and verified without being executed. Later steps are
  passed to `c:execute/2`, then compared through `c:snapshot/1` and
  `c:project/1`. Optional `c:cleanup/1` runs once after a successful init on
  every controlled exit.
  """

  alias Victoria.Step

  @typedoc "Opaque implementation state owned by the model."
  @type implementation :: term()
  @typedoc "A model-defined callback failure reason."
  @type reason :: term()

  @doc "Creates the implementation from the initial formal state."
  @callback init(map()) :: {:ok, implementation()} | {:error, reason()}
  @doc "Executes one non-initial formal step and returns the next implementation handle."
  @callback execute(Step.t(), implementation()) ::
              {:ok, implementation()} | {:error, reason()}
  @doc "Returns the implementation's observed state."
  @callback snapshot(implementation()) :: map()
  @doc "Returns the expected state supplied by a formal step."
  @callback project(Step.t()) :: map()
  @doc "Releases implementation resources after a controlled replay exit."
  @callback cleanup(implementation()) :: :ok | {:error, reason()}

  @optional_callbacks cleanup: 1
end
