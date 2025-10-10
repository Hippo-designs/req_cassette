# .credo.exs
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "lib/",
          "test/"
        ],
        excluded: [
          ~r"/_build/",
          ~r"/deps/",
          ~r"/node_modules/"
        ]
      },
      plugins: [],
      requires: [],
      strict: true,
      parse_timeout: 5000,
      color: true,
      checks: %{
        enabled: [
          # Design Checks
          {Credo.Check.Design.AliasUsage, priority: :low, exit_status: 0},

          # Readability Checks
          {Credo.Check.Readability.ModuleDoc, false},
          {Credo.Check.Readability.MaxLineLength, priority: :low, max_length: 120},
          {Credo.Check.Readability.ParenthesesOnZeroArityDefs, false},
          {Credo.Check.Readability.Specs, false},

          # Refactoring Opportunities
          {Credo.Check.Refactor.CyclomaticComplexity, max_complexity: 12},
          {Credo.Check.Refactor.Nesting, max_nesting: 3},

          # Warnings
          {Credo.Check.Warning.LazyLogging, false}
        ],
        disabled: [
          # Disabled checks
          {Credo.Check.Readability.ModuleDoc, []},
          {Credo.Check.Readability.Specs, []}
        ]
      }
    }
  ]
}
