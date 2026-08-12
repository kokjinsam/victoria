defmodule Victoria.Trace.Error do
  @moduledoc """
  A structured Victoria trace-adaptation error.

  Generic file, JSON, and ITF errors are returned as `ITF.Error` values.
  """

  @enforce_keys [:source, :reason, :path]
  defexception [:source, :reason, :path, :state_index, :action]

  @type t :: %__MODULE__{
          source: Path.t(),
          reason: term(),
          path: [String.t() | non_neg_integer()],
          state_index: non_neg_integer() | nil,
          action: String.t() | nil
        }

  @impl Exception
  def message(error) do
    location = if error.path == [], do: error.source, else: "#{error.source}:#{format_path(error.path)}"
    "trace adaptation error at #{location}: #{inspect(error.reason)}"
  end

  defp format_path([head | tail]) do
    Enum.reduce(tail, head, fn
      index, path when is_integer(index) -> "#{path}[#{index}]"
      key, path -> "#{path}.#{key}"
    end)
  end
end
