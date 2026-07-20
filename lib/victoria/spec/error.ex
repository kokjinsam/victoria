defmodule Victoria.Spec.Error do
  @moduledoc """
  Describes a filesystem validation failure for a Victoria specification.

  Errors are returned by `Victoria.Spec.new/1` and should be treated as
  read-only.
  """

  @enforce_keys [:field, :path, :reason]
  defexception [:field, :path, :reason]

  @typedoc "The specification path that failed validation."
  @type field :: :source | :config
  @typedoc "The filesystem or extension validation failure."
  @type reason ::
          :not_found
          | :not_a_regular_file
          | {:invalid_extension, String.t()}
          | {:filesystem, term()}

  @typedoc "A structured specification-path failure."
  @type t :: %__MODULE__{
          field: field(),
          path: Path.t(),
          reason: reason()
        }

  @impl Exception
  def message(%__MODULE__{field: field, path: path, reason: reason}) do
    "Victoria specification error for #{field} at #{inspect(path)}: #{format_reason(reason)}"
  end

  defp format_reason(:not_found), do: "file was not found"
  defp format_reason(:not_a_regular_file), do: "path is not a regular file"

  defp format_reason({:invalid_extension, actual_extension}) do
    "invalid extension #{inspect(actual_extension)}"
  end

  defp format_reason({:filesystem, reason}) do
    "filesystem error: #{inspect(reason)}"
  end
end
