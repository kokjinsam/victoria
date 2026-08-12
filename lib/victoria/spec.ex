defmodule Victoria.Spec do
  @moduledoc """
  High-level access to Apalachex specification validation.
  """

  @typedoc "A validated TLA+ source and optional Apalache configuration."
  @type t :: Apalachex.Spec.t()

  @spec new(keyword()) :: {:ok, t()} | {:error, Apalachex.Spec.Error.t()}
  @doc "Validates source/config paths and returns a specification reference."
  defdelegate new(options), to: Apalachex.Spec
end
