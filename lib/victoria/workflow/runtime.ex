defmodule Victoria.Workflow.Runtime do
  @moduledoc false

  @generated_at_key {__MODULE__, :generated_at}
  @suffix_key {__MODULE__, :suffix}

  @spec generated_at() :: DateTime.t()
  def generated_at do
    Process.get(@generated_at_key, &DateTime.utc_now/0).()
  end

  @spec suffix() :: String.t()
  def suffix do
    Process.get(@suffix_key, &random_suffix/0).()
  end

  @doc false
  @spec with_sources((-> DateTime.t()), (-> String.t()), (-> result)) :: result when result: var
  def with_sources(generated_at, suffix, function)
      when is_function(generated_at, 0) and is_function(suffix, 0) and is_function(function, 0) do
    previous_generated_at = Process.put(@generated_at_key, generated_at)
    previous_suffix = Process.put(@suffix_key, suffix)

    try do
      function.()
    after
      restore(@generated_at_key, previous_generated_at)
      restore(@suffix_key, previous_suffix)
    end
  end

  defp random_suffix do
    3
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  defp restore(key, nil), do: Process.delete(key)
  defp restore(key, value), do: Process.put(key, value)
end
