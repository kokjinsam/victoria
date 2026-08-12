defmodule Victoria.SpecTest do
  use ExUnit.Case, async: true

  alias Victoria.Spec

  @counter_source Path.expand("../specs/Counter.tla", __DIR__)
  @counter_config Path.expand("../specs/Counter.cfg", __DIR__)

  test "returns Apalachex specs" do
    assert {:ok, %Apalachex.Spec{source: @counter_source, config: nil}} =
             Spec.new(source: @counter_source)

    assert {:ok, %Apalachex.Spec{source: @counter_source, config: @counter_config}} =
             Spec.new(source: @counter_source, config: @counter_config)
  end

  test "preserves Apalachex specification errors exactly" do
    missing = Path.expand("../specs/Missing.tla", __DIR__)

    assert {:error, %Apalachex.Spec.Error{} = expected} = Apalachex.Spec.new(source: missing)
    assert {:error, ^expected} = Spec.new(source: missing)
  end
end
