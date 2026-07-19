defmodule Victoria.ApalacheTest do
  use ExUnit.Case, async: false

  alias Victoria.Apalache
  alias Victoria.Apalache.Error
  alias Victoria.Apalache.Plan
  alias Victoria.Apalache.Result
  alias Victoria.ITF
  alias Victoria.Spec

  @fixture_executable Path.expand("../fixtures/apalache/fake-apalache", __DIR__)
  @valid_trace Path.expand("../fixtures/counter.itf.json", __DIR__)
  @malformed_trace Path.expand("../fixtures/malformed_json.itf.json", __DIR__)
  @unsupported_trace Path.expand("../fixtures/unsupported_set.itf.json", __DIR__)
  @loop_trace Path.expand("../fixtures/loop.itf.json", __DIR__)
  @source Path.expand("../specs/Counter.tla", __DIR__)
  @config Path.expand("../specs/Counter.cfg", __DIR__)

  setup do
    root = Path.join(System.tmp_dir!(), "victoria-apalache-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "raises for strict API misuse", %{root: root} do
    plan = root |> Path.join("run") |> plan()
    apalache = Module.safe_concat(["Victoria", "Apalache"])

    invalid_calls = [
      fn -> Apalache.run(%{}, []) end,
      fn -> apalache.run(plan, %{executable: "tool"}) end,
      fn -> Apalache.run(plan, executable: "a", executable: "b") end,
      fn -> Apalache.run(plan, unknown: true) end,
      fn -> Apalache.run(plan, executable: "") end,
      fn -> Apalache.run(plan, executable: " \t") end,
      fn -> Apalache.run(plan, executable: 123) end
    ]

    for call <- invalid_calls do
      assert_raise ArgumentError, call
    end
  end

  test "resolves the omitted executable and bare names through PATH and restores PATH", %{root: root} do
    executable = install_fake(root, "apalache-mc")
    original_path = System.get_env("PATH")

    try do
      System.put_env("PATH", Path.dirname(executable) <> ":" <> (original_path || ""))

      assert {:ok, %Result{executable: ^executable}} =
               root |> Path.join("default") |> plan() |> Apalache.run()

      assert {:ok, %Result{executable: ^executable}} =
               root |> Path.join("bare") |> plan() |> Apalache.run(executable: "apalache-mc")
    after
      restore_env("PATH", original_path)
    end
  end

  test "reports an omitted executable missing from PATH and restores PATH", %{root: root} do
    original_path = System.get_env("PATH")

    try do
      System.put_env("PATH", "")

      assert {:error, %Error{phase: :executable_discovery, reason: :executable_not_found}} =
               root |> Path.join("run") |> plan() |> Apalache.run()
    after
      restore_env("PATH", original_path)
    end
  end

  test "expands explicit relative executables against the call-time process cwd", %{root: root} do
    _executable = install_fake(root, "relative-apalache")
    original_cwd = File.cwd!()

    try do
      File.cd!(root)
      expanded_executable = Path.expand("./relative-apalache")

      assert {:ok, %Result{executable: ^expanded_executable}} =
               root |> Path.join("run") |> plan() |> Apalache.run(executable: "./relative-apalache")
    after
      File.cd!(original_cwd)
    end
  end

  test "supports absolute executable paths containing spaces", %{root: root} do
    directory = Path.join(root, "tools with spaces")
    executable = install_fake(directory, "fake apalache")

    assert {:ok, %Result{executable: ^executable}} =
             root |> Path.join("run") |> plan() |> Apalache.run(executable: executable)
  end

  test "rejects missing explicit paths and directories", %{root: root} do
    run = root |> Path.join("run") |> plan()
    missing = Path.join(root, "missing/apalache")

    assert {:error, %Error{phase: :executable_discovery, reason: :executable_not_found}} =
             Apalache.run(run, executable: missing)

    assert {:error, %Error{phase: :executable_discovery, reason: {:not_a_regular_file, ^root}}} =
             Apalache.run(run, executable: root)
  end

  test "accepts only the supported version identity forms", %{root: root} do
    supported = root |> Path.join("supported") |> install_fake("supported")
    prefixed = root |> Path.join("prefixed") |> install_fake("prefixed")

    assert {:ok, %Result{version: %Version{major: 0, minor: 58, patch: 3}}} =
             root |> Path.join("supported-run") |> plan() |> Apalache.run(executable: supported)

    assert {:ok, %Result{version: %Version{major: 0, minor: 58, patch: 3}}} =
             root |> Path.join("prefixed-run") |> plan() |> Apalache.run(executable: prefixed)
  end

  test "rejects unsupported, banner, prerelease, and failed version probes before reservation", %{root: root} do
    cases = [
      {"unsupported", :version_compatibility, :unsupported_version},
      {"banner", :version_probe, :unparseable_version},
      {"prerelease", :version_probe, :unparseable_version},
      {"build-version", :version_probe, :unparseable_version},
      {"empty-version", :version_probe, :unparseable_version},
      {"version-fail", :version_probe, :version_process_failed}
    ]

    for {name, phase, reason_tag} <- cases do
      executable = root |> Path.join(name) |> install_fake(name)
      run_directory = Path.join(root, "#{name}-run")

      assert {:error, %Error{phase: ^phase, reason: reason}} =
               run_directory |> plan() |> Apalache.run(executable: executable)

      assert reason_tag(reason) == reason_tag
      refute File.exists?(run_directory)
    end
  end

  test "rejects invalid version bytes before reservation and preserves them exactly", %{root: root} do
    executable = root |> Path.join("invalid-version") |> install_fake("invalid-version")
    run_directory = Path.join(root, "run")
    output = <<255, "version\n">>

    assert {:error,
            %Error{
              phase: :version_probe,
              reason: {:unparseable_version, ^output},
              output: ^output
            }} = run_directory |> plan() |> Apalache.run(executable: executable)

    refute File.exists?(run_directory)
  end

  test "structures a version-probe process-start failure before reservation", %{root: root} do
    executable = root |> Path.join("tool") |> install_fake("supported")
    File.chmod!(executable, 0o644)
    run_directory = Path.join(root, "run")

    assert {:error, %Error{phase: :version_probe, reason: {:version_process_start_failed, _reason}}} =
             run_directory |> plan() |> Apalache.run(executable: executable)

    refute File.exists?(run_directory)
  end

  test "reserves the exact run directory exclusively and creates its parent", %{root: root} do
    executable = root |> Path.join("tool") |> install_fake("supported")
    run_directory = Path.join([root, "new", "parent", "exact"])

    assert {:ok, %Result{plan: %Plan{run_directory: ^run_directory}}} =
             run_directory |> plan() |> Apalache.run(executable: executable)

    assert File.dir?(run_directory)

    assert {:error, %Error{phase: :run_directory, reason: :run_directory_already_exists}} =
             run_directory |> plan() |> Apalache.run(executable: executable)
  end

  test "does not reuse an existing file or delete existing directory content", %{root: root} do
    executable = root |> Path.join("tool") |> install_fake("supported")
    file_path = Path.join(root, "existing-file")
    File.write!(file_path, "keep")

    assert {:error, %Error{phase: :run_directory, reason: :run_directory_already_exists}} =
             file_path |> plan() |> Apalache.run(executable: executable)

    directory = Path.join(root, "existing-directory")
    File.mkdir!(directory)
    sentinel = Path.join(directory, "keep.txt")
    File.write!(sentinel, "keep")

    assert {:error, %Error{phase: :run_directory, reason: :run_directory_already_exists}} =
             directory |> plan() |> Apalache.run(executable: executable)

    assert File.read!(sentinel) == "keep"
  end

  test "structures parent creation failures", %{root: root} do
    executable = root |> Path.join("tool") |> install_fake("supported")
    blocked_parent = Path.join(root, "blocked")
    File.write!(blocked_parent, "file")

    assert {:error, %Error{phase: :run_directory, reason: {:parent_creation_failed, _reason}}} =
             blocked_parent |> Path.join("run") |> plan() |> Apalache.run(executable: executable)
  end

  test "preserves exact argv, working directory, merged output, and shell-free arguments", %{root: root} do
    executable = root |> Path.join("tool") |> install_fake("supported")
    working_directory = Path.join(root, "formal models")
    File.mkdir_p!(working_directory)
    source = Path.join(working_directory, "$(touch forbidden).tla")
    File.write!(source, "fixture")
    forbidden = Path.join(working_directory, "forbidden")
    run_directory = Path.join(root, "run")

    custom_plan =
      Plan.new(%Spec{source: source, config: nil},
        mode: :simulate,
        length: 2,
        max_run: 1,
        run_directory: run_directory
      )

    assert {:ok, %Result{output: output, exit_status: 0}} =
             Apalache.run(custom_plan, executable: executable)

    assert output =~ "standard output"
    assert output =~ "standard error"

    actual_working_directory =
      run_directory |> Path.join("working-directory.txt") |> File.read!() |> String.trim()

    assert canonical_directory(actual_working_directory) == canonical_directory(working_directory)

    assert run_directory |> Path.join("argv.txt") |> File.read!() |> String.split("\n", trim: true) == custom_plan.argv
    refute File.exists?(forbidden)
  end

  test "returns success for zero and nonzero exits when every discovered trace validates", %{root: root} do
    zero = root |> Path.join("zero") |> install_fake("valid")
    nonzero = root |> Path.join("nonzero") |> install_fake("valid-nonzero")

    assert {:ok, %Result{exit_status: 0, traces: [_zero_trace]}} =
             root |> Path.join("zero-run") |> plan() |> Apalache.run(executable: zero)

    assert {:ok, %Result{exit_status: 12, traces: [_nonzero_trace]}} =
             root |> Path.join("nonzero-run") |> plan() |> Apalache.run(executable: nonzero)
  end

  test "classifies no-trace outcomes and retains their run directories", %{root: root} do
    zero = root |> Path.join("zero") |> install_fake("no-trace")
    nonzero = root |> Path.join("nonzero") |> install_fake("no-trace-nonzero")
    zero_run = Path.join(root, "zero-run")
    nonzero_run = Path.join(root, "nonzero-run")

    assert {:error, %Error{phase: :trace_discovery, reason: :no_traces, exit_status: 0}} =
             zero_run |> plan() |> Apalache.run(executable: zero)

    assert {:error, %Error{phase: :execution, reason: {:process_failed_without_trace, 9}, exit_status: 9}} =
             nonzero_run |> plan() |> Apalache.run(executable: nonzero)

    assert File.dir?(zero_run)
    assert File.dir?(nonzero_run)
  end

  test "structures process-start failures and retains the reserved run directory", %{root: root} do
    executable = root |> Path.join("tool") |> install_fake("start-fail")
    run_directory = Path.join(root, "run")

    assert {:error, %Error{phase: :execution, reason: {:process_start_failed, _reason}}} =
             run_directory |> plan() |> Apalache.run(executable: executable)

    assert File.dir?(run_directory)
  end

  test "discovers only actual top-level regular ITF files and sorts paths lexically", %{root: root} do
    multiple = root |> Path.join("multiple") |> install_fake("multiple")
    run_directory = Path.join(root, "multiple-run")

    assert {:ok, %Result{trace_paths: paths, traces: traces}} =
             run_directory |> plan() |> Apalache.run(executable: multiple)

    assert paths == Enum.sort(paths)
    assert Enum.map(paths, &Path.basename/1) == ["a.itf.json", "z.itf.json"]
    assert Enum.map(traces, & &1.source) == paths

    types = root |> Path.join("types") |> install_fake("discovery-types")

    assert {:ok, %Result{trace_paths: [regular]}} =
             root |> Path.join("types-run") |> plan() |> Apalache.run(executable: types)

    assert Path.basename(regular) == "regular.itf.json"
  end

  test "loads traces all-or-nothing and preserves the nested ITF error and every path", %{root: root} do
    executable = root |> Path.join("tool") |> install_fake("mixed")
    run_directory = Path.join(root, "run")

    assert {:error,
            %Error{
              phase: :trace_loading,
              reason: {:invalid_trace, failing_path, %ITF.Error{} = nested},
              trace_paths: paths,
              exit_status: 0
            }} = run_directory |> plan() |> Apalache.run(executable: executable)

    assert Path.basename(failing_path) == "b-invalid.itf.json"
    assert nested.source == failing_path
    assert Enum.map(paths, &Path.basename/1) == ["a-valid.itf.json", "b-invalid.itf.json"]
    assert File.dir?(run_directory)
  end

  test "wraps unsupported ITF values without flattening their structured paths", %{root: root} do
    executable = root |> Path.join("tool") |> install_fake("bad-value")

    assert {:error,
            %Error{
              phase: :trace_loading,
              reason: {:invalid_trace, path, %ITF.Error{kind: :shape, path: nested_path}}
            }} = root |> Path.join("run") |> plan() |> Apalache.run(executable: executable)

    assert Path.basename(path) == "unsupported.itf.json"
    assert nested_path != []
  end

  test "materializes a lasso unchanged without replaying it", %{root: root} do
    executable = root |> Path.join("tool") |> install_fake("lasso")

    assert {:ok, %Result{traces: [trace]}} =
             root |> Path.join("run") |> plan() |> Apalache.run(executable: executable)

    assert trace.loop_index == 1
  end

  test "bounds rendered output while preserving complete output in the error", %{root: root} do
    executable = root |> Path.join("tool") |> install_fake("long-output")

    assert {:error, %Error{output: output} = error} =
             root |> Path.join("run") |> plan() |> Apalache.run(executable: executable)

    assert byte_size(output) > 6000
    assert byte_size(Exception.message(error)) < byte_size(output)
    assert Exception.message(error) =~ "run directory"
  end

  test "aligns a multibyte output tail without changing stored bytes", %{root: root} do
    executable = root |> Path.join("multibyte-boundary") |> install_fake("multibyte-boundary")
    expected_output = "standard output\nstandard error\n\u20ac" <> String.duplicate("x", 4094)

    assert {:error, %Error{output: ^expected_output} = error} =
             root |> Path.join("run") |> plan() |> Apalache.run(executable: executable)

    message = Exception.message(error)

    assert String.valid?(message)
    assert byte_size(message) < 5000
    assert message =~ "output tail:\n" <> String.duplicate("x", 4094)
  end

  test "escapes short invalid output without changing stored bytes", %{root: root} do
    executable = root |> Path.join("short-bad-bytes") |> install_fake("short-bad-bytes")
    expected_output = <<"standard output\nstandard error\n", 255, 254>>

    assert {:error, %Error{output: ^expected_output} = error} =
             root |> Path.join("run") |> plan() |> Apalache.run(executable: executable)

    message = Exception.message(error)

    assert String.valid?(message)
    assert message =~ "output tail:\n<<"
  end

  defp plan(run_directory) do
    Plan.new(%Spec{source: @source, config: @config},
      mode: :simulate,
      length: 2,
      max_run: 1,
      run_directory: run_directory
    )
  end

  defp install_fake(directory, name) do
    File.mkdir_p!(directory)
    executable = Path.join(directory, name)
    File.cp!(@fixture_executable, executable)
    File.cp!(@valid_trace, Path.join(directory, "valid.itf.json"))
    File.cp!(@malformed_trace, Path.join(directory, "malformed.itf.json"))
    File.cp!(@unsupported_trace, Path.join(directory, "unsupported.itf.json"))
    File.cp!(@loop_trace, Path.join(directory, "loop.itf.json"))
    File.chmod!(executable, 0o755)
    Path.expand(executable)
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)

  defp canonical_directory(path), do: File.cd!(path, &File.cwd!/0)

  defp reason_tag({tag, _one}), do: tag
  defp reason_tag({tag, _one, _two}), do: tag
end
