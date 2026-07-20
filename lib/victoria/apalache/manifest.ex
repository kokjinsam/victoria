defmodule Victoria.Apalache.Manifest do
  @moduledoc false

  alias Victoria.Apalache.Error
  alias Victoria.Apalache.Output
  alias Victoria.Apalache.Plan
  alias Victoria.Apalache.Result

  @filename "victoria-run.json"
  @writer_key {__MODULE__, :writer}

  @spec path(Plan.t()) :: Path.t()
  def path(%Plan{run_directory: run_directory}), do: Path.join(run_directory, @filename)

  @spec running(Plan.t(), Path.t(), Version.t(), DateTime.t()) :: map()
  def running(%Plan{} = plan, executable, version, %DateTime{} = started_at) do
    base(plan, executable, version, started_at)
  end

  @spec completed(
          Plan.t(),
          Path.t(),
          Version.t(),
          DateTime.t(),
          DateTime.t(),
          {:ok, Result.t()} | {:error, Error.t()}
        ) :: map()
  def completed(%Plan{} = plan, executable, version, %DateTime{} = started_at, %DateTime{} = completed_at, result) do
    completed_at = max_datetime(started_at, completed_at)

    plan
    |> base(executable, version, started_at)
    |> Map.merge(completed_fields(result, completed_at))
  end

  @spec write(:initial | :final, Path.t(), map()) :: :ok | {:error, term()}
  def write(stage, path, document) when stage in [:initial, :final] and is_binary(path) and is_map(document) do
    writer = Process.get(@writer_key, &write_atomic/2)

    try do
      writer.(path, document)
    rescue
      exception -> {:error, {:write, exception}}
    catch
      kind, reason -> {:error, {:write, {kind, reason}}}
    end
  end

  @doc false
  @spec with_writer((Path.t(), map() -> :ok | {:error, term()}), (-> result)) :: result when result: var
  def with_writer(writer, function) when is_function(writer, 2) and is_function(function, 0) do
    previous = Process.put(@writer_key, writer)

    try do
      function.()
    after
      restore_writer(previous)
    end
  end

  @spec write_atomic(Path.t(), map()) :: :ok | {:error, term()}
  def write_atomic(path, document) do
    with {:ok, encoded} <- encode(document) do
      persist(path, encoded <> "\n")
    end
  end

  defp base(plan, executable, version, started_at) do
    %{
      "schema" => "victoria.apalache.run",
      "schema_version" => 1,
      "status" => "running",
      "outcome" => nil,
      "producer" => %{"name" => "victoria", "version" => producer_version()},
      "started_at" => DateTime.to_iso8601(started_at),
      "completed_at" => nil,
      "spec" => %{"source" => plan.spec.source, "config" => plan.spec.config},
      "plan" => %{
        "mode" => Atom.to_string(plan.mode),
        "working_directory" => plan.working_directory,
        "run_directory" => plan.run_directory,
        "options" => Map.new(plan.options, fn {key, value} -> {Atom.to_string(key), value} end),
        "argv" => plan.argv
      },
      "execution" => %{
        "executable" => executable,
        "apalache_version" => Version.to_string(version),
        "exit_status" => nil,
        "output" => nil
      },
      "artifacts" => %{"trace_paths" => []},
      "failure" => nil
    }
  end

  defp completed_fields({:ok, %Result{} = result}, completed_at) do
    %{
      "status" => "completed",
      "outcome" => "materialized",
      "completed_at" => DateTime.to_iso8601(completed_at),
      "execution" => execution(result.exit_status, result.output, result.executable, result.version),
      "artifacts" => %{"trace_paths" => relative_paths(result.plan, result.trace_paths)},
      "failure" => nil
    }
  end

  defp completed_fields({:error, %Error{} = error}, completed_at) do
    %{
      "status" => "completed",
      "outcome" => "failed",
      "completed_at" => DateTime.to_iso8601(completed_at),
      "execution" => execution(error.exit_status, error.output, error.executable, error.version),
      "artifacts" => %{"trace_paths" => relative_paths(error.plan, error.trace_paths)},
      "failure" => failure(error)
    }
  end

  defp execution(exit_status, output, executable, version) do
    %{
      "executable" => executable,
      "apalache_version" => version && Version.to_string(version),
      "exit_status" => exit_status,
      "output" => output && stringify_keys(Output.summary(output))
    }
  end

  defp failure(error) do
    maybe_put_trace_path(
      %{
        "phase" => Atom.to_string(error.phase),
        "reason" => reason_code(error.reason),
        "message" => error |> Exception.message() |> Output.tail() |> elem(0)
      },
      error
    )
  end

  defp maybe_put_trace_path(summary, %Error{reason: {:invalid_trace, path, _reason}, plan: plan}) do
    Map.put(summary, "trace_path", Path.relative_to(path, plan.run_directory))
  end

  defp maybe_put_trace_path(summary, _error), do: summary

  defp reason_code(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp reason_code(reason) when is_tuple(reason) and tuple_size(reason) > 0 and is_atom(elem(reason, 0)),
    do: reason |> elem(0) |> Atom.to_string()

  defp reason_code(_reason), do: "unknown"

  defp relative_paths(plan, paths), do: Enum.map(paths, &Path.relative_to(&1, plan.run_directory))

  defp producer_version do
    case Application.spec(:victoria, :vsn) do
      nil -> nil
      version when is_list(version) -> List.to_string(version)
      version -> to_string(version)
    end
  end

  defp stringify_keys(map), do: Map.new(map, fn {key, value} -> {Atom.to_string(key), value} end)

  defp max_datetime(started_at, completed_at) do
    if DateTime.before?(completed_at, started_at), do: started_at, else: completed_at
  end

  defp encode(document) do
    {:ok, JSON.encode!(document)}
  rescue
    exception -> {:error, {:encoding, exception}}
  catch
    kind, reason -> {:error, {:encoding, {kind, reason}}}
  end

  defp persist(path, contents) do
    temporary_path = temporary_path(path)

    result =
      with :ok <- File.write(temporary_path, contents, [:exclusive, :binary]),
           :ok <- File.rename(temporary_path, path) do
        :ok
      else
        {:error, reason} -> {:error, {:write, reason}}
      end

    if result != :ok do
      _cleanup_result = File.rm(temporary_path)
    end

    result
  end

  defp temporary_path(path) do
    unique = System.unique_integer([:positive, :monotonic])

    path
    |> Path.dirname()
    |> Path.join(".#{Path.basename(path)}.tmp-#{unique}")
  end

  defp restore_writer(nil), do: Process.delete(@writer_key)
  defp restore_writer(previous), do: Process.put(@writer_key, previous)
end
