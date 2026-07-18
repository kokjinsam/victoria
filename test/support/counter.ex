defmodule Victoria.Test.Counter do
  @moduledoc false

  def start_link(initial), do: Agent.start_link(fn -> initial end)
  def increment(counter), do: Agent.update(counter, &(&1 + 1))
  def decrement(counter), do: Agent.update(counter, &(&1 - 1))
  def value(counter), do: Agent.get(counter, & &1)
  def stop(counter), do: Agent.stop(counter)
end

defmodule Victoria.Test.BrokenCounter do
  @moduledoc false

  def start_link(initial), do: Agent.start_link(fn -> initial end)
  def increment(counter), do: Agent.update(counter, & &1)
  def value(counter), do: Agent.get(counter, & &1)
  def stop(counter), do: Agent.stop(counter)
end

defmodule Victoria.Test.CounterModel do
  @moduledoc false
  @behaviour Victoria.Model

  alias Victoria.Test.Counter

  @impl Victoria.Model
  def init(%{"count" => initial}), do: Counter.start_link(initial)

  @impl Victoria.Model
  def execute(%Victoria.Step{action: "Increment"}, counter) do
    :ok = Counter.increment(counter)
    {:ok, counter}
  end

  def execute(%Victoria.Step{action: "Decrement"}, counter) do
    :ok = Counter.decrement(counter)
    {:ok, counter}
  end

  @impl Victoria.Model
  def snapshot(counter), do: %{"count" => Counter.value(counter)}

  @impl Victoria.Model
  def project(%Victoria.Step{state: state}), do: state

  @impl Victoria.Model
  def cleanup(counter), do: Counter.stop(counter)
end

defmodule Victoria.Test.BrokenCounterModel do
  @moduledoc false
  @behaviour Victoria.Model

  alias Victoria.Test.BrokenCounter

  @impl Victoria.Model
  def init(%{"count" => initial}), do: BrokenCounter.start_link(initial)

  @impl Victoria.Model
  def execute(%Victoria.Step{action: "Increment"}, counter) do
    :ok = BrokenCounter.increment(counter)
    {:ok, counter}
  end

  @impl Victoria.Model
  def snapshot(counter), do: %{"count" => BrokenCounter.value(counter)}

  @impl Victoria.Model
  def project(%Victoria.Step{state: state}), do: state

  @impl Victoria.Model
  def cleanup(counter), do: BrokenCounter.stop(counter)
end

defmodule Victoria.Test.InitialMismatchModel do
  @moduledoc false
  @behaviour Victoria.Model

  alias Victoria.Test.Counter

  @impl Victoria.Model
  def init(%{"count" => initial}), do: Counter.start_link(initial + 1)

  @impl Victoria.Model
  def execute(_step, counter) do
    send(self(), :initial_was_executed)
    {:ok, counter}
  end

  @impl Victoria.Model
  def snapshot(counter), do: %{"count" => Counter.value(counter)}

  @impl Victoria.Model
  def project(%Victoria.Step{state: state}), do: state

  @impl Victoria.Model
  def cleanup(counter), do: Counter.stop(counter)
end

defmodule Victoria.Test.TrackingCounterModel do
  @moduledoc false
  @behaviour Victoria.Model

  alias Victoria.Test.CounterModel

  @impl Victoria.Model
  def init(state) do
    send(self(), :init)
    CounterModel.init(state)
  end

  @impl Victoria.Model
  def execute(%Victoria.Step{action: action} = step, counter) do
    send(self(), {:execute, step.index, action})
    CounterModel.execute(step, counter)
  end

  @impl Victoria.Model
  defdelegate snapshot(counter), to: CounterModel

  @impl Victoria.Model
  defdelegate project(step), to: CounterModel

  @impl Victoria.Model
  def cleanup(counter) do
    send(self(), :cleanup)
    CounterModel.cleanup(counter)
  end
end

defmodule Victoria.Test.InitErrorModel do
  @moduledoc false
  @behaviour Victoria.Model

  @impl Victoria.Model
  def init(_state), do: {:error, :cannot_start}

  @impl Victoria.Model
  def execute(_step, implementation), do: {:ok, implementation}

  @impl Victoria.Model
  def snapshot(_implementation), do: %{}

  @impl Victoria.Model
  def project(_step), do: %{}
end

defmodule Victoria.Test.ExecuteErrorModel do
  @moduledoc false
  @behaviour Victoria.Model

  alias Victoria.Test.Counter

  @impl Victoria.Model
  def init(%{"count" => initial}), do: Counter.start_link(initial)

  @impl Victoria.Model
  def execute(_step, _counter), do: {:error, :command_failed}

  @impl Victoria.Model
  def snapshot(counter), do: %{"count" => Counter.value(counter)}

  @impl Victoria.Model
  def project(%Victoria.Step{state: state}), do: state

  @impl Victoria.Model
  def cleanup(counter) do
    send(self(), :cleanup)
    Counter.stop(counter)
  end
end

defmodule Victoria.Test.InvalidSnapshotModel do
  @moduledoc false

  alias Victoria.Test.Counter

  def init(%{"count" => initial}), do: Counter.start_link(initial)

  def execute(_step, counter), do: {:ok, counter}

  def snapshot(_counter), do: :not_a_map

  def project(%Victoria.Step{state: state}), do: state

  def cleanup(counter) do
    send(self(), :cleanup)
    :ok = Counter.stop(counter)
    {:error, :cleanup_failed}
  end
end

defmodule Victoria.Test.RaisedProjectModel do
  @moduledoc false
  @behaviour Victoria.Model

  alias Victoria.Test.Counter

  @impl Victoria.Model
  def init(%{"count" => initial}), do: Counter.start_link(initial)

  @impl Victoria.Model
  def execute(_step, counter), do: {:ok, counter}

  @impl Victoria.Model
  def snapshot(counter), do: %{"count" => Counter.value(counter)}

  @impl Victoria.Model
  def project(_step), do: raise("projection failed")

  @impl Victoria.Model
  def cleanup(counter) do
    send(self(), :cleanup)
    Counter.stop(counter)
  end
end

defmodule Victoria.Test.ThreadingModel do
  @moduledoc false
  @behaviour Victoria.Model

  @impl Victoria.Model
  def init(_state), do: {:ok, 0}

  @impl Victoria.Model
  def execute(%Victoria.Step{action: "Increment"}, count), do: {:ok, count + 1}
  def execute(%Victoria.Step{action: "Decrement"}, count), do: {:ok, count - 1}

  @impl Victoria.Model
  def snapshot(count), do: %{"count" => count}

  @impl Victoria.Model
  def project(%Victoria.Step{state: state}), do: state

  @impl Victoria.Model
  def cleanup(count) do
    send(self(), {:cleaned_up, count})
    :ok
  end
end

defmodule Victoria.Test.CleanupErrorModel do
  @moduledoc false
  @behaviour Victoria.Model

  alias Victoria.Test.CounterModel

  @impl Victoria.Model
  defdelegate init(state), to: CounterModel

  @impl Victoria.Model
  defdelegate execute(step, counter), to: CounterModel

  @impl Victoria.Model
  defdelegate snapshot(counter), to: CounterModel

  @impl Victoria.Model
  defdelegate project(step), to: CounterModel

  @impl Victoria.Model
  def cleanup(counter) do
    :ok = CounterModel.cleanup(counter)
    {:error, :cleanup_failed}
  end
end
