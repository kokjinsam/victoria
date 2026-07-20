defmodule Victoria.Apalache.Plan do
  @moduledoc """
  Describes a pure, non-executing Apalache invocation plan.

  Construct plans with `new/2`. Direct struct construction bypasses argument
  and path validation.
  """

  alias Victoria.Spec

  @enforce_keys [:spec, :mode, :working_directory, :run_directory, :options, :argv]
  defstruct [:spec, :mode, :working_directory, :run_directory, :options, :argv]

  @typedoc "Supported Apalache operation."
  @type mode :: :simulate | :check
  @typedoc "A validated, shell-free argv plan."
  @type t :: %__MODULE__{
          spec: Spec.t(),
          mode: mode(),
          working_directory: Path.t(),
          run_directory: Path.t(),
          options: %{required(:length) => non_neg_integer(), optional(:max_run) => pos_integer()},
          argv: [String.t()]
        }

  @spec new(Spec.t(), keyword()) :: t()
  @doc "Builds a deterministic invocation plan without executing Apalache."
  def new(%Spec{} = spec, options) do
    validate_options!(options)

    mode = Keyword.fetch!(options, :mode)
    length = Keyword.fetch!(options, :length)
    run_directory = validate_run_directory!(Keyword.fetch!(options, :run_directory))

    validate_mode!(mode)
    validate_length!(length)

    build(spec, mode, length, run_directory, options)
  end

  def new(_spec, _options) do
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

    unknown = keys -- [:mode, :length, :max_run, :run_directory]

    if unknown != [] do
      raise ArgumentError, "unknown options: #{inspect(unknown)}"
    end

    for required <- [:mode, :length, :run_directory], required not in keys do
      raise ArgumentError, "missing required option #{inspect(required)}"
    end
  end

  defp validate_mode!(mode) when mode in [:simulate, :check], do: :ok

  defp validate_mode!(_mode) do
    raise ArgumentError, "expected :mode to be :simulate or :check"
  end

  defp validate_length!(length) when is_integer(length) and length >= 0, do: :ok

  defp validate_length!(_length) do
    raise ArgumentError, "expected :length to be a nonnegative integer"
  end

  defp validate_max_run!(max_run) when is_integer(max_run) and max_run > 0, do: :ok

  defp validate_max_run!(_max_run) do
    raise ArgumentError, "expected :max_run to be a positive integer"
  end

  defp validate_run_directory!(run_directory) when is_binary(run_directory) do
    if String.trim(run_directory) == "" do
      raise ArgumentError, "expected :run_directory to be a non-blank string"
    end

    Path.expand(run_directory)
  end

  defp validate_run_directory!(_run_directory) do
    raise ArgumentError, "expected :run_directory to be a non-blank string"
  end

  defp build(spec, :simulate, length, run_directory, options) do
    max_run =
      case Keyword.fetch(options, :max_run) do
        {:ok, value} -> value
        :error -> raise ArgumentError, "missing required option :max_run for :simulate"
      end

    validate_max_run!(max_run)
    plan_options = %{length: length, max_run: max_run}

    struct(spec, :simulate, run_directory, plan_options, [
      "simulate",
      config_argument(spec),
      "--length=#{length}",
      "--max-run=#{max_run}",
      "--output-traces",
      "--run-dir=#{run_directory}",
      spec.source
    ])
  end

  defp build(spec, :check, length, run_directory, options) do
    if Keyword.has_key?(options, :max_run) do
      raise ArgumentError, ":max_run is forbidden for :check"
    end

    plan_options = %{length: length}

    struct(spec, :check, run_directory, plan_options, [
      "check",
      config_argument(spec),
      "--length=#{length}",
      "--output-traces",
      "--run-dir=#{run_directory}",
      spec.source
    ])
  end

  defp struct(spec, mode, run_directory, options, argv) do
    %__MODULE__{
      spec: spec,
      mode: mode,
      working_directory: Path.dirname(spec.source),
      run_directory: run_directory,
      options: options,
      argv: Enum.reject(argv, &is_nil/1)
    }
  end

  defp config_argument(%Spec{config: nil}), do: nil
  defp config_argument(%Spec{config: config}), do: "--config=#{config}"
end
