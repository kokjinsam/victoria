defmodule Victoria.Model do
  @moduledoc "Callbacks used to replay a fixed formal trace."

  alias Victoria.Step

  @type implementation :: term()
  @type reason :: term()

  @callback init(map()) :: {:ok, implementation()} | {:error, reason()}
  @callback execute(Step.t(), implementation()) ::
              {:ok, implementation()} | {:error, reason()}
  @callback snapshot(implementation()) :: map()
  @callback project(Step.t()) :: map()
  @callback cleanup(implementation()) :: :ok | {:error, reason()}

  @optional_callbacks cleanup: 1
end
