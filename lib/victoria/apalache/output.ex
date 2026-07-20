defmodule Victoria.Apalache.Output do
  @moduledoc false

  @maximum_tail_bytes 4096

  @spec summary(binary()) :: %{
          byte_size: non_neg_integer(),
          tail: String.t(),
          tail_truncated: boolean()
        }
  def summary(output) when is_binary(output) do
    {tail, tail_truncated?} = tail(output)

    %{
      byte_size: byte_size(output),
      tail: tail,
      tail_truncated: tail_truncated?
    }
  end

  @spec tail(binary()) :: {String.t(), boolean()}
  def tail(output) when is_binary(output) do
    if String.valid?(output) do
      valid_tail(output)
    else
      inspected_tail(output)
    end
  end

  defp valid_tail(output) when byte_size(output) <= @maximum_tail_bytes, do: {output, false}

  defp valid_tail(output) do
    output
    |> binary_tail(@maximum_tail_bytes)
    |> trim_to_codepoint_boundary()
    |> then(&{&1, true})
  end

  defp inspected_tail(output) do
    raw_tail = binary_tail(output, @maximum_tail_bytes)
    inspected = inspect(raw_tail, binaries: :as_binaries, limit: :infinity, printable_limit: :infinity)

    if byte_size(inspected) <= @maximum_tail_bytes do
      {inspected, byte_size(raw_tail) < byte_size(output)}
    else
      {binary_tail(inspected, @maximum_tail_bytes), true}
    end
  end

  defp binary_tail(binary, maximum) when byte_size(binary) <= maximum, do: binary

  defp binary_tail(binary, maximum) do
    start = byte_size(binary) - maximum
    binary_part(binary, start, maximum)
  end

  defp trim_to_codepoint_boundary(binary) do
    if String.valid?(binary), do: binary, else: trim_to_codepoint_boundary(binary_part(binary, 1, byte_size(binary) - 1))
  end
end
