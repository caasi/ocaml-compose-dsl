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

let test_lex_fanout_operator () =
  let tokens = Lexer.tokenize "a &&& b" in
  let toks = List.map (fun (t : Lexer.located) -> t.token) tokens in
  Alcotest.(check int) "token count" 4 (List.length toks);
  Alcotest.(check bool) "has FANOUT" true (List.nth toks 1 = Lexer.FANOUT)

let test_lex_partial_ampersand () =
  match Lexer.tokenize "a & b" with
  | _ -> Alcotest.fail "expected lex error"
  | exception Lexer.Lex_error (_, msg) ->
    Alcotest.(check string) "error msg" "unexpected character '&'" msg

let test_lex_double_ampersand () =
  match Lexer.tokenize "a && b" with
  | _ -> Alcotest.fail "expected lex error"
  | exception Lexer.Lex_error (_, msg) ->
    Alcotest.(check string) "error msg" "unexpected character '&'" msg

let test_lex_integer () =
  let tokens = Lexer.tokenize "42" in
  match (List.hd tokens).token with
  | Lexer.NUMBER "42" -> ()
  | _ -> Alcotest.fail "expected NUMBER 42"

let test_lex_float () =
  let tokens = Lexer.tokenize "3.14" in
  match (List.hd tokens).token with
  | Lexer.NUMBER "3.14" -> ()
  | _ -> Alcotest.fail "expected NUMBER 3.14"

let test_lex_negative_integer () =
  let tokens = Lexer.tokenize "a(x: -5)" in
  let has_neg =
    List.exists
      (fun (t : Lexer.located) ->
        match t.token with Lexer.NUMBER "-5" -> true | _ -> false)
      tokens
  in
  Alcotest.(check bool) "has NUMBER -5" true has_neg

let test_lex_negative_float () =
  let tokens = Lexer.tokenize "a(x: -0.5)" in
  let has_neg =
    List.exists
      (fun (t : Lexer.located) ->
        match t.token with Lexer.NUMBER "-0.5" -> true | _ -> false)
      tokens
  in
  Alcotest.(check bool) "has NUMBER -0.5" true has_neg

let test_lex_negative_is_not_comment () =
  let tokens = Lexer.tokenize "a(x: -3)" in
  let has_comment =
    List.exists
      (fun (t : Lexer.located) ->
        match t.token with Lexer.COMMENT _ -> true | _ -> false)
      tokens
  in
  Alcotest.(check bool) "no comment" false has_comment

let test_lex_trailing_dot () =
  match Lexer.tokenize "a(x: 3.)" with
  | _ -> Alcotest.fail "expected lex error"
  | exception Lexer.Lex_error (_, msg) ->
    Alcotest.(check string) "error msg" "expected digit after '.'" msg

let test_lex_leading_dot () =
  match Lexer.tokenize "a(x: .5)" with
  | _ -> Alcotest.fail "expected lex error"
  | exception Lexer.Lex_error (_, msg) ->
    Alcotest.(check string) "error msg" "unexpected character '.'" msg

let test_lex_unit_suffix () =
  let tokens = Lexer.tokenize "100mg" in
  match (List.hd tokens).token with
  | Lexer.NUMBER "100mg" -> ()
  | _ -> Alcotest.fail "expected NUMBER 100mg"

let test_lex_float_unit_suffix () =
  let tokens = Lexer.tokenize "2.5cm" in
  match (List.hd tokens).token with
  | Lexer.NUMBER "2.5cm" -> ()
  | _ -> Alcotest.fail "expected NUMBER 2.5cm"

let test_lex_negative_unit_suffix () =
  let tokens = Lexer.tokenize "a(x: -10dB)" in
  let has_neg =
    List.exists
      (fun (t : Lexer.located) ->
        match t.token with Lexer.NUMBER "-10dB" -> true | _ -> false)
      tokens
  in
  Alcotest.(check bool) "has NUMBER -10dB" true has_neg

let test_lex_number_before_delimiter () =
  let tokens = Lexer.tokenize "a(x: 42)" in
  let toks = List.map (fun (t : Lexer.located) -> t.token) tokens in
  Alcotest.(check bool) "NUMBER then RPAREN"
    true
    (List.nth toks 4 = Lexer.NUMBER "42"
     && List.nth toks 5 = Lexer.RPAREN)

let test_lex_reserved_hash () =
  match Lexer.tokenize "#invalid" with
  | _ -> Alcotest.fail "expected lex error"
  | exception Lexer.Lex_error (_, msg) ->
    Alcotest.(check string) "error msg" "unexpected character '#'" msg

let test_lex_unicode_unit_suffix () =
  let tokens = Lexer.tokenize "500ミリ秒" in
  match (List.hd tokens).token with
  | Lexer.NUMBER "500ミリ秒" -> ()
  | _ -> Alcotest.fail "expected NUMBER 500ミリ秒"

let test_lex_unit_suffix_with_digit () =
  let tokens = Lexer.tokenize "100m2" in
  match (List.hd tokens).token with
  | Lexer.NUMBER "100m2" -> ()
  | _ -> Alcotest.fail "expected NUMBER 100m2"

let test_lex_unicode_cjk_ident () =
  let tokens = Lexer.tokenize "翻譯" in
  match (List.hd tokens).token with
  | Lexer.IDENT "翻譯" -> ()
  | _ -> Alcotest.fail "expected IDENT 翻譯"

let test_lex_unicode_greek_ident () =
  let tokens = Lexer.tokenize "α" in
  match (List.hd tokens).token with
  | Lexer.IDENT "α" -> ()
  | _ -> Alcotest.fail "expected IDENT α"

let test_lex_unicode_accented_ident () =
  let tokens = Lexer.tokenize "café" in
  match (List.hd tokens).token with
  | Lexer.IDENT "café" -> ()
  | _ -> Alcotest.fail "expected IDENT café"

let test_lex_unicode_mixed_ident () =
  let tokens = Lexer.tokenize "a_名前-test" in
  match (List.hd tokens).token with
  | Lexer.IDENT "a_名前-test" -> ()
  | _ -> Alcotest.fail "expected IDENT a_名前-test"

let test_lex_unicode_ident_col () =
  let tokens = Lexer.tokenize "翻譯 >>> b" in
  let tok0 = List.nth tokens 0 in (* 翻譯 *)
  let tok1 = List.nth tokens 1 in (* >>> *)
  let tok2 = List.nth tokens 2 in (* b *)
  Alcotest.(check int) "翻譯 col" 1 tok0.pos.col;
  Alcotest.(check int) ">>> col" 4 tok1.pos.col;
  Alcotest.(check int) "b col" 8 tok2.pos.col

let test_lex_mixed_unicode_col () =
  let tokens = Lexer.tokenize "a翻譯b >>> c" in
  let tok0 = List.nth tokens 0 in (* a翻譯b *)
  let tok1 = List.nth tokens 1 in (* >>> *)
  Alcotest.(check string) "ident" "a翻譯b" (match tok0.token with Lexer.IDENT s -> s | _ -> "");
  Alcotest.(check int) "ident col" 1 tok0.pos.col;
  Alcotest.(check int) ">>> col" 6 tok1.pos.col

let test_lex_unicode_string_col () =
  let tokens = Lexer.tokenize {|"翻譯" >>> b|} in
  let tok0 = List.nth tokens 0 in (* "翻譯" *)
  let tok1 = List.nth tokens 1 in (* >>> *)
  let tok2 = List.nth tokens 2 in (* b *)
  Alcotest.(check int) "string col" 1 tok0.pos.col;
  Alcotest.(check int) ">>> col" 6 tok1.pos.col;
  Alcotest.(check int) "b col" 10 tok2.pos.col

let test_lex_multiline_unicode_col () =
  let tokens = Lexer.tokenize "翻譯\nb" in
  let tok0 = List.nth tokens 0 in (* 翻譯 *)
  let tok1 = List.nth tokens 1 in (* b *)
  Alcotest.(check int) "翻譯 line" 1 tok0.pos.line;
  Alcotest.(check int) "翻譯 col" 1 tok0.pos.col;
  Alcotest.(check int) "b line" 2 tok1.pos.line;
  Alcotest.(check int) "b col" 1 tok1.pos.col

let test_lex_malformed_utf8 () =
  match Lexer.tokenize "\xff\xfe" with
  | _ -> Alcotest.fail "expected Lex_error"
  | exception Lexer.Lex_error (_, msg) ->
    Alcotest.(check string) "error msg" "invalid UTF-8 byte sequence" msg

let test_lex_error_col_after_unicode () =
  match Lexer.tokenize "翻譯 @" with
  | _ -> Alcotest.fail "expected Lex_error"
  | exception Lexer.Lex_error (pos, _) ->
    Alcotest.(check int) "error col" 4 pos.col

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

let test_parse_number_value () =
  let ast = parse_ok "resize(width: 1920)" in
  match ast with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.Number "1920" -> ()
     | _ -> Alcotest.fail "expected Number value")
  | _ -> Alcotest.fail "expected Node"

let test_parse_float_value () =
  let ast = parse_ok "delay(seconds: 3.5)" in
  match ast with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.Number "3.5" -> ()
     | _ -> Alcotest.fail "expected Number value")
  | _ -> Alcotest.fail "expected Node"

let test_parse_negative_value () =
  let ast = parse_ok "adjust(offset: -10)" in
  match ast with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.Number "-10" -> ()
     | _ -> Alcotest.fail "expected Number value")
  | _ -> Alcotest.fail "expected Node"

let test_parse_number_in_list () =
  let ast = parse_ok "a(dims: [1920, 1080])" in
  match ast with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.List [Ast.Number "1920"; Ast.Number "1080"] -> ()
     | _ -> Alcotest.fail "expected List of Numbers")
  | _ -> Alcotest.fail "expected Node"

let test_parse_number_with_unit () =
  let ast = parse_ok "dose(amount: 100mg)" in
  match ast with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.Number "100mg" -> ()
     | _ -> Alcotest.fail "expected Number with unit")
  | _ -> Alcotest.fail "expected Node"

let test_parse_number_as_node_name () =
  parse_fails "42(x: 1)"

(* expr = term , { operator , term } *)
let test_parse_seq () =
  let ast = parse_ok "a >>> b >>> c" in
  match ast with
  | Ast.Seq (Ast.Node _, Ast.Seq (Ast.Node _, Ast.Node _)) -> ()
  | _ -> Alcotest.fail "expected right-associative Seq"

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
  (* a >>> b *** c ||| d = a >>> ((b *** c) ||| d) *)
  let ast = parse_ok "a >>> b *** c ||| d" in
  match ast with
  | Ast.Seq (Ast.Node _, Ast.Alt (Ast.Par (Ast.Node _, Ast.Node _), Ast.Node _)) -> ()
  | _ -> Alcotest.fail "expected precedence: >>> < ||| < ***"

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
  | Ast.Loop (Ast.Seq (Ast.Node _, Ast.Seq (Ast.Loop _, Ast.Node _))) -> ()
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

let test_parse_comment_on_group () =
  let ast =
    parse_ok {|(a >>> b) -- comment on group
  >>> c|}
  in
  match ast with
  | Ast.Seq (Ast.Group (Ast.Seq (Ast.Node _, Ast.Node b)), Ast.Node _) ->
    Alcotest.(check int) "comment attached to rightmost node in group" 1 (List.length b.comments);
    Alcotest.(check string) "comment text" "comment on group" (List.hd b.comments)
  | _ -> Alcotest.fail "expected Seq(Group(Seq(a,b)),c)"

let test_parse_comment_on_loop () =
  let ast =
    parse_ok {|loop (a >>> evaluate(x: y)) -- loop comment
  >>> done|}
  in
  match ast with
  | Ast.Seq (Ast.Loop (Ast.Seq (Ast.Node _, Ast.Node e)), Ast.Node _) ->
    Alcotest.(check int) "comment attached to rightmost node in loop" 1 (List.length e.comments);
    Alcotest.(check string) "comment text" "loop comment" (List.hd e.comments)
  | _ -> Alcotest.fail "expected Seq(Loop(...), done)"

let test_parse_fanout () =
  let ast = parse_ok "a &&& b" in
  match ast with
  | Ast.Fanout (Ast.Node _, Ast.Node _) -> ()
  | _ -> Alcotest.fail "expected Fanout"

let test_parse_precedence_seq_fanout () =
  (* a >>> b &&& c >>> d  =  a >>> ((b &&& c) >>> d)  right-assoc *)
  let ast = parse_ok "a >>> b &&& c >>> d" in
  match ast with
  | Ast.Seq (Ast.Node _, Ast.Seq (Ast.Fanout (Ast.Node _, Ast.Node _), Ast.Node _)) -> ()
  | _ -> Alcotest.fail "expected Seq(a, Seq(Fanout(b,c), d))"

let test_parse_precedence_alt_par () =
  (* a ||| b *** c  =  a ||| (b *** c)  precedence *)
  let ast = parse_ok "a ||| b *** c" in
  match ast with
  | Ast.Alt (Ast.Node _, Ast.Par (Ast.Node _, Ast.Node _)) -> ()
  | _ -> Alcotest.fail "expected Alt(a, Par(b,c))"

let test_parse_par_fanout_same_prec () =
  (* a *** b &&& c  =  a *** (b &&& c)  right-assoc, same precedence *)
  let ast = parse_ok "a *** b &&& c" in
  match ast with
  | Ast.Par (Ast.Node _, Ast.Fanout (Ast.Node _, Ast.Node _)) -> ()
  | _ -> Alcotest.fail "expected Par(a, Fanout(b,c))"

let test_parse_mixed_all_precedence () =
  let ast = parse_ok "a >>> b ||| c &&& d *** e" in
  match ast with
  | Ast.Seq (Ast.Node _,
      Ast.Alt (Ast.Node _,
        Ast.Fanout (Ast.Node _,
          Ast.Par (Ast.Node _, Ast.Node _)))) -> ()
  | _ -> Alcotest.fail "expected Seq(a, Alt(b, Fanout(c, Par(d, e))))"

let test_parse_group_overrides_precedence () =
  let ast = parse_ok "(a >>> b) &&& c" in
  match ast with
  | Ast.Fanout (Ast.Group (Ast.Seq (Ast.Node _, Ast.Node _)), Ast.Node _) -> ()
  | _ -> Alcotest.fail "expected Fanout(Group(Seq(a,b)), c)"

let test_parse_unicode_node_with_args () =
  let ast = parse_ok {|翻譯(來源: "日文")|} in
  match ast with
  | Ast.Node n ->
    Alcotest.(check string) "name" "翻譯" n.name;
    Alcotest.(check int) "1 arg" 1 (List.length n.args);
    Alcotest.(check string) "arg key" "來源" (List.hd n.args).key;
    (match (List.hd n.args).value with
     | Ast.String "日文" -> ()
     | _ -> Alcotest.fail "expected String value")
  | _ -> Alcotest.fail "expected Node"

let test_parse_unicode_seq () =
  let ast = parse_ok "café >>> naïve" in
  match ast with
  | Ast.Seq (Ast.Node a, Ast.Node b) ->
    Alcotest.(check string) "lhs" "café" a.name;
    Alcotest.(check string) "rhs" "naïve" b.name
  | _ -> Alcotest.fail "expected Seq"

let test_parse_greek_seq () =
  let ast = parse_ok "α >>> β" in
  match ast with
  | Ast.Seq (Ast.Node a, Ast.Node b) ->
    Alcotest.(check string) "lhs" "α" a.name;
    Alcotest.(check string) "rhs" "β" b.name
  | _ -> Alcotest.fail "expected Seq"

let test_parse_unicode_unit_value () =
  let ast = parse_ok "wait(duration: 500ミリ秒)" in
  match ast with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.Number "500ミリ秒" -> ()
     | _ -> Alcotest.fail "expected Number with unicode unit")
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

let test_check_loop_with_fanout_and_eval () =
  let _ = check_ok "loop (a &&& evaluate(criteria: done))" in
  ()

let test_check_loop_with_test () =
  let _ = check_ok "loop (a >>> test)" in
  ()

let test_check_loop_with_checking () =
  let _ = check_ok "loop (a >>> checking)" in
  ()

(* === Printer tests === *)

let test_print_simple_node () =
  let ast = parse_ok "a" in
  let s = Printer.to_string ast in
  Alcotest.(check string) "simple node" {|Node("a", [], [])|} s

let test_print_node_with_args () =
  let ast = parse_ok {|read(source: "data.csv")|} in
  let s = Printer.to_string ast in
  Alcotest.(check string) "node with args"
    {|Node("read", [source: String("data.csv")], [])|} s

let test_print_node_with_list_arg () =
  let ast = parse_ok "collect(fields: [name, email])" in
  let s = Printer.to_string ast in
  Alcotest.(check string) "node with list"
    {|Node("collect", [fields: List([Ident("name"), Ident("email")])], [])|} s

let test_print_seq () =
  let ast = parse_ok "a >>> b" in
  let s = Printer.to_string ast in
  Alcotest.(check string) "seq"
    {|Seq(Node("a", [], []), Node("b", [], []))|} s

let test_print_fanout () =
  let ast = parse_ok "a &&& b" in
  let s = Printer.to_string ast in
  Alcotest.(check string) "fanout"
    {|Fanout(Node("a", [], []), Node("b", [], []))|} s

let test_print_loop () =
  let ast = parse_ok "loop (a >>> evaluate(x: y))" in
  let s = Printer.to_string ast in
  Alcotest.(check string) "loop"
    {|Loop(Seq(Node("a", [], []), Node("evaluate", [x: Ident("y")], [])))|} s

let test_print_group () =
  let ast = parse_ok "(a >>> b) *** c" in
  let s = Printer.to_string ast in
  Alcotest.(check string) "group"
    {|Par(Group(Seq(Node("a", [], []), Node("b", [], []))), Node("c", [], []))|} s

let test_print_number_arg () =
  let ast = parse_ok "resize(width: 1920, height: 1080)" in
  let s = Printer.to_string ast in
  Alcotest.(check string) "number args"
    {|Node("resize", [width: Number(1920), height: Number(1080)], [])|} s

let test_print_negative_number () =
  let ast = parse_ok "adjust(offset: -3.14)" in
  let s = Printer.to_string ast in
  Alcotest.(check string) "negative number"
    {|Node("adjust", [offset: Number(-3.14)], [])|} s

let test_print_number_with_unit () =
  let ast = parse_ok "dose(amount: 100mg)" in
  let s = Printer.to_string ast in
  Alcotest.(check string) "number with unit"
    {|Node("dose", [amount: Number(100mg)], [])|} s

let test_print_comment () =
  let ast = parse_ok "a -- this is a comment" in
  let s = Printer.to_string ast in
  Alcotest.(check string) "comment"
    {|Node("a", [], ["this is a comment"])|} s

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
  ; "fanout operator", `Quick, test_lex_fanout_operator
  ; "partial ampersand", `Quick, test_lex_partial_ampersand
  ; "double ampersand", `Quick, test_lex_double_ampersand
  ; "integer literal", `Quick, test_lex_integer
  ; "float literal", `Quick, test_lex_float
  ; "negative integer", `Quick, test_lex_negative_integer
  ; "negative float", `Quick, test_lex_negative_float
  ; "negative is not comment", `Quick, test_lex_negative_is_not_comment
  ; "trailing dot invalid", `Quick, test_lex_trailing_dot
  ; "leading dot invalid", `Quick, test_lex_leading_dot
  ; "unit suffix", `Quick, test_lex_unit_suffix
  ; "float unit suffix", `Quick, test_lex_float_unit_suffix
  ; "negative unit suffix", `Quick, test_lex_negative_unit_suffix
  ; "number before delimiter", `Quick, test_lex_number_before_delimiter
  ; "reserved hash", `Quick, test_lex_reserved_hash
  ; "unicode unit suffix", `Quick, test_lex_unicode_unit_suffix
  ; "unit suffix with digit", `Quick, test_lex_unit_suffix_with_digit
  ; "unicode CJK ident", `Quick, test_lex_unicode_cjk_ident
  ; "unicode Greek ident", `Quick, test_lex_unicode_greek_ident
  ; "unicode accented ident", `Quick, test_lex_unicode_accented_ident
  ; "unicode mixed ident", `Quick, test_lex_unicode_mixed_ident
  ; "unicode ident col", `Quick, test_lex_unicode_ident_col
  ; "mixed unicode col", `Quick, test_lex_mixed_unicode_col
  ; "unicode string col", `Quick, test_lex_unicode_string_col
  ; "multiline unicode col", `Quick, test_lex_multiline_unicode_col
  ; "malformed UTF-8", `Quick, test_lex_malformed_utf8
  ; "error col after unicode", `Quick, test_lex_error_col_after_unicode
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
  ; "number value", `Quick, test_parse_number_value
  ; "float value", `Quick, test_parse_float_value
  ; "negative value", `Quick, test_parse_negative_value
  ; "number in list", `Quick, test_parse_number_in_list
  ; "number with unit", `Quick, test_parse_number_with_unit
  ; "error: number as node name", `Quick, test_parse_number_as_node_name
  ; "sequential", `Quick, test_parse_seq
  ; "parallel", `Quick, test_parse_par
  ; "alternative", `Quick, test_parse_alt
  ; "mixed operators", `Quick, test_parse_mixed_operators
  ; "fanout", `Quick, test_parse_fanout
  ; "precedence: seq vs fanout", `Quick, test_parse_precedence_seq_fanout
  ; "precedence: alt vs par", `Quick, test_parse_precedence_alt_par
  ; "par and fanout same prec", `Quick, test_parse_par_fanout_same_prec
  ; "mixed all precedence", `Quick, test_parse_mixed_all_precedence
  ; "group overrides precedence", `Quick, test_parse_group_overrides_precedence
  ; "group", `Quick, test_parse_group
  ; "nested groups", `Quick, test_parse_nested_groups
  ; "loop", `Quick, test_parse_loop
  ; "nested loop", `Quick, test_parse_nested_loop
  ; "comments attach to node", `Quick, test_parse_comments_attach_to_node
  ; "multiline comments", `Quick, test_parse_multiline_comments
  ; "comment on group expr", `Quick, test_parse_comment_on_group
  ; "comment on loop expr", `Quick, test_parse_comment_on_loop
  ; "unicode node with args", `Quick, test_parse_unicode_node_with_args
  ; "unicode seq", `Quick, test_parse_unicode_seq
  ; "Greek letter seq", `Quick, test_parse_greek_seq
  ; "unicode unit in arg value", `Quick, test_parse_unicode_unit_value
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
  ; "loop with fanout and eval", `Quick, test_check_loop_with_fanout_and_eval
  ; "loop with test (4-char name)", `Quick, test_check_loop_with_test
  ; "loop with checking (check prefix)", `Quick, test_check_loop_with_checking
  ]

let printer_tests =
  [ "simple node", `Quick, test_print_simple_node
  ; "node with args", `Quick, test_print_node_with_args
  ; "node with list arg", `Quick, test_print_node_with_list_arg
  ; "seq", `Quick, test_print_seq
  ; "fanout", `Quick, test_print_fanout
  ; "loop", `Quick, test_print_loop
  ; "group", `Quick, test_print_group
  ; "number arg", `Quick, test_print_number_arg
  ; "negative number", `Quick, test_print_negative_number
  ; "number with unit", `Quick, test_print_number_with_unit
  ; "comment", `Quick, test_print_comment
  ]

let () =
  Alcotest.run "compose-dsl"
    [ "Lexer", lexer_tests
    ; "Parser", parser_tests
    ; "Checker", checker_tests
    ; "Printer", printer_tests
    ]
