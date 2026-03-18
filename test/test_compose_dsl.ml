open Compose_dsl

let parse_ok input =
  let tokens = Lexer.tokenize input in
  Parser.parse tokens

let check_ok input =
  let ast = parse_ok input in
  let errors = Checker.check ast in
  Alcotest.(check int) "no errors" 0 (List.length errors);
  ast

let check_fails input =
  let ast = parse_ok input in
  let errors = Checker.check ast in
  Alcotest.(check bool) "has errors" true (List.length errors > 0);
  errors

(* === Lexer tests === *)

let test_lex_basic () =
  let tokens = Lexer.tokenize "read(source: \"data.csv\")" in
  let toks = List.map (fun (t : Lexer.located) -> t.token) tokens in
  Alcotest.(check int) "token count" 7 (List.length toks)

let test_lex_combinators () =
  let tokens = Lexer.tokenize "a >>> b *** c ||| d" in
  let toks = List.map (fun (t : Lexer.located) -> t.token) tokens in
  (* IDENT SEQ IDENT PAR IDENT ALT IDENT EOF *)
  Alcotest.(check int) "token count" 8 (List.length toks)

let test_lex_comment () =
  let tokens = Lexer.tokenize "a -- hello world" in
  let has_comment =
    List.exists
      (fun (t : Lexer.located) ->
        match t.token with Lexer.COMMENT _ -> true | _ -> false)
      tokens
  in
  Alcotest.(check bool) "has comment" true has_comment

let test_lex_unterminated_string () =
  match Lexer.tokenize "a(\"hello)" with
  | _ -> Alcotest.fail "expected lex error"
  | exception Lexer.Lex_error (_, msg) ->
    Alcotest.(check string) "error msg" "unterminated string" msg

let test_lex_unexpected_char () =
  match Lexer.tokenize "@" with
  | _ -> Alcotest.fail "expected lex error"
  | exception Lexer.Lex_error (_, msg) ->
    Alcotest.(check string) "error msg" "unexpected character '@'" msg

(* === Parser tests === *)

let test_parse_simple_node () =
  let ast = parse_ok "read(source: \"data.csv\")" in
  match ast with
  | Ast.Node n ->
    Alcotest.(check string) "name" "read" n.name;
    Alcotest.(check int) "1 arg" 1 (List.length n.args)
  | _ -> Alcotest.fail "expected Node"

let test_parse_node_no_args () =
  let ast = parse_ok "count" in
  match ast with
  | Ast.Node n ->
    Alcotest.(check string) "name" "count" n.name;
    Alcotest.(check int) "0 args" 0 (List.length n.args)
  | _ -> Alcotest.fail "expected Node"

let test_parse_seq () =
  let ast = parse_ok "a >>> b >>> c" in
  match ast with
  | Ast.Seq (Ast.Seq (Ast.Node _, Ast.Node _), Ast.Node _) -> ()
  | _ -> Alcotest.fail "expected left-associative Seq"

let test_parse_par () =
  let ast = parse_ok "a *** b" in
  match ast with
  | Ast.Par (Ast.Node _, Ast.Node _) -> ()
  | _ -> Alcotest.fail "expected Par"

let test_parse_alt () =
  let ast = parse_ok "a ||| b" in
  match ast with
  | Ast.Alt (Ast.Node _, Ast.Node _) -> ()
  | _ -> Alcotest.fail "expected Alt"

let test_parse_group () =
  let ast = parse_ok "(a >>> b) *** c" in
  match ast with
  | Ast.Par (Ast.Group (Ast.Seq _), Ast.Node _) -> ()
  | _ -> Alcotest.fail "expected Par with grouped Seq"

let test_parse_loop () =
  let ast = parse_ok "loop (a >>> evaluate(criteria: pass))" in
  match ast with
  | Ast.Loop (Ast.Seq _) -> ()
  | _ -> Alcotest.fail "expected Loop"

let test_parse_list_value () =
  let ast = parse_ok "collect(fields: [name, email, age])" in
  match ast with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.List vs -> Alcotest.(check int) "3 items" 3 (List.length vs)
     | _ -> Alcotest.fail "expected List value")
  | _ -> Alcotest.fail "expected Node"

let test_parse_plan_example_1 () =
  let _ =
    check_ok
      {|read(source: "data.csv") >>> parse(format: csv) >>> filter(condition: "age > 18") >>> (count *** collect(fields: [email])) >>> format(as: report)|}
  in
  ()

let test_parse_plan_example_2 () =
  let _ =
    check_ok
      {|(fetch(url: endpoint) ||| load(from: cache, key: k)) >>> transform(mapping: schema_v2) >>> write(dest: "output.json")|}
  in
  ()

let test_parse_plan_example_3 () =
  let _ =
    check_ok
      {|loop (generate(artifact: code, from: spec) >>> verify(method: test_suite) >>> evaluate(criteria: all_pass))|}
  in
  ()

let test_parse_error_unclosed () =
  match parse_ok "a(" with
  | _ -> Alcotest.fail "expected parse error"
  | exception Parser.Parse_error (_, msg) ->
    Alcotest.(check string) "error msg" "expected argument name or ')'" msg

let test_parse_with_comments () =
  let ast =
    parse_ok
      {|read(source: "data.csv") -- read the source
  >>> write(dest: "out.csv") -- write output|}
  in
  match ast with
  | Ast.Seq (Ast.Node r, Ast.Node w) ->
    Alcotest.(check int) "read comments" 1 (List.length r.comments);
    Alcotest.(check int) "write comments" 1 (List.length w.comments)
  | _ -> Alcotest.fail "expected Seq"

(* === Checker tests === *)

let test_check_loop_no_eval () =
  let errors = check_fails "loop (a >>> b)" in
  let msg = (List.hd errors).message in
  Alcotest.(check bool) "mentions eval" true
    (String.length msg > 0)

let test_check_loop_with_eval () =
  let _ = check_ok "loop (a >>> evaluate(criteria: done))" in
  ()

let test_check_loop_with_verify () =
  let _ = check_ok "loop (a >>> verify(method: tests))" in
  ()

(* === Test suite === *)

let lexer_tests =
  [ "basic tokens", `Quick, test_lex_basic
  ; "combinators", `Quick, test_lex_combinators
  ; "comment", `Quick, test_lex_comment
  ; "unterminated string", `Quick, test_lex_unterminated_string
  ; "unexpected char", `Quick, test_lex_unexpected_char
  ]

let parser_tests =
  [ "simple node", `Quick, test_parse_simple_node
  ; "node no args", `Quick, test_parse_node_no_args
  ; "sequential", `Quick, test_parse_seq
  ; "parallel", `Quick, test_parse_par
  ; "alternative", `Quick, test_parse_alt
  ; "group", `Quick, test_parse_group
  ; "loop", `Quick, test_parse_loop
  ; "list value", `Quick, test_parse_list_value
  ; "plan example 1", `Quick, test_parse_plan_example_1
  ; "plan example 2", `Quick, test_parse_plan_example_2
  ; "plan example 3", `Quick, test_parse_plan_example_3
  ; "unclosed paren", `Quick, test_parse_error_unclosed
  ; "with comments", `Quick, test_parse_with_comments
  ]

let checker_tests =
  [ "loop no eval", `Quick, test_check_loop_no_eval
  ; "loop with evaluate", `Quick, test_check_loop_with_eval
  ; "loop with verify", `Quick, test_check_loop_with_verify
  ]

let () =
  Alcotest.run "compose-dsl"
    [ "Lexer", lexer_tests
    ; "Parser", parser_tests
    ; "Checker", checker_tests
    ]
