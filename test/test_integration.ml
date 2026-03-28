open Compose_dsl
open Helpers

(* Integration: full pipeline parse_program >>> reduce >>> check *)
let test_integration_let_and_check () =
  let input = "let f = \\ x -> x >>> a in f(b)" in
  let tokens = Lexer.tokenize input in
  let ast = Parser.parse_program tokens in
  let reduced = Reducer.reduce ast in
  let result = Checker.check reduced in
  Alcotest.(check int) "no warnings" 0 (List.length result.Checker.warnings)

let test_integration_backward_compat () =
  let input = "a >>> b *** c" in
  let tokens = Lexer.tokenize input in
  let ast = Parser.parse_program tokens in
  let reduced = Reducer.reduce ast in
  let result = Checker.check reduced in
  Alcotest.(check int) "no warnings" 0 (List.length result.Checker.warnings)

let test_parse_mixed_args () =
  let ast = parse_ok {|push(remote: origin, v)|} in
  match ast.desc with
  | App ({ desc = Var "push"; _ }, [Named { key = "remote"; _ }; Positional { desc = Var "v"; _ }]) -> ()
  | _ -> Alcotest.fail "expected App(Var push, [Named, Positional])"

let test_parse_positional_then_named () =
  let ast = parse_ok {|deploy(stage, env: production)|} in
  match ast.desc with
  | App ({ desc = Var "deploy"; _ }, [Positional { desc = Var "stage"; _ }; Named { key = "env"; value = Ident "production" }]) -> ()
  | _ -> Alcotest.fail "expected App with positional then named"

let test_parse_multiple_positional () =
  let ast = parse_ok {|f(a >>> b, c)|} in
  match ast.desc with
  | App ({ desc = Var "f"; _ }, [Positional { desc = Seq _; _ }; Positional { desc = Var "c"; _ }]) -> ()
  | _ -> Alcotest.fail "expected App with two positional args"

let test_parse_app_question () =
  let ast = parse_ok {|check(strict: true)?|} in
  match ast.desc with
  | Question { desc = App ({ desc = Var "check"; _ }, [Named _]); _ } -> ()
  | _ -> Alcotest.fail "expected Question(App(...))"

let test_parse_var_question () =
  let ast = parse_ok {|ready?|} in
  match ast.desc with
  | Question { desc = Var "ready"; _ } -> ()
  | _ -> Alcotest.fail "expected Question(Var)"

let test_parse_empty_parens_app () =
  match desc_of "noop()" with
  | App ({ desc = Var "noop"; _ }, [Positional { desc = Unit; _ }]) -> ()
  | _ -> Alcotest.fail "expected App(Var noop, [Positional Unit])"

let test_reduce_mixed_args () =
  let ast = reduce_ok "let v = a >>> b in push(remote: origin, v)" in
  Alcotest.(check string) "printed"
    {|App(Var("push"), [Named(remote: Ident("origin")), Positional(Seq(Var("a"), Var("b")))])|}
    (Printer.to_string ast)

let test_reduce_named_args_on_lambda_error () =
  reduce_fails "let f = \\ x -> x in f(key: val)"

let test_reduce_free_var_with_named () =
  let ast = reduce_ok {|push(remote: origin)|} in
  Alcotest.(check string) "printed"
    {|App(Var("push"), [Named(remote: Ident("origin"))])|}
    (Printer.to_string ast)

let test_reduce_free_var_bare () =
  let ast = reduce_ok "a >>> b" in
  Alcotest.(check string) "printed"
    {|Seq(Var("a"), Var("b"))|}
    (Printer.to_string ast)

let test_check_mixed_args_no_error () =
  let _ = check_ok "let v = a >>> b in push(remote: origin, v)" in
  ()

let test_check_question_in_positional_arg () =
  let warnings = check_ok_with_warnings "push(remote: origin, inner?)" in
  Alcotest.(check int) "1 warning from isolated arg" 1 (List.length warnings)

let test_check_app_question_with_alt () =
  let _ = check_ok "check(strict: true)? >>> (pass ||| fail)" in
  ()

let test_integration_mixed_args () =
  let input = "let v = some_pipeline in push(remote: origin, v)" in
  let tokens = Lexer.tokenize input in
  let ast = Parser.parse_program tokens in
  let reduced = Reducer.reduce ast in
  let result = Checker.check reduced in
  Alcotest.(check int) "no warnings" 0 (List.length result.Checker.warnings)

let test_parse_in_as_named_arg () =
  let ast = parse_ok "pipe(in: source, out: dest)" in
  Alcotest.(check string) "printed"
    {|App(Var("pipe"), [Named(in: Ident("source")), Named(out: Ident("dest"))])|}
    (Printer.to_string ast)

let tests =
  [ "let and check", `Quick, test_integration_let_and_check
  ; "backward compat", `Quick, test_integration_backward_compat
  ]

let mixed_arg_tests =
  [ "mixed named and positional", `Quick, test_parse_mixed_args
  ; "positional then named", `Quick, test_parse_positional_then_named
  ; "multiple positional", `Quick, test_parse_multiple_positional
  ; "app question", `Quick, test_parse_app_question
  ; "var question", `Quick, test_parse_var_question
  ; "empty parens app", `Quick, test_parse_empty_parens_app
  ; "reduce mixed args", `Quick, test_reduce_mixed_args
  ; "named args on lambda error", `Quick, test_reduce_named_args_on_lambda_error
  ; "free var with named", `Quick, test_reduce_free_var_with_named
  ; "free var bare", `Quick, test_reduce_free_var_bare
  ; "check mixed args no error", `Quick, test_check_mixed_args_no_error
  ; "check question in positional arg", `Quick, test_check_question_in_positional_arg
  ; "check app question with alt", `Quick, test_check_app_question_with_alt
  ; "integration mixed args", `Quick, test_integration_mixed_args
  ; "in as named arg key", `Quick, test_parse_in_as_named_arg
  ]
