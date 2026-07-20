defmodule Victoria.Apalache do
  @moduledoc """
  Runs a validated Apalache plan and materializes every generated ITF trace.

  Execution is synchronous, supports exactly Apalache v0.58.3, invokes the
  executable without a shell, and retains the exclusively reserved run
  directory on success and failure. Victoria imposes no runtime timeout.
  """

  alias Victoria.Apalache.Error
  alias Victoria.Apalache.Manifest
  alias Victoria.Apalache.Plan
  alias Victoria.Apalache.Result
  alias Victoria.Trace

  @default_executable "apalache-mc"
  @supported_version Version.parse!("0.58.3")

  @spec run(Plan.t(), keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  @doc """
  Executes `plan` with Apalache v0.58.3.

  The only option is `:executable`. A successful result means at least one
  top-level regular ITF file was discovered and every discovered trace loaded;
  Apalache may have returned a nonzero status. Invalid arguments raise
  `ArgumentError`.
  """
  def run(plan, options \\ [])

  def run(%Plan{} = plan, options) do
    executable_option = validate_options!(options)

    with {:ok, executable} <- resolve_executable(plan, executable_option),
         {:ok, version, version_output} <- probe_version(plan, executable),
         :ok <- require_supported_version(plan, executable, version, version_output),
         :ok <- reserve_run_directory(plan, executable, version) do
      run_reserved(plan, executable, version)
    end
  end

  def run(_plan, _options) do
    raise ArgumentError, "expected the first argument to be a Victoria.Apalache.Plan"
  end

  defp validate_options!(options) do
    if !Keyword.keyword?(options) do
      raise ArgumentError, "expected options to be a keyword list"
    end

    keys = Keyword.keys(options)

    if length(keys) != length(Enum.uniq(keys)) do
      raise ArgumentError, "expected options to contain no duplicate keys"
    end

    unknown = keys -- [:executable]

    if unknown != [] do
      raise ArgumentError, "unknown options: #{inspect(unknown)}"
    end

    case Keyword.get(options, :executable, @default_executable) do
      executable when is_binary(executable) ->
        if String.trim(executable) == "" do
          raise ArgumentError, "expected :executable to be a non-blank string"
        end

        executable

      _executable ->
        raise ArgumentError, "expected :executable to be a non-blank string"
    end
  end

  defp resolve_executable(plan, executable) do
    if explicit_path?(executable) do
      path = Path.expand(executable)
      validate_executable_path(plan, path)
    else
      case System.find_executable(executable) do
        nil -> error(plan, :executable_discovery, :executable_not_found)
        path -> validate_executable_path(plan, Path.expand(path))
      end
    end
  end

  defp explicit_path?(executable), do: String.contains?(executable, ["/", "\\"])

  defp validate_executable_path(plan, path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular}} -> {:ok, path}
      {:ok, %File.Stat{}} -> error(plan, :executable_discovery, {:not_a_regular_file, path})
      {:error, :enoent} -> error(plan, :executable_discovery, :executable_not_found)
      {:error, reason} -> error(plan, :executable_discovery, {:filesystem, reason})
    end
  end

  defp probe_version(plan, executable) do
    case system_cmd(executable, ["version"], stderr_to_stdout: true) do
      {:ok, output, 0} ->
        parse_version(plan, executable, output)

      {:ok, output, exit_status} ->
        error(plan, :version_probe, {:version_process_failed, exit_status},
          executable: executable,
          exit_status: exit_status,
          output: output
        )

      {:error, reason} ->
        error(plan, :version_probe, {:version_process_start_failed, reason}, executable: executable)
    end
  end

  defp parse_version(plan, executable, output) do
    if String.valid?(output) do
      substantive_lines =
        output
        |> String.split(~r/\R/u)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      case substantive_lines do
        [line] -> parse_version_line(plan, executable, output, line)
        _lines -> unparseable_version(plan, executable, output)
      end
    else
      unparseable_version(plan, executable, output)
    end
  end

  defp parse_version_line(_plan, _executable, output, line) when line in ["0.58.3", "v0.58.3"] do
    {:ok, @supported_version, output}
  end

  defp parse_version_line(plan, executable, output, line) do
    normalized = if String.starts_with?(line, "v"), do: String.slice(line, 1..-1//1), else: line

    case Version.parse(normalized) do
      {:ok, %Version{pre: [], build: nil} = version} -> {:ok, version, output}
      _other -> unparseable_version(plan, executable, output)
    end
  end

  defp unparseable_version(plan, executable, output) do
    error(plan, :version_probe, {:unparseable_version, output}, executable: executable, output: output)
  end

  defp require_supported_version(_plan, _executable, @supported_version, _output), do: :ok

  defp require_supported_version(plan, executable, installed_version, output) do
    error(
      plan,
      :version_compatibility,
      {:unsupported_version, installed_version, @supported_version},
      executable: executable,
      version: installed_version,
      output: output
    )
  end

  defp reserve_run_directory(plan, executable, version) do
    parent = Path.dirname(plan.run_directory)

    case File.mkdir_p(parent) do
      :ok ->
        create_run_directory(plan, executable, version)

      {:error, reason} ->
        error(plan, :run_directory, {:parent_creation_failed, reason},
          executable: executable,
          version: version
        )
    end
  end

  defp create_run_directory(plan, executable, version) do
    case File.mkdir(plan.run_directory) do
      :ok ->
        :ok

      {:error, :eexist} ->
        error(plan, :run_directory, :run_directory_already_exists,
          executable: executable,
          version: version
        )

      {:error, reason} ->
        error(plan, :run_directory, {:run_directory_creation_failed, reason},
          executable: executable,
          version: version
        )
    end
  end

  defp execute(plan, executable, version) do
    options = [cd: plan.working_directory, stderr_to_stdout: true]

    case system_cmd(executable, plan.argv, options) do
      {:ok, output, exit_status} ->
        {:ok, output, exit_status}

      {:error, reason} ->
        error(plan, :execution, {:process_start_failed, reason},
          executable: executable,
          version: version
        )
    end
  end

  defp run_reserved(plan, executable, version) do
    started_at = DateTime.utc_now()
    manifest_path = Manifest.path(plan)
    running_manifest = Manifest.running(plan, executable, version, started_at)

    case Manifest.write(:initial, manifest_path, running_manifest) do
      :ok ->
        operation_result = execute_and_materialize(plan, executable, version)
        completed_at = DateTime.utc_now()
        completed_manifest = Manifest.completed(plan, executable, version, started_at, completed_at, operation_result)
        finalize(operation_result, manifest_path, completed_manifest)

      {:error, failure} ->
        manifest_error(plan, executable, version, :initial, manifest_path, failure)
    end
  end

  defp execute_and_materialize(plan, executable, version) do
    with {:ok, output, exit_status} <- execute(plan, executable, version),
         {:ok, trace_paths} <- discover_traces(plan, executable, version, output, exit_status),
         {:ok, traces} <- load_traces(plan, executable, version, output, exit_status, trace_paths) do
      {:ok,
       %Result{
         plan: plan,
         executable: executable,
         version: version,
         exit_status: exit_status,
         output: output,
         trace_paths: trace_paths,
         traces: traces
       }}
    end
  end

  defp finalize(operation_result, manifest_path, completed_manifest) do
    case Manifest.write(:final, manifest_path, completed_manifest) do
      :ok ->
        operation_result

      {:error, failure} ->
        final_manifest_failure(operation_result, manifest_path, failure)
    end
  end

  defp final_manifest_failure({:ok, %Result{} = result}, manifest_path, failure) do
    manifest_error(result.plan, result.executable, result.version, :final, manifest_path, failure,
      exit_status: result.exit_status,
      output: result.output,
      trace_paths: result.trace_paths
    )
  end

  defp final_manifest_failure({:error, %Error{} = error}, manifest_path, failure) do
    reason = manifest_reason(:final, manifest_path, failure)
    {:error, %{error | manifest_failure: reason}}
  end

  defp manifest_error(plan, executable, version, stage, manifest_path, failure, fields \\ []) do
    error(
      plan,
      :manifest,
      manifest_reason(stage, manifest_path, failure),
      Keyword.merge([executable: executable, version: version], fields)
    )
  end

  defp manifest_reason(stage, _manifest_path, {:encoding, cause}), do: {:manifest_encoding_failed, stage, cause}

  defp manifest_reason(stage, manifest_path, {:write, cause}), do: {:manifest_write_failed, stage, manifest_path, cause}

  defp manifest_reason(stage, manifest_path, cause), do: {:manifest_write_failed, stage, manifest_path, cause}

  defp system_cmd(executable, argv, options) do
    {output, exit_status} = System.cmd(executable, argv, options)
    {:ok, output, exit_status}
  rescue
    exception in ErlangError -> {:error, exception.original}
    exception in ArgumentError -> {:error, Exception.message(exception)}
  end

  defp discover_traces(plan, executable, version, output, exit_status) do
    case File.ls(plan.run_directory) do
      {:ok, names} ->
        discover_trace_files(plan, executable, version, output, exit_status, names)

      {:error, reason} ->
        error(plan, :trace_discovery, {:directory_listing_failed, reason},
          executable: executable,
          version: version,
          exit_status: exit_status,
          output: output
        )
    end
  end

  defp discover_trace_files(plan, executable, version, output, exit_status, names) do
    candidates = Enum.filter(names, &String.ends_with?(&1, ".itf.json"))

    case regular_trace_paths(plan, candidates) do
      {:ok, paths} ->
        case Enum.sort(paths) do
          [] when exit_status == 0 ->
            error(plan, :trace_discovery, :no_traces,
              executable: executable,
              version: version,
              exit_status: exit_status,
              output: output
            )

          [] ->
            error(plan, :execution, {:process_failed_without_trace, exit_status},
              executable: executable,
              version: version,
              exit_status: exit_status,
              output: output
            )

          paths ->
            {:ok, paths}
        end

      {:error, reason} ->
        error(plan, :trace_discovery, {:directory_listing_failed, reason},
          executable: executable,
          version: version,
          exit_status: exit_status,
          output: output
        )
    end
  end

  defp regular_trace_paths(plan, names) do
    Enum.reduce_while(names, {:ok, []}, fn name, {:ok, paths} ->
      path = Path.expand(Path.join(plan.run_directory, name))

      case File.lstat(path) do
        {:ok, %File.Stat{type: :regular}} -> {:cont, {:ok, [path | paths]}}
        {:ok, %File.Stat{}} -> {:cont, {:ok, paths}}
        {:error, reason} -> {:halt, {:error, {path, reason}}}
      end
    end)
  end

  defp load_traces(plan, executable, version, output, exit_status, trace_paths) do
    loading_result =
      Enum.reduce_while(trace_paths, {:ok, []}, fn path, {:ok, traces} ->
        case Trace.load(path) do
          {:ok, trace} -> {:cont, {:ok, [trace | traces]}}
          {:error, itf_error} -> {:halt, {:error, path, itf_error}}
        end
      end)

    case loading_result do
      {:ok, traces} ->
        {:ok, Enum.reverse(traces)}

      {:error, path, itf_error} ->
        error(plan, :trace_loading, {:invalid_trace, path, itf_error},
          executable: executable,
          version: version,
          exit_status: exit_status,
          output: output,
          trace_paths: trace_paths
        )
    end
  end

  defp error(plan, phase, reason, fields \\ []) do
    {:error, struct!(Error, Keyword.merge([plan: plan, phase: phase, reason: reason], fields))}
  end
end
