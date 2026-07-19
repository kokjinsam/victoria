defmodule Victoria do
  @moduledoc "Public developer workflow for fixed-trace verification."

  alias Victoria.ITF
  alias Victoria.Runner
  alias Victoria.Runner.Failure
  alias Victoria.Runner.Report
  alias Victoria.Trace

  @spec verify(module(), trace: Path.t() | Trace.t()) ::
          {:ok, Report.t()} | {:error, ITF.Error.t() | Failure.t()}
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
