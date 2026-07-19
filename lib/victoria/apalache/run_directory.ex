defmodule Victoria.Apalache.RunDirectory do
  @moduledoc """
  Builds deterministic, caller-owned Apalache run directory paths.
  """

  alias Victoria.Spec

  @default_root "tmp/victoria"
  @suffix_pattern ~r/\A[0-9a-f]{6}\z/

  @spec build(Spec.t(), keyword()) :: Path.t()
  def build(%Spec{} = spec, options) do
    validate_options!(options)

    generated_at = Keyword.fetch!(options, :generated_at)
    suffix = Keyword.fetch!(options, :suffix)
    root = Keyword.get(options, :root, @default_root)

    validate_generated_at!(generated_at)
    validate_suffix!(suffix)
    validate_root!(root)

    name = Enum.join([timestamp(generated_at), slug(spec.source), suffix], "-")

    root
    |> Path.expand()
    |> Path.join(name)
  end

  def build(_spec, _options) do
    raise ArgumentError, "expected the first argument to be a Victoria.Spec"
  end

  defp validate_options!(options) do
    if !Keyword.keyword?(options) do
      raise ArgumentError, "expected options to be a keyword list"
    end

    keys = Keyword.keys(options)

    if length(keys) != length(Enum.uniq(keys)) do
      raise ArgumentError, "expected options to contain no duplicate keys"
    end

    unknown = keys -- [:generated_at, :suffix, :root]

    if unknown != [] do
      raise ArgumentError, "unknown options: #{inspect(unknown)}"
    end

    for required <- [:generated_at, :suffix], required not in keys do
      raise ArgumentError, "missing required option #{inspect(required)}"
    end
  end

  defp validate_generated_at!(%DateTime{utc_offset: 0, std_offset: 0}), do: :ok

  defp validate_generated_at!(_generated_at) do
    raise ArgumentError, "expected :generated_at to be a UTC DateTime"
  end

  defp validate_suffix!(suffix) when is_binary(suffix) do
    if !Regex.match?(@suffix_pattern, suffix) do
      raise ArgumentError, "expected :suffix to be exactly six lowercase hexadecimal characters"
    end
  end

  defp validate_suffix!(_suffix) do
    raise ArgumentError, "expected :suffix to be exactly six lowercase hexadecimal characters"
  end

  defp validate_root!(root) when is_binary(root) do
    if String.trim(root) == "" do
      raise ArgumentError, "expected :root to be a non-blank string"
    end
  end

  defp validate_root!(_root) do
    raise ArgumentError, "expected :root to be a non-blank string"
  end

  defp timestamp(generated_at) do
    Calendar.strftime(generated_at, "%Y%m%dT%H%M%SZ")
  end

  defp slug(source) do
    source
    |> Path.basename(".tla")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "spec"
      value -> value
    end
  end
end
