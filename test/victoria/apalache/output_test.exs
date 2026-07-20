defmodule Victoria.Apalache.OutputTest do
  use ExUnit.Case, async: true

  alias Victoria.Apalache.Output

  test "summarizes empty and ordinary UTF-8 output" do
    assert Output.summary("") == %{byte_size: 0, tail: "", tail_truncated: false}

    assert Output.summary("ordinary output") == %{
             byte_size: 15,
             tail: "ordinary output",
             tail_truncated: false
           }
  end

  test "bounds a valid UTF-8 tail by final byte size without splitting a codepoint" do
    output = String.duplicate("x", 10) <> "€" <> String.duplicate("y", 4094)
    summary = Output.summary(output)

    assert summary.byte_size == byte_size(output)
    assert summary.tail_truncated
    assert summary.tail == String.duplicate("y", 4094)
    assert String.valid?(summary.tail)
    assert byte_size(summary.tail) <= 4096
  end

  test "renders invalid bytes as a bounded valid UTF-8 diagnostic" do
    output = :binary.copy(<<255>>, 5000)
    summary = Output.summary(output)

    assert summary.byte_size == 5000
    assert summary.tail_truncated
    assert String.valid?(summary.tail)
    assert byte_size(summary.tail) <= 4096
  end
end
