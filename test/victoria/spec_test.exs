defmodule Victoria.SpecTest do
  use ExUnit.Case, async: false

  alias Victoria.Spec
  alias Victoria.Spec.Error

  @counter_source Path.expand("../specs/Counter.tla", __DIR__)
  @counter_config Path.expand("../specs/Counter.cfg", __DIR__)

  setup do
    directory = Path.join(System.tmp_dir!(), "victoria-spec-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    %{directory: directory}
  end

  test "builds a spec with an optional config" do
    assert {:ok, %Spec{source: @counter_source, config: nil}} =
             Spec.new(source: @counter_source)

    assert {:ok, %Spec{source: @counter_source, config: @counter_config}} =
             Spec.new(source: @counter_source, config: @counter_config)
  end

  test "expands paths from the cwd at construction and keeps them stable", %{directory: directory} do
    source = Path.join(directory, "Counter.tla")
    config = Path.join(directory, "Counter.cfg")
    File.write!(source, "---- MODULE Counter ----")
    File.write!(config, "INIT Init")

    original_cwd = File.cwd!()

    try do
      File.cd!(directory)
      expanded_source = Path.expand("Counter.tla")
      expanded_config = Path.expand("Counter.cfg")
      assert {:ok, spec} = Spec.new(source: "Counter.tla", config: "Counter.cfg")
      assert spec.source == expanded_source
      assert spec.config == expanded_config

      directory
      |> Path.dirname()
      |> File.cd!()

      assert spec.source == expanded_source
      assert spec.config == expanded_config
    after
      File.cd!(original_cwd)
    end
  end

  test "allows source and config to be in separate directories", %{directory: directory} do
    source_directory = Path.join(directory, "source")
    config_directory = Path.join(directory, "config")
    File.mkdir_p!(source_directory)
    File.mkdir_p!(config_directory)
    source = Path.join(source_directory, "Separate.tla")
    config = Path.join(config_directory, "Separate.cfg")
    File.write!(source, "---- MODULE Separate ----")
    File.write!(config, "INIT Init")

    assert {:ok, %Spec{source: ^source, config: ^config}} =
             Spec.new(source: source, config: config)
  end

  test "preserves an expanded symlink path instead of canonicalizing it", %{directory: directory} do
    target = Path.join(directory, "Target.tla")
    link = Path.join(directory, "Linked.tla")
    File.write!(target, "---- MODULE Target ----")
    File.ln_s!(target, link)

    assert {:ok, %Spec{source: ^link}} = Spec.new(source: link)
  end

  test "raises for option-shape misuse" do
    invalid_options = [
      :not_a_keyword_list,
      [],
      [source: @counter_source, source: @counter_source],
      [source: @counter_source, unknown: true],
      [source: nil],
      [source: "  "],
      [source: @counter_source, config: nil],
      [source: @counter_source, config: 42],
      [source: @counter_source, config: "\t"]
    ]

    for options <- invalid_options do
      assert_raise ArgumentError, fn -> Spec.new(options) end
    end
  end

  test "requires exact case-sensitive extensions before filesystem validation", %{directory: directory} do
    uppercase_source = Path.join(directory, "Missing.TLA")
    wrong_source = Path.join(directory, "Missing.txt")
    extensionless_source = Path.join(directory, "Missing")

    assert {:error,
            %Error{
              field: :source,
              path: ^uppercase_source,
              reason: {:invalid_extension, ".TLA"}
            }} = Spec.new(source: uppercase_source)

    assert {:error, %Error{reason: {:invalid_extension, ".txt"}}} =
             Spec.new(source: wrong_source)

    assert {:error, %Error{reason: {:invalid_extension, ""}}} =
             Spec.new(source: extensionless_source)
  end

  test "reports missing and non-regular files with the responsible field", %{directory: directory} do
    missing_source = Path.join(directory, "Missing.tla")

    assert {:error, %Error{field: :source, path: ^missing_source, reason: :not_found}} =
             Spec.new(source: missing_source)

    config_directory = Path.join(directory, "Directory.cfg")
    File.mkdir!(config_directory)

    assert {:error, %Error{field: :config, path: ^config_directory, reason: :not_a_regular_file}} =
             Spec.new(source: @counter_source, config: config_directory)
  end

  test "renders a useful structured error" do
    error = %Error{field: :config, path: "/tmp/Counter.CFG", reason: {:invalid_extension, ".CFG"}}
    message = Exception.message(error)

    assert message =~ "Victoria specification error"
    assert message =~ "config"
    assert message =~ "/tmp/Counter.CFG"
    assert message =~ "invalid extension"
    assert message =~ ".CFG"

    assert Exception.message(%Error{field: :source, path: "/tmp/A.tla", reason: :not_found}) =~
             "file was not found"

    assert Exception.message(%Error{
             field: :source,
             path: "/tmp/A.tla",
             reason: {:filesystem, :eacces}
           }) =~ "filesystem error"
  end
end
