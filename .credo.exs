%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "lib/",
          "test/"
        ],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      checks: %{
        enabled: [
          {Credo.Check.Refactor.CyclomaticComplexity, [max_complexity: 9]},
          {Credo.Check.Refactor.Nesting, [max_nesting: 2]},
          {Credo.Check.Readability.WithSingleClause, []}
        ],
        disabled: [
          # Module docs will be added systematically — not one-off nagging
          {Credo.Check.Readability.ModuleDoc, []}
        ]
      }
    }
  ]
}
