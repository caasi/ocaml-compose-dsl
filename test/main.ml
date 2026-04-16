let () =
  Alcotest.run "compose-dsl"
    [ "Lexer", Test_lexer.tests
    ; "Parser", Test_parser.tests
    ; "Checker", Test_checker.tests
    ; "Printer", Test_printer.tests
    ; "Reducer", Test_reducer.tests
    ; "Integration", Test_integration.tests
    ; "Edge cases", Test_parser.edge_case_tests
    ; "Mixed args", Test_integration.mixed_arg_tests
    ; "Markdown", Test_markdown.tests
    ; "Markdown integration", Test_markdown.integration_tests
    ; "Properties", Test_properties.tests
    ]
