defmodule VictoriaGeneratedConsumerTest do
  use ExUnit.Case

  import Victoria.ExUnit

  @moduletag :consumer

  test "verifies a consumer-owned spec through the unpacked package and real Apalache" do
    spec_root = Path.expand("specs", __DIR__)

    artifact_root =
      "VICTORIA_PACKAGE_PATH"
      |> System.fetch_env!()
      |> Path.dirname()
      |> Path.join("artifacts")

    on_exit(fn -> File.rm_rf!(artifact_root) end)

    {:ok, spec} =
      Victoria.Spec.new(
        source: Path.join(spec_root, "Counter.tla"),
        config: Path.join(spec_root, "Counter.cfg")
      )

    assert :ok =
             assert_conform(
               VictoriaGeneratedConsumer.Model,
               spec,
               plan: [mode: :simulate, length: 2, max_run: 1],
               artifacts: [root: artifact_root]
             )
  end
end
