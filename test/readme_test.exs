defmodule SourcerorTest.ReadmeTest do
  use ExUnit.Case, async: true

  alias SourcerorTest.Support.Parser
  require Parser

  @project Sourceror.MixProject.project()

  readme_path = Parser.resource("README.md")
  readme = Parser.code_blocks(readme_path)

  @readme readme

  test "the version numbers match" do
    assert @readme |> hd |> elem(0) =~ @project[:version]
  end

  env = __ENV__

  readme
  |> tl
  |> Enum.each(
    &Code.eval_string(
      elem(&1, 0),
      [],
      %{env | file: readme_path, line: elem(&1, 1)}
    )
  )

  @external_resource readme_path
end
