open Compose_dsl

let parse_ok input =
  let tokens = Lexer.tokenize input in
  Parser.parse tokens

let parse_fails input =
  match parse_ok input with
  | _ -> Alcotest.fail "expected parse error"
  | exception Parser.Parse_error _ -> ()

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

(* ident = ( letter | "_" ) , { letter | digit | "-" | "_" } *)
let test_lex_ident_with_digits () =
  let tokens = Lexer.tokenize "step2" in
  match (List.hd tokens).token with
  | Lexer.IDENT "step2" -> ()
  | _ -> Alcotest.fail "expected IDENT step2"

let test_lex_ident_with_hyphen () =
  let tokens = Lexer.tokenize "my-node" in
  match (List.hd tokens).token with
  | Lexer.IDENT "my-node" -> ()
  | _ -> Alcotest.fail "expected IDENT my-node"

let test_lex_ident_with_underscore () =
  let tokens = Lexer.tokenize "_private" in
  match (List.hd tokens).token with
  | Lexer.IDENT "_private" -> ()
  | _ -> Alcotest.fail "expected IDENT _private"

(* operator = ">>>" | "***" | "|||" *)
let test_lex_all_operators () =
  let tokens = Lexer.tokenize "a >>> b *** c ||| d" in
  let toks = List.map (fun (t : Lexer.located) -> t.token) tokens in
  Alcotest.(check int) "token count" 8 (List.length toks);
  Alcotest.(check bool) "has SEQ" true (List.nth toks 1 = Lexer.SEQ);
  Alcotest.(check bool) "has PAR" true (List.nth toks 3 = Lexer.PAR);
  Alcotest.(check bool) "has ALT" true (List.nth toks 5 = Lexer.ALT)

(* string = '"' , { any char - '"' } , '"' *)
let test_lex_string () =
  let tokens = Lexer.tokenize "a(x: \"hello world\")" in
  let has_string =
    List.exists
      (fun (t : Lexer.located) ->
        match t.token with Lexer.STRING "hello world" -> true | _ -> false)
      tokens
  in
  Alcotest.(check bool) "has string" true has_string

let test_lex_unterminated_string () =
  match Lexer.tokenize "a(\"hello)" with
  | _ -> Alcotest.fail "expected lex error"
  | exception Lexer.Lex_error (_, msg) ->
    Alcotest.(check string) "error msg" "unterminated string" msg

(* comment = "--" , { any char - newline } *)
let test_lex_comment () =
  let tokens = Lexer.tokenize "a -- hello world" in
  let comment =
    List.find_map
      (fun (t : Lexer.located) ->
        match t.token with Lexer.COMMENT s -> Some s | _ -> None)
      tokens
  in
  Alcotest.(check (option string)) "comment text" (Some "hello world") comment

(* loop keyword vs ident *)
let test_lex_loop_keyword () =
  let tokens = Lexer.tokenize "loop" in
  match (List.hd tokens).token with
  | Lexer.LOOP -> ()
  | _ -> Alcotest.fail "expected LOOP token"

let test_lex_unexpected_char () =
  match Lexer.tokenize "@" with
  | _ -> Alcotest.fail "expected lex error"
  | exception Lexer.Lex_error (_, msg) ->
    Alcotest.(check string) "error msg" "unexpected character '@'" msg

(* === Parser tests === *)

(* node = ident , [ "(" , [ args ] , ")" ] *)
let test_parse_node_with_args () =
  let ast = parse_ok "read(source: \"data.csv\")" in
  match ast with
  | Ast.Node n ->
    Alcotest.(check string) "name" "read" n.name;
    Alcotest.(check int) "1 arg" 1 (List.length n.args);
    Alcotest.(check string) "arg key" "source" (List.hd n.args).key
  | _ -> Alcotest.fail "expected Node"

let test_parse_node_no_parens () =
  let ast = parse_ok "count" in
  match ast with
  | Ast.Node n ->
    Alcotest.(check string) "name" "count" n.name;
    Alcotest.(check int) "0 args" 0 (List.length n.args)
  | _ -> Alcotest.fail "expected Node"

let test_parse_node_empty_parens () =
  let ast = parse_ok "noop()" in
  match ast with
  | Ast.Node n ->
    Alcotest.(check string) "name" "noop" n.name;
    Alcotest.(check int) "0 args" 0 (List.length n.args)
  | _ -> Alcotest.fail "expected Node"

(* args = arg , { "," , arg } *)
let test_parse_multiple_args () =
  let ast = parse_ok "load(from: cache, key: k, ttl: \"60\")" in
  match ast with
  | Ast.Node n ->
    Alcotest.(check int) "3 args" 3 (List.length n.args);
    Alcotest.(check string) "arg1" "from" (List.nth n.args 0).key;
    Alcotest.(check string) "arg2" "key" (List.nth n.args 1).key;
    Alcotest.(check string) "arg3" "ttl" (List.nth n.args 2).key
  | _ -> Alcotest.fail "expected Node"

(* value = string | ident | "[" , [ value , { "," , value } ] , "]" *)
let test_parse_string_value () =
  let ast = parse_ok "a(x: \"hello\")" in
  match ast with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.String "hello" -> ()
     | _ -> Alcotest.fail "expected String value")
  | _ -> Alcotest.fail "expected Node"

let test_parse_ident_value () =
  let ast = parse_ok "a(x: csv)" in
  match ast with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.Ident "csv" -> ()
     | _ -> Alcotest.fail "expected Ident value")
  | _ -> Alcotest.fail "expected Node"

let test_parse_list_value () =
  let ast = parse_ok "collect(fields: [name, email, age])" in
  match ast with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.List vs -> Alcotest.(check int) "3 items" 3 (List.length vs)
     | _ -> Alcotest.fail "expected List value")
  | _ -> Alcotest.fail "expected Node"

let test_parse_empty_list () =
  let ast = parse_ok "a(x: [])" in
  match ast with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.List vs -> Alcotest.(check int) "0 items" 0 (List.length vs)
     | _ -> Alcotest.fail "expected List value")
  | _ -> Alcotest.fail "expected Node"

let test_parse_single_item_list () =
  let ast = parse_ok "a(x: [one])" in
  match ast with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.List [ Ast.Ident "one" ] -> ()
     | _ -> Alcotest.fail "expected single-item List")
  | _ -> Alcotest.fail "expected Node"

(* expr = term , { operator , term } *)
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

let test_parse_mixed_operators () =
  let ast = parse_ok "a >>> b *** c ||| d" in
  match ast with
  | Ast.Alt (Ast.Par (Ast.Seq (Ast.Node _, Ast.Node _), Ast.Node _), Ast.Node _) -> ()
  | _ -> Alcotest.fail "expected left-associative mixed ops"

(* term = node | "loop" , "(" , expr , ")" | "(" , expr , ")" *)
let test_parse_group () =
  let ast = parse_ok "(a >>> b) *** c" in
  match ast with
  | Ast.Par (Ast.Group (Ast.Seq _), Ast.Node _) -> ()
  | _ -> Alcotest.fail "expected Par with grouped Seq"

let test_parse_nested_groups () =
  let ast = parse_ok "((a >>> b))" in
  match ast with
  | Ast.Group (Ast.Group (Ast.Seq _)) -> ()
  | _ -> Alcotest.fail "expected nested Group"

let test_parse_loop () =
  let ast = parse_ok "loop (a >>> evaluate(criteria: pass))" in
  match ast with
  | Ast.Loop (Ast.Seq _) -> ()
  | _ -> Alcotest.fail "expected Loop"

let test_parse_nested_loop () =
  let ast = parse_ok "loop (a >>> loop (b >>> check(x: y)) >>> evaluate(r: done))" in
  match ast with
  | Ast.Loop (Ast.Seq (Ast.Seq (Ast.Node _, Ast.Loop _), Ast.Node _)) -> ()
  | _ -> Alcotest.fail "expected nested Loop"

(* comment attachment *)
let test_parse_comments_attach_to_node () =
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

let test_parse_multiline_comments () =
  let ast =
    parse_ok
      {|read(source: "data.csv") -- read the source
                               -- ref: Read, cat|}
  in
  match ast with
  | Ast.Node n ->
    Alcotest.(check int) "2 comments" 2 (List.length n.comments)
  | _ -> Alcotest.fail "expected Node"

(* error cases *)
let test_parse_error_unclosed_paren () =
  match parse_ok "a(" with
  | _ -> Alcotest.fail "expected parse error"
  | exception Parser.Parse_error (_, msg) ->
    Alcotest.(check string) "error msg" "expected argument name or ')'" msg

let test_parse_error_unclosed_group () =
  parse_fails "(a >>> b"

let test_parse_error_missing_loop_paren () =
  parse_fails "loop a"

let test_parse_error_trailing_operator () =
  parse_fails "a >>>"

(* plan examples *)
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

(* === Checker tests === *)

let test_check_loop_no_eval () =
  let errors = check_fails "loop (a >>> b)" in
  let msg = (List.hd errors).message in
  Alcotest.(check bool) "mentions eval" true
    (String.length msg > 0)

let test_check_loop_with_evaluate () =
  let _ = check_ok "loop (a >>> evaluate(criteria: done))" in
  ()

let test_check_loop_with_verify () =
  let _ = check_ok "loop (a >>> verify(method: tests))" in
  ()

let test_check_loop_with_check () =
  let _ = check_ok "loop (a >>> check(result: ok))" in
  ()

let test_check_nested_loop_both_need_eval () =
  let errors = check_fails "loop (a >>> loop (b >>> c))" in
  Alcotest.(check int) "2 errors" 2 (List.length errors)

(* === Test suite === *)

let lexer_tests =
  [ "ident with digits", `Quick, test_lex_ident_with_digits
  ; "ident with hyphen", `Quick, test_lex_ident_with_hyphen
  ; "ident with underscore start", `Quick, test_lex_ident_with_underscore
  ; "all operators", `Quick, test_lex_all_operators
  ; "string", `Quick, test_lex_string
  ; "unterminated string", `Quick, test_lex_unterminated_string
  ; "comment", `Quick, test_lex_comment
  ; "loop keyword", `Quick, test_lex_loop_keyword
  ; "unexpected char", `Quick, test_lex_unexpected_char
  ]

let parser_tests =
  [ "node with args", `Quick, test_parse_node_with_args
  ; "node no parens", `Quick, test_parse_node_no_parens
  ; "node empty parens", `Quick, test_parse_node_empty_parens
  ; "multiple args", `Quick, test_parse_multiple_args
  ; "string value", `Quick, test_parse_string_value
  ; "ident value", `Quick, test_parse_ident_value
  ; "list value", `Quick, test_parse_list_value
  ; "empty list", `Quick, test_parse_empty_list
  ; "single item list", `Quick, test_parse_single_item_list
  ; "sequential", `Quick, test_parse_seq
  ; "parallel", `Quick, test_parse_par
  ; "alternative", `Quick, test_parse_alt
  ; "mixed operators", `Quick, test_parse_mixed_operators
  ; "group", `Quick, test_parse_group
  ; "nested groups", `Quick, test_parse_nested_groups
  ; "loop", `Quick, test_parse_loop
  ; "nested loop", `Quick, test_parse_nested_loop
  ; "comments attach to node", `Quick, test_parse_comments_attach_to_node
  ; "multiline comments", `Quick, test_parse_multiline_comments
  ; "error: unclosed paren", `Quick, test_parse_error_unclosed_paren
  ; "error: unclosed group", `Quick, test_parse_error_unclosed_group
  ; "error: missing loop paren", `Quick, test_parse_error_missing_loop_paren
  ; "error: trailing operator", `Quick, test_parse_error_trailing_operator
  ; "plan example 1", `Quick, test_parse_plan_example_1
  ; "plan example 2", `Quick, test_parse_plan_example_2
  ; "plan example 3", `Quick, test_parse_plan_example_3
  ]

let checker_tests =
  [ "loop no eval", `Quick, test_check_loop_no_eval
  ; "loop with evaluate", `Quick, test_check_loop_with_evaluate
  ; "loop with verify", `Quick, test_check_loop_with_verify
  ; "loop with check", `Quick, test_check_loop_with_check
  ; "nested loops both need eval", `Quick, test_check_nested_loop_both_need_eval
  ]

let () =
  Alcotest.run "compose-dsl"
    [ "Lexer", lexer_tests
    ; "Parser", parser_tests
    ; "Checker", checker_tests
    ]
