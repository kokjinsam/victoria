defmodule VictoriaFixedConsumer.Counter do
  @moduledoc false
  use Agent

  def start_link(initial), do: Agent.start_link(fn -> initial end)
  def increment(counter), do: Agent.update(counter, &(&1 + 1))
  def value(counter), do: Agent.get(counter, & &1)
end

defmodule VictoriaFixedConsumer.Model do
  @moduledoc false
  @behaviour Victoria.Model

  alias VictoriaFixedConsumer.Counter

  @impl Victoria.Model
  def init(%{"count" => initial}), do: Counter.start_link(initial)

  @impl Victoria.Model
  def execute(%Victoria.Step{action: "Increment"}, counter) do
    :ok = Counter.increment(counter)
    {:ok, counter}
  end

  @impl Victoria.Model
  def snapshot(counter), do: %{"count" => Counter.value(counter)}

  @impl Victoria.Model
  def project(%Victoria.Step{state: state}), do: state

  @impl Victoria.Model
  def cleanup(counter), do: Agent.stop(counter)
end
