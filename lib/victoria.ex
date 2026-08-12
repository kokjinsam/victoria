defmodule Victoria do
  @moduledoc """
  The primary API for verifying one fixed formal trace.

  Use `verify/2` with either an ITF path or an already loaded `Victoria.Trace`.
  Generated conformance workflows are provided by `Victoria.Workflow`.
  """

  alias Victoria.Runner
  alias Victoria.Runner.Failure
  alias Victoria.Runner.Report
  alias Victoria.Trace
  alias Victoria.Trace.Error

  @spec verify(module(), trace: Path.t() | Trace.t()) ::
          {:ok, Report.t()} | {:error, ITF.Error.t() | Error.t() | Failure.t()}
  @doc """
  Replays one validated trace against `model`.

  Returns a `Victoria.Runner.Report` on conformance. ITF loading and controlled
  replay failures are returned as structured errors. Invalid options raise
  `ArgumentError`.
  """
  def verify(model, options) do
    case options do
      [trace: %Trace{} = trace] -> Runner.replay(trace, model)
      [trace: path] when is_binary(path) -> load_and_replay(path, model)
      _other -> raise ArgumentError, "expected exactly one :trace option containing a path or Victoria.Trace"
    end
  end

  defp load_and_replay(path, model) do
    with {:ok, trace} <- Trace.load(path) do
      Runner.replay(trace, model)
    end
  end
end
