defmodule Victoria.Apalache.RunDirectoryTest do
  use ExUnit.Case, async: true

  alias Victoria.Apalache.RunDirectory
  alias Victoria.Spec

  @source Path.expand("../../specs/Counter.tla", __DIR__)
  @generated_at ~U[2026-07-19 12:34:56.987654Z]

  test "builds a deterministic path under the default root" do
    spec = spec(@source)

    assert RunDirectory.build(spec, generated_at: @generated_at, suffix: "0a1b2c") ==
             Path.expand("tmp/victoria/20260719T123456Z-counter-0a1b2c")
  end

  test "uses a custom expanded root without creating it" do
    root = Path.join(System.tmp_dir!(), "victoria-absent-#{System.unique_integer([:positive])}")
    spec = spec(@source)

    run_directory =
      RunDirectory.build(spec,
        generated_at: @generated_at,
        suffix: "abcdef",
        root: root
      )

    assert run_directory == Path.join(root, "20260719T123456Z-counter-abcdef")
    refute File.exists?(root)
    refute File.exists?(run_directory)
  end

  test "normalizes the basename to an ASCII slug with a fallback" do
    assert build_for("My  HTTP___Spec-2.tla") =~ "/20260719T123456Z-my-http-spec-2-abcdef"
    assert build_for("ÅÄ!!!.tla") =~ "/20260719T123456Z-spec-abcdef"
    assert build_for("A---B.tla") =~ "/20260719T123456Z-a-b-abcdef"
  end

  test "accepts a zero-offset DateTime regardless of zone name" do
    generated_at = %{@generated_at | time_zone: "Etc/Whatever", zone_abbr: "LOCAL"}

    assert build_for("Counter.tla", generated_at) =~
             "/20260719T123456Z-counter-abcdef"
  end

  test "raises for invalid specs and option misuse" do
    spec = spec(@source)

    invalid_calls = [
      fn -> RunDirectory.build(%{}, generated_at: @generated_at, suffix: "abcdef") end,
      fn -> build(spec, :not_options) end,
      fn -> RunDirectory.build(spec, []) end,
      fn -> RunDirectory.build(spec, generated_at: @generated_at) end,
      fn -> RunDirectory.build(spec, suffix: "abcdef") end,
      fn ->
        RunDirectory.build(spec,
          generated_at: @generated_at,
          generated_at: @generated_at,
          suffix: "abcdef"
        )
      end,
      fn ->
        RunDirectory.build(spec, generated_at: @generated_at, suffix: "abcdef", unknown: true)
      end,
      fn -> RunDirectory.build(spec, generated_at: DateTime.to_naive(@generated_at), suffix: "abcdef") end,
      fn ->
        RunDirectory.build(spec,
          generated_at: %{@generated_at | utc_offset: 3600},
          suffix: "abcdef"
        )
      end,
      fn -> RunDirectory.build(spec, generated_at: @generated_at, suffix: "ABCDEF") end,
      fn -> RunDirectory.build(spec, generated_at: @generated_at, suffix: "abcde") end,
      fn -> RunDirectory.build(spec, generated_at: @generated_at, suffix: "abcdef0") end,
      fn -> RunDirectory.build(spec, generated_at: @generated_at, suffix: "abcde-") end,
      fn -> RunDirectory.build(spec, generated_at: @generated_at, suffix: 123_456) end,
      fn -> RunDirectory.build(spec, generated_at: @generated_at, suffix: "abcdef", root: nil) end,
      fn -> RunDirectory.build(spec, generated_at: @generated_at, suffix: "abcdef", root: " ") end
    ]

    for call <- invalid_calls do
      assert_raise ArgumentError, call
    end
  end

  defp build_for(name, generated_at \\ @generated_at) do
    source = Path.join("/unused", name)

    source
    |> spec()
    |> RunDirectory.build(
      generated_at: generated_at,
      suffix: "abcdef",
      root: "/tmp/victoria-run-directory-test"
    )
  end

  defp build(spec, options), do: RunDirectory.build(spec, options)
  defp spec(source), do: %Spec{source: source, config: nil}
end
