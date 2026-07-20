defmodule VictoriaFixedConsumerTest do
  use ExUnit.Case

  import Victoria.ExUnit

  @moduletag :consumer

  test "verifies a consumer-owned fixed trace through the unpacked package" do
    assert :ok =
             assert_conform(
               VictoriaFixedConsumer.Model,
               trace: Path.expand("fixtures/counter.itf.json", __DIR__)
             )
  end
end
