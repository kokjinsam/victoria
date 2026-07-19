defmodule Victoria.ExUnit do
  @moduledoc "ExUnit assertion helpers for Victoria verification."

  @spec assert_conform(module(), trace: Path.t() | Victoria.Trace.t()) :: :ok
  def assert_conform(model, options) do
    case Victoria.verify(model, options) do
      {:ok, _report} -> :ok
      {:error, error} -> raise %ExUnit.AssertionError{message: Exception.message(error)}
    end
  end
end
