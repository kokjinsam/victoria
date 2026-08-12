defmodule Victoria.ExUnit do
  @moduledoc """
  ExUnit assertion helpers for Victoria conformance verification.

  Verify one existing fixed trace:

      import Victoria.ExUnit

      assert_conform(
        Counter.Model,
        trace: "test/traces/counter.itf.json"
      )

  Or generate traces through a complete workflow and verify all of them:

      {:ok, spec} =
        Victoria.Spec.new(
          source: "test/specs/Counter.tla",
          config: "test/specs/Counter.cfg"
        )

      assert_conform(
        Counter.Model,
        spec,
        plan: [
          mode: :simulate,
          length: 10,
          max_run: 5
        ]
      )

  `assert_conform/2` verifies one fixed trace. `assert_conform/3` runs a
  generated conformance workflow and verifies every materialized trace.
  """

  alias Victoria.Spec
  alias Victoria.Workflow

  @spec assert_conform(module(), trace: Path.t() | Victoria.Trace.t()) :: :ok
  @doc "Verifies one fixed trace and raises `ExUnit.AssertionError` on controlled failure."
  def assert_conform(model, options) do
    case Victoria.verify(model, options) do
      {:ok, %Victoria.Runner.Report{}} -> :ok
      {:error, %ITF.Error{} = error} -> raise_assertion(error)
      {:error, %Victoria.Trace.Error{} = error} -> raise_assertion(error)
      {:error, %Victoria.Runner.Failure{} = error} -> raise_assertion(error)
    end
  end

  @spec assert_conform(module(), Spec.t(), keyword()) :: :ok
  @doc "Runs a generated workflow and raises `ExUnit.AssertionError` on controlled failure."
  def assert_conform(model, spec, workflow_options) do
    case Workflow.run(model, spec, workflow_options) do
      {:ok, %Workflow.Result{}} -> :ok
      {:error, %Workflow.Error{} = error} -> raise_assertion(error)
    end
  end

  defp raise_assertion(error) do
    raise %ExUnit.AssertionError{message: Exception.message(error)}
  end
end
