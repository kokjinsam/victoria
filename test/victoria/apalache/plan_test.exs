defmodule Victoria.Apalache.PlanTest do
  use ExUnit.Case, async: false

  alias Victoria.Apalache.Plan
  alias Victoria.Spec

  @source Path.expand("../../specs/Counter.tla", __DIR__)
  @config Path.expand("../../specs/Counter.cfg", __DIR__)

  test "builds the exact simulate argv with config" do
    spec = %Spec{source: @source, config: @config}
    run_directory = Path.expand("tmp/a run")

    plan =
      Plan.new(spec,
        mode: :simulate,
        length: 10,
        max_run: 3,
        run_directory: run_directory
      )

    assert plan == %Plan{
             spec: spec,
             mode: :simulate,
             working_directory: Path.dirname(@source),
             run_directory: run_directory,
             options: %{length: 10, max_run: 3},
             argv: [
               "simulate",
               "--config=#{@config}",
               "--length=10",
               "--max-run=3",
               "--output-traces",
               "--run-dir=#{run_directory}",
               @source
             ]
           }

    assert "--run-dir=#{run_directory}" in plan.argv
  end

  test "builds the exact simulate argv without config" do
    spec = %Spec{source: @source, config: nil}
    run_directory = Path.expand("tmp/simulate")

    plan =
      Plan.new(spec,
        mode: :simulate,
        length: 0,
        max_run: 1,
        run_directory: run_directory
      )

    assert plan.argv == [
             "simulate",
             "--length=0",
             "--max-run=1",
             "--output-traces",
             "--run-dir=#{run_directory}",
             @source
           ]
  end

  test "builds exact check argv with and without config" do
    run_directory = Path.expand("tmp/check")

    assert %Plan{options: %{length: 7}, argv: with_config} =
             Plan.new(%Spec{source: @source, config: @config},
               mode: :check,
               length: 7,
               run_directory: run_directory
             )

    assert with_config == [
             "check",
             "--config=#{@config}",
             "--length=7",
             "--output-traces",
             "--run-dir=#{run_directory}",
             @source
           ]

    assert %Plan{argv: without_config} =
             Plan.new(%Spec{source: @source, config: nil},
               mode: :check,
               length: 7,
               run_directory: run_directory
             )

    assert without_config == [
             "check",
             "--length=7",
             "--output-traces",
             "--run-dir=#{run_directory}",
             @source
           ]
  end

  test "keeps paths containing spaces as single argv items" do
    source = "/tmp/formal models/Counter.tla"
    config = "/tmp/formal models/Counter.cfg"
    run_directory = "/tmp/generated traces/run one"

    plan =
      Plan.new(%Spec{source: source, config: config},
        mode: :check,
        length: 1,
        run_directory: run_directory
      )

    assert "--config=#{config}" in plan.argv
    assert "--run-dir=#{run_directory}" in plan.argv
    assert Enum.take(plan.argv, -1) == [source]
  end

  test "is reproducible and does not mutate the filesystem" do
    root = Path.join(System.tmp_dir!(), "victoria-plan-#{System.unique_integer([:positive])}")
    run_directory = Path.join(root, "planned")
    spec = %Spec{source: @source, config: nil}
    options = [mode: :check, length: 4, run_directory: run_directory]

    assert Plan.new(spec, options) == Plan.new(spec, options)
    refute File.exists?(root)
    refute File.exists?(run_directory)
  end

  test "expands run directory at construction and keeps it stable across cwd changes" do
    original_cwd = File.cwd!()

    try do
      File.cd!(System.tmp_dir!())
      expected = Path.expand("relative run")

      plan =
        Plan.new(%Spec{source: @source, config: nil},
          mode: :check,
          length: 1,
          run_directory: "relative run"
        )

      assert plan.run_directory == expected
      assert "--run-dir=#{expected}" in plan.argv

      File.cd!(original_cwd)
      assert plan.run_directory == expected
    after
      File.cd!(original_cwd)
    end
  end

  test "raises for invalid specs and strict option misuse" do
    spec = %Spec{source: @source, config: nil}

    invalid_calls = [
      fn -> Plan.new(%{}, mode: :check, length: 1, run_directory: "/tmp/run") end,
      fn -> plan(spec, :not_options) end,
      fn -> Plan.new(spec, []) end,
      fn -> Plan.new(spec, mode: :check, length: 1) end,
      fn -> Plan.new(spec, mode: :check, run_directory: "/tmp/run") end,
      fn -> Plan.new(spec, length: 1, run_directory: "/tmp/run") end,
      fn -> Plan.new(spec, mode: :other, length: 1, run_directory: "/tmp/run") end,
      fn -> Plan.new(spec, mode: :check, length: -1, run_directory: "/tmp/run") end,
      fn -> Plan.new(spec, mode: :check, length: 1.0, run_directory: "/tmp/run") end,
      fn -> Plan.new(spec, mode: :check, length: 1, max_run: 1, run_directory: "/tmp/run") end,
      fn -> Plan.new(spec, mode: :simulate, length: 1, run_directory: "/tmp/run") end,
      fn -> Plan.new(spec, mode: :simulate, length: 1, max_run: 0, run_directory: "/tmp/run") end,
      fn -> Plan.new(spec, mode: :simulate, length: 1, max_run: 1.0, run_directory: "/tmp/run") end,
      fn -> Plan.new(spec, mode: :check, mode: :check, length: 1, run_directory: "/tmp/run") end,
      fn -> Plan.new(spec, mode: :check, length: 1, run_directory: "/tmp/run", unknown: true) end,
      fn -> Plan.new(spec, mode: :check, length: 1, run_directory: nil) end,
      fn -> Plan.new(spec, mode: :check, length: 1, run_directory: "\t") end
    ]

    for call <- invalid_calls do
      assert_raise ArgumentError, call
    end
  end

  defp plan(spec, options), do: Plan.new(spec, options)
end
