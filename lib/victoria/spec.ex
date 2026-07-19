defmodule Victoria.Spec do
  @moduledoc """
  Identifies the source and optional configuration files for a TLA+ specification.
  """

  alias Victoria.Spec.Error

  @enforce_keys [:source]
  defstruct [:source, :config]

  @type t :: %__MODULE__{
          source: Path.t(),
          config: Path.t() | nil
        }

  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(options) do
    validate_options!(options)

    with {:ok, source} <- validate_path(:source, Keyword.fetch!(options, :source), ".tla"),
         {:ok, config} <- validate_config(options) do
      {:ok, %__MODULE__{source: source, config: config}}
    end
  end

  defp validate_options!(options) do
    if !Keyword.keyword?(options) do
      raise ArgumentError, "expected options to be a keyword list"
    end

    keys = Keyword.keys(options)

    if length(keys) != length(Enum.uniq(keys)) do
      raise ArgumentError, "expected options to contain no duplicate keys"
    end

    unknown = keys -- [:source, :config]

    if unknown != [] do
      raise ArgumentError, "unknown options: #{inspect(unknown)}"
    end

    if :source not in keys do
      raise ArgumentError, "missing required option :source"
    end

    validate_path_option!(:source, Keyword.fetch!(options, :source))

    if :config in keys do
      validate_path_option!(:config, Keyword.fetch!(options, :config))
    end
  end

  defp validate_path_option!(field, path) when is_binary(path) do
    if String.trim(path) == "" do
      raise ArgumentError, "expected #{inspect(field)} to be a non-blank string"
    end
  end

  defp validate_path_option!(field, _path) do
    raise ArgumentError, "expected #{inspect(field)} to be a non-blank string"
  end

  defp validate_config(options) do
    case Keyword.fetch(options, :config) do
      {:ok, config} -> validate_path(:config, config, ".cfg")
      :error -> {:ok, nil}
    end
  end

  defp validate_path(field, path, extension) do
    expanded_path = Path.expand(path)
    actual_extension = Path.extname(expanded_path)

    if actual_extension == extension do
      validate_file(field, expanded_path)
    else
      {:error,
       %Error{
         field: field,
         path: expanded_path,
         reason: {:invalid_extension, actual_extension}
       }}
    end
  end

  defp validate_file(field, path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular}} ->
        {:ok, path}

      {:ok, %File.Stat{}} ->
        {:error, %Error{field: field, path: path, reason: :not_a_regular_file}}

      {:error, :enoent} ->
        {:error, %Error{field: field, path: path, reason: :not_found}}

      {:error, reason} ->
        {:error, %Error{field: field, path: path, reason: {:filesystem, reason}}}
    end
  end
end
