open Compose_dsl

let parse_ok input =
  let tokens = Lexer.tokenize input in
  Parser.parse_program tokens

let desc_of input = (parse_ok input).desc

let parse_fails input =
  match parse_ok input with
  | _ -> Alcotest.fail "expected parse error"
  | exception Parser.Parse_error _ -> ()

let check_ok input =
  let ast = parse_ok input in
  let ast = Reducer.reduce ast in
  let _result = Checker.check ast in
  ast

let check_ok_with_warnings input =
  let ast = parse_ok input in
  let ast = Reducer.reduce ast in
  let result = Checker.check ast in
  result.Checker.warnings

let has_warning_containing substr warnings =
  List.exists (fun (w : Checker.warning) ->
    let len = String.length substr in
    let rec scan i =
      if i + len > String.length w.message then false
      else if String.sub w.message i len = substr then true
      else scan (i + 1)
    in
    scan 0
  ) warnings

let contains s sub =
  let len = String.length sub in
  let rec scan i = i + len <= String.length s && (String.sub s i len = sub || scan (i + 1)) in
  scan 0

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
  match tokens with
  | tok0 :: tok1 :: tok2 :: _ ->
    (match tok0.token with
     | Lexer.IDENT "翻譯" -> ()
     | _ -> Alcotest.fail "expected IDENT 翻譯");
    (match tok1.token with
     | Lexer.SEQ -> ()
     | _ -> Alcotest.fail "expected SEQ");
    (match tok2.token with
     | Lexer.IDENT "b" -> ()
     | _ -> Alcotest.fail "expected IDENT b");
    Alcotest.(check int) "翻譯 col" 1 tok0.loc.start.col;
    Alcotest.(check int) ">>> col" 4 tok1.loc.start.col;
    Alcotest.(check int) "b col" 8 tok2.loc.start.col
  | _ -> Alcotest.fail "expected at least 3 tokens"

let test_lex_mixed_unicode_col () =
  let tokens = Lexer.tokenize "a翻譯b >>> c" in
  match tokens with
  | tok0 :: tok1 :: _ ->
    (match tok0.token with
     | Lexer.IDENT s -> Alcotest.(check string) "ident" "a翻譯b" s
     | _ -> Alcotest.fail "expected IDENT a翻譯b");
    (match tok1.token with
     | Lexer.SEQ -> ()
     | _ -> Alcotest.fail "expected SEQ");
    Alcotest.(check int) "ident col" 1 tok0.loc.start.col;
    Alcotest.(check int) ">>> col" 6 tok1.loc.start.col
  | _ -> Alcotest.fail "expected at least 2 tokens"

let test_lex_unicode_string_col () =
  let tokens = Lexer.tokenize {|"翻譯" >>> b|} in
  match tokens with
  | tok0 :: tok1 :: tok2 :: _ ->
    (match tok0.token with
     | Lexer.STRING "翻譯" -> ()
     | _ -> Alcotest.fail "expected STRING 翻譯");
    (match tok1.token with
     | Lexer.SEQ -> ()
     | _ -> Alcotest.fail "expected SEQ");
    (match tok2.token with
     | Lexer.IDENT "b" -> ()
     | _ -> Alcotest.fail "expected IDENT b");
    Alcotest.(check int) "string col" 1 tok0.loc.start.col;
    Alcotest.(check int) ">>> col" 6 tok1.loc.start.col;
    Alcotest.(check int) "b col" 10 tok2.loc.start.col
  | _ -> Alcotest.fail "expected at least 3 tokens"

let test_lex_multiline_unicode_col () =
  let tokens = Lexer.tokenize "翻譯\nb" in
  match tokens with
  | tok0 :: tok1 :: _ ->
    Alcotest.(check int) "翻譯 line" 1 tok0.loc.start.line;
    Alcotest.(check int) "翻譯 col" 1 tok0.loc.start.col;
    Alcotest.(check int) "b line" 2 tok1.loc.start.line;
    Alcotest.(check int) "b col" 1 tok1.loc.start.col
  | _ -> Alcotest.fail "expected at least 2 tokens"

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

(* question operator *)
let test_lex_question () =
  let tokens = Lexer.tokenize "a?" in
  let toks = List.map (fun (t : Lexer.located) -> t.token) tokens in
  Alcotest.(check int) "token count" 3 (List.length toks);
  Alcotest.(check bool) "IDENT" true (List.nth toks 0 = Lexer.IDENT "a");
  Alcotest.(check bool) "QUESTION" true (List.nth toks 1 = Lexer.QUESTION);
  Alcotest.(check bool) "EOF" true (List.nth toks 2 = Lexer.EOF)

let test_lex_question_with_space () =
  let tokens = Lexer.tokenize "a ?" in
  let toks = List.map (fun (t : Lexer.located) -> t.token) tokens in
  Alcotest.(check int) "token count" 3 (List.length toks);
  Alcotest.(check bool) "QUESTION" true (List.nth toks 1 = Lexer.QUESTION)

let test_lex_question_after_string () =
  let tokens = Lexer.tokenize {|"hello"?|} in
  let toks = List.map (fun (t : Lexer.located) -> t.token) tokens in
  Alcotest.(check int) "token count" 3 (List.length toks);
  Alcotest.(check bool) "STRING" true (List.nth toks 0 = Lexer.STRING "hello");
  Alcotest.(check bool) "QUESTION" true (List.nth toks 1 = Lexer.QUESTION)

(* === Parser tests === *)

let test_parse_node_with_args () =
  match desc_of "read(source: \"data.csv\")" with
  | Ast.App ({ desc = Ast.Var "read"; _ }, [Named { key = "source"; value = String "data.csv" }]) -> ()
  | _ -> Alcotest.fail "expected App(Var read, [Named source])"

let test_parse_node_no_parens () =
  match desc_of "count" with
  | Ast.Var "count" -> ()
  | _ -> Alcotest.fail "expected Var count"

let test_parse_node_empty_parens () =
  match desc_of "noop()" with
  | Ast.App ({ desc = Ast.Var "noop"; _ }, []) -> ()
  | _ -> Alcotest.fail "expected App(Var noop, [])"

(* args = arg , { "," , arg } *)
let test_parse_multiple_args () =
  match desc_of "load(from: cache, key: k, ttl: \"60\")" with
  | Ast.App ({ desc = Ast.Var "load"; _ }, args) ->
    Alcotest.(check int) "3 args" 3 (List.length args);
    (match args with
     | [Named { key = "from"; _ }; Named { key = "key"; _ }; Named { key = "ttl"; _ }] -> ()
     | _ -> Alcotest.fail "expected 3 Named args")
  | _ -> Alcotest.fail "expected App"

(* value = string | ident | "[" , [ value , { "," , value } ] , "]" *)
let test_parse_string_value () =
  match desc_of "a(x: \"hello\")" with
  | Ast.App ({ desc = Ast.Var "a"; _ }, [Named { value = String "hello"; _ }]) -> ()
  | _ -> Alcotest.fail "expected App with String value"

let test_parse_ident_value () =
  match desc_of "a(x: csv)" with
  | Ast.App ({ desc = Ast.Var "a"; _ }, [Named { value = Ident "csv"; _ }]) -> ()
  | _ -> Alcotest.fail "expected App with Ident value"

let test_parse_list_value () =
  match desc_of "collect(fields: [name, email, age])" with
  | Ast.App ({ desc = Ast.Var "collect"; _ }, [Named { value = List vs; _ }]) ->
    Alcotest.(check int) "3 items" 3 (List.length vs)
  | _ -> Alcotest.fail "expected App with List value"

let test_parse_empty_list () =
  match desc_of "a(x: [])" with
  | Ast.App ({ desc = Ast.Var "a"; _ }, [Named { value = List vs; _ }]) ->
    Alcotest.(check int) "0 items" 0 (List.length vs)
  | _ -> Alcotest.fail "expected App with List value"

let test_parse_single_item_list () =
  match desc_of "a(x: [one])" with
  | Ast.App ({ desc = Ast.Var "a"; _ }, [Named { value = List [ Ident "one" ]; _ }]) -> ()
  | _ -> Alcotest.fail "expected single-item List"

let test_parse_number_value () =
  match desc_of "resize(width: 1920)" with
  | Ast.App ({ desc = Ast.Var "resize"; _ }, [Named { value = Number "1920"; _ }]) -> ()
  | _ -> Alcotest.fail "expected Number value"

let test_parse_float_value () =
  match desc_of "delay(seconds: 3.5)" with
  | Ast.App ({ desc = Ast.Var "delay"; _ }, [Named { value = Number "3.5"; _ }]) -> ()
  | _ -> Alcotest.fail "expected Number value"

let test_parse_negative_value () =
  match desc_of "adjust(offset: -10)" with
  | Ast.App ({ desc = Ast.Var "adjust"; _ }, [Named { value = Number "-10"; _ }]) -> ()
  | _ -> Alcotest.fail "expected Number value"

let test_parse_number_in_list () =
  match desc_of "a(dims: [1920, 1080])" with
  | Ast.App ({ desc = Ast.Var "a"; _ }, [Named { value = List [Number "1920"; Number "1080"]; _ }]) -> ()
  | _ -> Alcotest.fail "expected List of Numbers"

let test_parse_number_with_unit () =
  match desc_of "dose(amount: 100mg)" with
  | Ast.App ({ desc = Ast.Var "dose"; _ }, [Named { value = Number "100mg"; _ }]) -> ()
  | _ -> Alcotest.fail "expected Number with unit"

let test_parse_number_as_node_name () =
  parse_fails "42(x: 1)"

(* expr = term , { operator , term } *)
let test_parse_seq () =
  match desc_of "a >>> b >>> c" with
  | Ast.Seq ({ desc = Ast.Var _; _ }, { desc = Ast.Seq ({ desc = Ast.Var _; _ }, { desc = Ast.Var _; _ }); _ }) -> ()
  | _ -> Alcotest.fail "expected right-associative Seq"

let test_parse_par () =
  match desc_of "a *** b" with
  | Ast.Par ({ desc = Ast.Var _; _ }, { desc = Ast.Var _; _ }) -> ()
  | _ -> Alcotest.fail "expected Par"

let test_parse_alt () =
  match desc_of "a ||| b" with
  | Ast.Alt ({ desc = Ast.Var _; _ }, { desc = Ast.Var _; _ }) -> ()
  | _ -> Alcotest.fail "expected Alt"

let test_parse_mixed_operators () =
  match desc_of "a >>> b *** c ||| d" with
  | Ast.Seq ({ desc = Ast.Var _; _ }, { desc = Ast.Alt ({ desc = Ast.Par ({ desc = Ast.Var _; _ }, { desc = Ast.Var _; _ }); _ }, { desc = Ast.Var _; _ }); _ }) -> ()
  | _ -> Alcotest.fail "expected precedence: >>> < ||| < ***"

(* term = node | "loop" , "(" , expr , ")" | "(" , expr , ")" *)
let test_parse_group () =
  match desc_of "(a >>> b) *** c" with
  | Ast.Par ({ desc = Ast.Group { desc = Ast.Seq _; _ }; _ }, { desc = Ast.Var _; _ }) -> ()
  | _ -> Alcotest.fail "expected Par with grouped Seq"

let test_parse_nested_groups () =
  match desc_of "((a >>> b))" with
  | Ast.Group { desc = Ast.Group { desc = Ast.Seq _; _ }; _ } -> ()
  | _ -> Alcotest.fail "expected nested Group"

let test_parse_loop () =
  match desc_of "loop (a >>> evaluate(criteria: pass))" with
  | Ast.Loop { desc = Ast.Seq _; _ } -> ()
  | _ -> Alcotest.fail "expected Loop"

let test_parse_nested_loop () =
  match desc_of "loop (a >>> loop (b >>> check(x: y)) >>> evaluate(r: done))" with
  | Ast.Loop { desc = Ast.Seq ({ desc = Ast.Var _; _ }, { desc = Ast.Seq ({ desc = Ast.Loop _; _ }, { desc = Ast.App _; _ }); _ }); _ } -> ()
  | _ -> Alcotest.fail "expected nested Loop"

(* comment attachment — comments are now dropped on Var/App *)
let test_parse_comments_attach_to_node () =
  let ast =
    parse_ok
      {|read(source: "data.csv") -- read the source
  >>> write(dest: "out.csv") -- write output|}
  in
  match ast.desc with
  | Ast.Seq ({ desc = Ast.App _; _ }, { desc = Ast.App _; _ }) -> ()
  | _ -> Alcotest.fail "expected Seq(App, App)"

let test_parse_multiline_comments () =
  let ast =
    parse_ok
      {|read(source: "data.csv") -- read the source
                               -- ref: Read, cat|}
  in
  match ast.desc with
  | Ast.App ({ desc = Ast.Var "read"; _ }, _) -> ()
  | _ -> Alcotest.fail "expected App"

let test_parse_comment_on_group () =
  let ast =
    parse_ok {|(a >>> b) -- comment on group
  >>> c|}
  in
  match ast.desc with
  | Ast.Seq ({ desc = Ast.Group { desc = Ast.Seq _; _ }; _ }, { desc = Ast.Var _; _ }) -> ()
  | _ -> Alcotest.fail "expected Seq(Group(Seq(a,b)),c)"

let test_parse_comment_on_loop () =
  let ast =
    parse_ok {|loop (a >>> evaluate(x: y)) -- loop comment
  >>> done|}
  in
  match ast.desc with
  | Ast.Seq ({ desc = Ast.Loop _; _ }, { desc = Ast.Var _; _ }) -> ()
  | _ -> Alcotest.fail "expected Seq(Loop(...), done)"

let test_parse_fanout () =
  match desc_of "a &&& b" with
  | Ast.Fanout ({ desc = Ast.Var _; _ }, { desc = Ast.Var _; _ }) -> ()
  | _ -> Alcotest.fail "expected Fanout"

let test_parse_precedence_seq_fanout () =
  match desc_of "a >>> b &&& c >>> d" with
  | Ast.Seq ({ desc = Ast.Var _; _ }, { desc = Ast.Seq ({ desc = Ast.Fanout ({ desc = Ast.Var _; _ }, { desc = Ast.Var _; _ }); _ }, { desc = Ast.Var _; _ }); _ }) -> ()
  | _ -> Alcotest.fail "expected Seq(a, Seq(Fanout(b,c), d))"

let test_parse_precedence_alt_par () =
  match desc_of "a ||| b *** c" with
  | Ast.Alt ({ desc = Ast.Var _; _ }, { desc = Ast.Par ({ desc = Ast.Var _; _ }, { desc = Ast.Var _; _ }); _ }) -> ()
  | _ -> Alcotest.fail "expected Alt(a, Par(b,c))"

let test_parse_par_fanout_same_prec () =
  match desc_of "a *** b &&& c" with
  | Ast.Par ({ desc = Ast.Var _; _ }, { desc = Ast.Fanout ({ desc = Ast.Var _; _ }, { desc = Ast.Var _; _ }); _ }) -> ()
  | _ -> Alcotest.fail "expected Par(a, Fanout(b,c))"

let test_parse_mixed_all_precedence () =
  match desc_of "a >>> b ||| c &&& d *** e" with
  | Ast.Seq ({ desc = Ast.Var _; _ },
      { desc = Ast.Alt ({ desc = Ast.Var _; _ },
        { desc = Ast.Fanout ({ desc = Ast.Var _; _ },
          { desc = Ast.Par ({ desc = Ast.Var _; _ }, { desc = Ast.Var _; _ }); _ }); _ }); _ }) -> ()
  | _ -> Alcotest.fail "expected Seq(a, Alt(b, Fanout(c, Par(d, e))))"

let test_parse_group_overrides_precedence () =
  match desc_of "(a >>> b) &&& c" with
  | Ast.Fanout ({ desc = Ast.Group { desc = Ast.Seq ({ desc = Ast.Var _; _ }, { desc = Ast.Var _; _ }); _ }; _ }, { desc = Ast.Var _; _ }) -> ()
  | _ -> Alcotest.fail "expected Fanout(Group(Seq(a,b)), c)"

let test_parse_unicode_node_with_args () =
  match desc_of {|翻譯(來源: "日文")|} with
  | Ast.App ({ desc = Ast.Var "翻譯"; _ }, [Named { key = "來源"; value = String "日文" }]) -> ()
  | _ -> Alcotest.fail "expected App(Var 翻譯, [Named 來源])"

let test_parse_unicode_seq () =
  match desc_of "café >>> naïve" with
  | Ast.Seq ({ desc = Ast.Var "café"; _ }, { desc = Ast.Var "naïve"; _ }) -> ()
  | _ -> Alcotest.fail "expected Seq"

let test_parse_greek_seq () =
  match desc_of "α >>> β" with
  | Ast.Seq ({ desc = Ast.Var "α"; _ }, { desc = Ast.Var "β"; _ }) -> ()
  | _ -> Alcotest.fail "expected Seq"

let test_parse_unicode_unit_value () =
  match desc_of "wait(duration: 500ミリ秒)" with
  | Ast.App ({ desc = Ast.Var "wait"; _ }, [Named { value = Number "500ミリ秒"; _ }]) -> ()
  | _ -> Alcotest.fail "expected App with Number unicode unit"

(* error cases *)
let test_parse_error_unclosed_paren () =
  match parse_ok "a(" with
  | _ -> Alcotest.fail "expected parse error"
  | exception Parser.Parse_error (_, msg) ->
    if not (contains msg ")") then
      Alcotest.fail ("expected error mentioning ')': " ^ msg)

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


let test_check_question_with_alt () =
  let warnings = check_ok_with_warnings {|"ready"? >>> (go ||| stop)|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)

let test_check_question_without_alt () =
  let warnings = check_ok_with_warnings {|"ready"? >>> process >>> done|} in
  Alcotest.(check int) "one warning" 1 (List.length warnings);
  Alcotest.(check bool) "warning message" true
    (String.length (List.hd warnings).Checker.message > 0)

let test_check_question_with_intermediate_steps () =
  let warnings = check_ok_with_warnings {|"ok"? >>> log >>> transform >>> (yes ||| no)|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)

let test_check_question_alt_in_par_no_match () =
  let warnings = check_ok_with_warnings {|"ready"? >>> a *** (b ||| c)|} in
  Alcotest.(check int) "one warning" 1 (List.length warnings)

let test_check_question_in_loop () =
  let warnings = check_ok_with_warnings {|loop("pass"? >>> (exit ||| eval))|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)

let test_check_question_in_loop_no_alt () =
  let warnings = check_ok_with_warnings {|loop("pass"? >>> eval)|} in
  Alcotest.(check int) "one warning" 1 (List.length warnings)

let test_check_multiple_questions () =
  let warnings = check_ok_with_warnings {|"a"? >>> (x ||| y) >>> "b"? >>> (p ||| q)|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)

let test_check_multiple_questions_unmatched () =
  let warnings = check_ok_with_warnings {|"a"? >>> "b"? >>> (x ||| y)|} in
  Alcotest.(check int) "one warning (one unmatched)" 1 (List.length warnings)

let test_check_existing_alt_no_warning () =
  let warnings = check_ok_with_warnings {|a ||| b|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)

let test_check_question_in_group_with_alt () =
  let warnings = check_ok_with_warnings {|("ready"?) >>> (a ||| b)|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)

let test_check_question_in_fanout_branch () =
  let warnings = check_ok_with_warnings {|("ready"? >>> (a ||| b)) &&& c|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)

let test_check_question_in_fanout_branch_no_alt () =
  let warnings = check_ok_with_warnings {|("ready"? >>> process) &&& c|} in
  Alcotest.(check int) "one warning" 1 (List.length warnings)

let test_check_alt_before_question_still_warns () =
  (* ||| before ? should NOT cancel it — only downstream ||| matches *)
  let warnings = check_ok_with_warnings {|(a ||| b) >>> "ready"? >>> process|} in
  Alcotest.(check int) "one warning" 1 (List.length warnings)

let test_check_question_tail_as_alt_operand () =
  let warnings = check_ok_with_warnings {|(a >>> b >>> c?) ||| d|} in
  Alcotest.(check int) "one warning" 1 (List.length warnings);
  Alcotest.(check bool) "specific message" true
    (has_warning_containing "operand of '|||'" warnings)

let test_check_question_direct_alt_operand () =
  let warnings = check_ok_with_warnings {|c? ||| d|} in
  Alcotest.(check int) "one warning" 1 (List.length warnings);
  Alcotest.(check bool) "specific message" true
    (has_warning_containing "operand of '|||'" warnings)

let test_check_question_multiple_with_tail_alt_operand () =
  let warnings = check_ok_with_warnings {|("a"? >>> "b"?) ||| c|} in
  Alcotest.(check int) "two warnings" 2 (List.length warnings);
  Alcotest.(check bool) "has specific" true
    (has_warning_containing "operand of '|||'" warnings);
  Alcotest.(check bool) "has generic" true
    (has_warning_containing "without matching" warnings)

let test_check_question_not_at_tail_alt_operand () =
  let warnings = check_ok_with_warnings {|("ready"? >>> process) ||| fallback|} in
  Alcotest.(check int) "one warning" 1 (List.length warnings);
  Alcotest.(check bool) "generic message" true
    (has_warning_containing "without matching" warnings);
  Alcotest.(check bool) "not specific message" false
    (has_warning_containing "operand of '|||'" warnings)


let test_check_loop_plain_no_error () =
  let result = Checker.check (parse_ok "loop (a >>> b)") in
  Alcotest.(check int) "no warnings" 0 (List.length result.Checker.warnings)

let test_check_loop_unicode_no_error () =
  let result = Checker.check (parse_ok "loop (掃描 >>> 檢查)") in
  Alcotest.(check int) "no warnings" 0 (List.length result.Checker.warnings)

let test_parse_comment_on_node_question () =
  (* Comments are now dropped on Var, so just verify the structure *)
  let ast = parse_ok "validate -- important\n? >>> (a ||| b)" in
  match ast.desc with
  | Ast.Seq ({ desc = Ast.Question { desc = Ast.Var "validate"; _ }; _ }, _) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "unexpected AST: %s" (Printer.to_string ast))

let test_parse_comment_on_string_question () =
  let ast = parse_ok {|"hello" -- note
? >>> (a ||| b)|} in
  match ast.desc with
  | Ast.Seq ({ desc = Ast.Question { desc = Ast.StringLit "hello"; _ }; _ }, _) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "unexpected AST: %s" (Printer.to_string ast))

(* === Printer tests === *)

let test_print_simple_node () =
  let ast = parse_ok "a" in
  let s = Printer.to_string ast in
  Alcotest.(check string) "simple node" {|Var("a")|} s

let test_print_node_with_args () =
  let ast = parse_ok {|read(source: "data.csv")|} in
  let s = Printer.to_string ast in
  Alcotest.(check string) "node with args"
    {|App(Var("read"), [Named(source: String("data.csv"))])|} s

let test_print_node_with_list_arg () =
  let ast = parse_ok "collect(fields: [name, email])" in
  let s = Printer.to_string ast in
  Alcotest.(check string) "node with list"
    {|App(Var("collect"), [Named(fields: List([Ident("name"), Ident("email")]))])|} s

let test_print_seq () =
  let ast = parse_ok "a >>> b" in
  let s = Printer.to_string ast in
  Alcotest.(check string) "seq"
    {|Seq(Var("a"), Var("b"))|} s

let test_print_fanout () =
  let ast = parse_ok "a &&& b" in
  let s = Printer.to_string ast in
  Alcotest.(check string) "fanout"
    {|Fanout(Var("a"), Var("b"))|} s

let test_print_loop () =
  let ast = parse_ok "loop (a >>> evaluate(x: y))" in
  let s = Printer.to_string ast in
  Alcotest.(check string) "loop"
    {|Loop(Seq(Var("a"), App(Var("evaluate"), [Named(x: Ident("y"))])))|} s

let test_print_group () =
  let ast = parse_ok "(a >>> b) *** c" in
  let s = Printer.to_string ast in
  Alcotest.(check string) "group"
    {|Par(Group(Seq(Var("a"), Var("b"))), Var("c"))|} s

let test_print_number_arg () =
  let ast = parse_ok "resize(width: 1920, height: 1080)" in
  let s = Printer.to_string ast in
  Alcotest.(check string) "number args"
    {|App(Var("resize"), [Named(width: Number(1920)), Named(height: Number(1080))])|} s

let test_print_negative_number () =
  let ast = parse_ok "adjust(offset: -3.14)" in
  let s = Printer.to_string ast in
  Alcotest.(check string) "negative number"
    {|App(Var("adjust"), [Named(offset: Number(-3.14))])|} s

let test_print_number_with_unit () =
  let ast = parse_ok "dose(amount: 100mg)" in
  let s = Printer.to_string ast in
  Alcotest.(check string) "number with unit"
    {|App(Var("dose"), [Named(amount: Number(100mg))])|} s

let test_print_comment () =
  (* Comments are now dropped on Var *)
  let ast = parse_ok "a -- this is a comment" in
  let s = Printer.to_string ast in
  Alcotest.(check string) "comment dropped"
    {|Var("a")|} s

let test_print_question_string () =
  let ast = parse_ok {|"earth is not flat"? >>> (believe ||| doubt)|} in
  let s = Printer.to_string ast in
  Alcotest.(check string) "question string" {|Seq(Question(StringLit("earth is not flat")), Group(Alt(Var("believe"), Var("doubt"))))|} s

let test_print_question_node () =
  let ast = parse_ok "validate(method: test_suite)? >>> (deploy ||| rollback)" in
  let s = Printer.to_string ast in
  Alcotest.(check string) "question node" {|Seq(Question(App(Var("validate"), [Named(method: Ident("test_suite"))])), Group(Alt(Var("deploy"), Var("rollback"))))|} s

let test_print_string_lit () =
  let ast = parse_ok {|"hello" >>> a|} in
  let s = Printer.to_string ast in
  Alcotest.(check string) "string lit"
    {|Seq(StringLit("hello"), Var("a"))|}
    s

(* === Question operator parser tests === *)

let test_parse_string_question () =
  let ast = parse_ok {|"earth is not flat"? >>> (believe ||| doubt)|} in
  match ast.desc with
  | Ast.Seq ({ desc = Ast.Question { desc = Ast.StringLit "earth is not flat"; _ }; _ }, { desc = Ast.Group { desc = Ast.Alt ({ desc = Ast.Var _; _ }, { desc = Ast.Var _; _ }); _ }; _ }) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "unexpected AST: %s" (Printer.to_string ast))

let test_parse_node_question () =
  let ast = parse_ok "validate(method: test_suite)? >>> (deploy ||| rollback)" in
  match ast.desc with
  | Ast.Seq ({ desc = Ast.Question { desc = Ast.App ({ desc = Ast.Var "validate"; _ }, _); _ }; _ }, { desc = Ast.Group { desc = Ast.Alt _; _ }; _ }) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "unexpected AST: %s" (Printer.to_string ast))

let test_parse_bare_node_question () =
  match desc_of "check? >>> (yes ||| no)" with
  | Ast.Seq ({ desc = Ast.Question { desc = Ast.Var "check"; _ }; _ }, _) -> ()
  | _ -> Alcotest.fail "expected Question(Var check)"

let test_parse_question_with_space () =
  let ast = parse_ok {|"hello" ? >>> (a ||| b)|} in
  match ast.desc with
  | Ast.Seq ({ desc = Ast.Question { desc = Ast.StringLit "hello"; _ }; _ }, _) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "unexpected AST: %s" (Printer.to_string ast))

let test_parse_question_in_loop () =
  let ast = parse_ok {|loop(generate >>> "all pass"? >>> (exit ||| continue))|} in
  match ast.desc with
  | Ast.Loop { desc = Ast.Seq (_, { desc = Ast.Seq ({ desc = Ast.Question { desc = Ast.StringLit "all pass"; _ }; _ }, { desc = Ast.Group { desc = Ast.Alt _; _ }; _ }); _ }); _ } -> ()
  | _ -> Alcotest.fail (Printf.sprintf "unexpected AST: %s" (Printer.to_string ast))

let test_parse_question_in_group () =
  let ast = parse_ok {|("is valid"?) >>> (accept ||| reject)|} in
  match ast.desc with
  | Ast.Seq ({ desc = Ast.Group { desc = Ast.Question { desc = Ast.StringLit "is valid"; _ }; _ }; _ }, _) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "unexpected AST: %s" (Printer.to_string ast))

(* === Checker loc tests === *)


let test_check_question_warning_loc () =
  let warnings = check_ok_with_warnings {|"ready"? >>> process >>> done|} in
  let w = List.hd warnings in
  Alcotest.(check int) "warning start line" 1 w.loc.start.line;
  Alcotest.(check int) "warning start col" 1 w.loc.start.col

let test_check_string_lit_no_error () =
  let _ = check_ok {|"hello" >>> a|} in
  ()

let test_check_string_lit_question_with_alt () =
  let warnings = check_ok_with_warnings {|"is valid"? >>> (yes ||| no)|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)


(* === Parser loc span tests === *)

let test_parse_node_loc () =
  let ast = parse_ok "abc" in
  Alcotest.(check int) "start line" 1 ast.loc.start.line;
  Alcotest.(check int) "start col" 1 ast.loc.start.col;
  Alcotest.(check int) "end col" 4 ast.loc.end_.col

let test_parse_seq_loc () =
  let ast = parse_ok "a >>> b" in
  Alcotest.(check int) "start col" 1 ast.loc.start.col;
  Alcotest.(check int) "end col" 8 ast.loc.end_.col

let test_parse_group_loc () =
  let ast = parse_ok "(a >>> b)" in
  Alcotest.(check int) "start col" 1 ast.loc.start.col;
  Alcotest.(check int) "end col" 10 ast.loc.end_.col

let test_parse_loop_loc () =
  let ast = parse_ok "loop(a >>> eval)" in
  Alcotest.(check int) "start col" 1 ast.loc.start.col;
  Alcotest.(check int) "end col" 17 ast.loc.end_.col

let test_parse_multiline_loc () =
  let ast = parse_ok "a >>>\nb" in
  Alcotest.(check int) "start line" 1 ast.loc.start.line;
  Alcotest.(check int) "end line" 2 ast.loc.end_.line;
  Alcotest.(check int) "end col" 2 ast.loc.end_.col

let test_parse_question_loc () =
  let ast = parse_ok {|"ok"?|} in
  Alcotest.(check int) "start col" 1 ast.loc.start.col;
  Alcotest.(check int) "end col" 6 ast.loc.end_.col

let test_parse_node_with_args_loc () =
  let ast = parse_ok "a(x: y)" in
  Alcotest.(check int) "start col" 1 ast.loc.start.col;
  Alcotest.(check int) "end col" 8 ast.loc.end_.col

let test_parse_unicode_node_loc () =
  let ast = parse_ok "翻譯" in
  Alcotest.(check int) "start col" 1 ast.loc.start.col;
  Alcotest.(check int) "end col (codepoints)" 3 ast.loc.end_.col

(* === Lexer loc span tests === *)

let test_lex_ident_loc_span () =
  let tokens = Lexer.tokenize "abc" in
  let t = List.hd tokens in
  Alcotest.(check int) "start col" 1 t.loc.start.col;
  Alcotest.(check int) "end col" 4 t.loc.end_.col

let test_lex_operator_loc_span () =
  let tokens = Lexer.tokenize "a >>> b" in
  let seq_tok = List.nth tokens 1 in
  Alcotest.(check int) ">>> start col" 3 seq_tok.loc.start.col;
  Alcotest.(check int) ">>> end col" 6 seq_tok.loc.end_.col

let test_lex_string_loc_span () =
  let tokens = Lexer.tokenize {|"hello"|} in
  let t = List.hd tokens in
  Alcotest.(check int) "start col" 1 t.loc.start.col;
  Alcotest.(check int) "end col" 8 t.loc.end_.col

let test_lex_question_loc_span () =
  let tokens = Lexer.tokenize "a?" in
  let q_tok = List.nth tokens 1 in
  Alcotest.(check int) "? start col" 2 q_tok.loc.start.col;
  Alcotest.(check int) "? end col" 3 q_tok.loc.end_.col

let test_lex_eof_loc_span () =
  let tokens = Lexer.tokenize "a" in
  let eof_tok = List.nth tokens 1 in
  (match eof_tok.token with
   | Lexer.EOF ->
     Alcotest.(check int) "eof start = end" eof_tok.loc.start.col eof_tok.loc.end_.col
   | _ -> Alcotest.fail "expected EOF")

let test_lex_unicode_ident_loc_span () =
  let tokens = Lexer.tokenize "翻譯" in
  let t = List.hd tokens in
  Alcotest.(check int) "start col" 1 t.loc.start.col;
  Alcotest.(check int) "end col (codepoints)" 3 t.loc.end_.col

let test_lex_double_colon () =
  let tokens = Lexer.tokenize "a :: B" in
  match tokens with
  | [ { token = IDENT "a"; _ }; { token = DOUBLE_COLON; _ }; { token = IDENT "B"; _ }; { token = EOF; _ } ] -> ()
  | _ -> Alcotest.fail "expected IDENT DOUBLE_COLON IDENT"

let test_lex_arrow () =
  let tokens = Lexer.tokenize "A -> B" in
  match tokens with
  | [ { token = IDENT "A"; _ }; { token = ARROW; _ }; { token = IDENT "B"; _ }; { token = EOF; _ } ] -> ()
  | _ -> Alcotest.fail "expected IDENT ARROW IDENT"

let test_lex_type_annotation () =
  let tokens = Lexer.tokenize "node :: Input -> Output" in
  match tokens with
  | [ { token = IDENT "node"; _ }; { token = DOUBLE_COLON; _ }; { token = IDENT "Input"; _ }; { token = ARROW; _ }; { token = IDENT "Output"; _ }; { token = EOF; _ } ] -> ()
  | _ -> Alcotest.fail "expected full type annotation token sequence"

let test_lex_colon_still_works () =
  let tokens = Lexer.tokenize "key: value" in
  match tokens with
  | [ { token = IDENT "key"; _ }; { token = COLON; _ }; { token = IDENT "value"; _ }; { token = EOF; _ } ] -> ()
  | _ -> Alcotest.fail "single colon should still produce COLON"

let test_lex_arrow_not_negative () =
  let tokens = Lexer.tokenize "-3 -> B" in
  match tokens with
  | [ { token = NUMBER "-3"; _ }; { token = ARROW; _ }; { token = IDENT "B"; _ }; { token = EOF; _ } ] -> ()
  | _ -> Alcotest.fail "-> after number should be ARROW"

let test_lex_arrow_no_whitespace () =
  let tokens = Lexer.tokenize "A->B" in
  match tokens with
  | [ { token = IDENT "A"; _ }; { token = ARROW; _ }; { token = IDENT "B"; _ }; { token = EOF; _ } ] -> ()
  | _ -> Alcotest.fail "-> without whitespace should tokenize correctly"

let test_lex_arrow_no_whitespace_in_type_ann () =
  let tokens = Lexer.tokenize "node::A->B" in
  match tokens with
  | [ { token = IDENT "node"; _ }; { token = DOUBLE_COLON; _ }; { token = IDENT "A"; _ }; { token = ARROW; _ }; { token = IDENT "B"; _ }; { token = EOF; _ } ] -> ()
  | _ -> Alcotest.fail "type annotation without whitespace should tokenize correctly"

let test_parse_type_ann_no_whitespace () =
  let ast = parse_ok "node::A->B" in
  Alcotest.(check (option (pair string string))) "type_ann"
    (Some ("A", "B"))
    (Option.map (fun (t : Ast.type_ann) -> (t.input, t.output)) ast.type_ann)

let test_lex_ident_with_hyphen_before_arrow () =
  let tokens = Lexer.tokenize "my-node->B" in
  match tokens with
  | [ { token = IDENT "my-node"; _ }; { token = ARROW; _ }; { token = IDENT "B"; _ }; { token = EOF; _ } ] -> ()
  | _ -> Alcotest.fail "hyphenated ident before -> should not consume the arrow"

let test_parse_type_ann_bare_node () =
  let ast = parse_ok "node :: A -> B" in
  Alcotest.(check (option (pair string string))) "type_ann"
    (Some ("A", "B"))
    (Option.map (fun (t : Ast.type_ann) -> (t.input, t.output)) ast.type_ann)

let test_parse_type_ann_node_with_args () =
  let ast = parse_ok "fetch(url: \"x\") :: URL -> HTML" in
  Alcotest.(check (option (pair string string))) "type_ann"
    (Some ("URL", "HTML"))
    (Option.map (fun (t : Ast.type_ann) -> (t.input, t.output)) ast.type_ann)

let test_parse_type_ann_optional () =
  let ast = parse_ok "node" in
  Alcotest.(check bool) "no type_ann" true (ast.type_ann = None)

let test_parse_type_ann_in_seq () =
  let ast = parse_ok "a :: X -> Y >>> b :: Y -> Z" in
  match ast.desc with
  | Ast.Seq (a, b) ->
    Alcotest.(check (option (pair string string))) "lhs type"
      (Some ("X", "Y"))
      (Option.map (fun (t : Ast.type_ann) -> (t.input, t.output)) a.type_ann);
    Alcotest.(check (option (pair string string))) "rhs type"
      (Some ("Y", "Z"))
      (Option.map (fun (t : Ast.type_ann) -> (t.input, t.output)) b.type_ann)
  | _ -> Alcotest.fail "expected Seq"

let test_parse_type_ann_mixed () =
  let ast = parse_ok "a :: X -> Y >>> b >>> c :: Y -> Z" in
  match ast.desc with
  | Ast.Seq (a, Ast.{ desc = Seq (b, c); _ }) ->
    Alcotest.(check bool) "a has type" true (a.type_ann <> None);
    Alcotest.(check bool) "b has no type" true (b.type_ann = None);
    Alcotest.(check bool) "c has type" true (c.type_ann <> None)
  | _ -> Alcotest.fail "expected Seq(a, Seq(b, c))"

let test_parse_type_ann_on_group () =
  let ast = parse_ok "(a >>> b) :: X -> Y" in
  Alcotest.(check (option (pair string string))) "group type_ann"
    (Some ("X", "Y"))
    (Option.map (fun (t : Ast.type_ann) -> (t.input, t.output)) ast.type_ann)

let test_parse_type_ann_on_loop () =
  let ast = parse_ok "loop(body) :: A -> B" in
  Alcotest.(check (option (pair string string))) "loop type_ann"
    (Some ("A", "B"))
    (Option.map (fun (t : Ast.type_ann) -> (t.input, t.output)) ast.type_ann)

let test_parse_type_ann_on_question () =
  let ast = parse_ok "\"ok\"? :: A -> Result" in
  Alcotest.(check (option (pair string string))) "question type_ann"
    (Some ("A", "Result"))
    (Option.map (fun (t : Ast.type_ann) -> (t.input, t.output)) ast.type_ann)

let test_parse_type_ann_unicode () =
  let ast = parse_ok "処理 :: 入力 -> 出力" in
  Alcotest.(check (option (pair string string))) "unicode type_ann"
    (Some ("入力", "出力"))
    (Option.map (fun (t : Ast.type_ann) -> (t.input, t.output)) ast.type_ann)

let test_parse_type_ann_with_comment () =
  let ast = parse_ok "node :: A -> B -- some comment" in
  Alcotest.(check (option (pair string string))) "type_ann"
    (Some ("A", "B"))
    (Option.map (fun (t : Ast.type_ann) -> (t.input, t.output)) ast.type_ann)

let test_parse_type_ann_loc () =
  let ast = parse_ok "node :: A -> B" in
  Alcotest.(check int) "start col" 1 ast.loc.start.col;
  Alcotest.(check int) "end col" 15 ast.loc.end_.col

let test_parse_type_ann_loc_no_ann () =
  let ast = parse_ok "node" in
  Alcotest.(check int) "start col" 1 ast.loc.start.col;
  Alcotest.(check int) "end col" 5 ast.loc.end_.col

let test_parse_type_ann_incomplete_error () =
  (match parse_ok "node :: A" with
   | _ -> Alcotest.fail "expected parse error"
   | exception Parser.Parse_error (_, msg) ->
     Alcotest.(check bool) "error mentions ->" true (contains msg "->"))

let test_parse_type_ann_missing_output_error () =
  (match parse_ok "node :: A ->" with
   | _ -> Alcotest.fail "expected parse error"
   | exception Parser.Parse_error (_, msg) ->
     Alcotest.(check bool) "error mentions ->" true (contains msg "->"))

(* Helper that parses with parse_program and reduces *)
let reduce_ok input =
  let tokens = Lexer.tokenize input in
  let ast = Parser.parse_program tokens in
  Reducer.reduce ast

let reduce_fails input =
  match reduce_ok input with
  | _ -> Alcotest.fail "expected reduce error"
  | exception Reducer.Reduce_error _ -> ()

let test_parse_string_lit () =
  match desc_of {|"hello" >>> a|} with
  | Ast.Seq ({ desc = Ast.StringLit "hello"; _ }, { desc = Ast.Var "a"; _ }) -> ()
  | _ -> Alcotest.fail "expected Seq(StringLit, Var)"

let test_parse_string_lit_as_positional_arg () =
  let ast = reduce_ok ({|let f = \x -> x >>> a|} ^ "\n" ^ {|f("hello")|}) in
  Alcotest.(check string) "printed"
    {|Seq(StringLit("hello"), Var("a"))|}
    (Printer.to_string ast)

let test_parse_string_lit_alone () =
  match desc_of {|"just a string"|} with
  | Ast.StringLit "just a string" -> ()
  | _ -> Alcotest.fail "expected StringLit"

let test_parse_string_lit_in_par () =
  match desc_of {|"left" *** "right"|} with
  | Ast.Par ({ desc = Ast.StringLit "left"; _ }, { desc = Ast.StringLit "right"; _ }) -> ()
  | _ -> Alcotest.fail "expected Par(StringLit, StringLit)"

let test_reduce_no_lambda () =
  let ast = reduce_ok "a >>> b" in
  Alcotest.(check string) "printed"
    {|Seq(Var("a"), Var("b"))|}
    (Printer.to_string ast)

let test_reduce_let_simple () =
  let ast = reduce_ok "let f = a >>> b\nf" in
  Alcotest.(check string) "printed"
    {|Seq(Var("a"), Var("b"))|}
    (Printer.to_string ast)

let test_reduce_lambda_apply () =
  let ast = reduce_ok "let f = \\ x -> x >>> a\nf(b)" in
  Alcotest.(check string) "printed"
    {|Seq(Var("b"), Var("a"))|}
    (Printer.to_string ast)

let test_reduce_lambda_multi_param () =
  let ast = reduce_ok "let f = \\ x, y -> x >>> y\nf(a, b)" in
  Alcotest.(check string) "printed"
    {|Seq(Var("a"), Var("b"))|}
    (Printer.to_string ast)

let test_reduce_let_chain () =
  let ast = reduce_ok "let a = x\nlet b = a\nb" in
  Alcotest.(check string) "printed"
    {|Var("x")|}
    (Printer.to_string ast)

let test_reduce_nested_application () =
  let ast = reduce_ok "let f = \\ x -> x\nlet g = \\ y -> f(y)\ng(a)" in
  Alcotest.(check string) "printed"
    {|Var("a")|}
    (Printer.to_string ast)

let test_reduce_free_variable () =
  (* y is free in the lambda body — survives as Var *)
  let ast = reduce_ok "let f = \\ x -> y\nf(a)" in
  Alcotest.(check string) "printed"
    {|Var("y")|}
    (Printer.to_string ast)

let test_reduce_arity_mismatch () =
  reduce_fails "let f = \\ x, y -> x\nf(a)"

let test_reduce_free_var_apply () =
  (* Applying a bound variable that resolves to a free Var now survives *)
  let ast = reduce_ok "let f = a\nf(b)" in
  Alcotest.(check string) "printed"
    {|App(Var("a"), [Positional(Var("b"))])|}
    (Printer.to_string ast)

let test_reduce_curried_free_var_apply () =
  (* Curried application on free var: let g = f(b) then g(c) *)
  let ast = reduce_ok "let g = f(b)\ng(c)" in
  Alcotest.(check string) "printed"
    {|App(App(Var("f"), [Positional(Var("b"))]), [Positional(Var("c"))])|}
    (Printer.to_string ast)

let test_reduce_string_lit_passthrough () =
  let ast = reduce_ok {|"hello" >>> a|} in
  Alcotest.(check string) "printed"
    {|Seq(StringLit("hello"), Var("a"))|}
    (Printer.to_string ast)

let test_reduce_string_lit_as_arg () =
  let ast = reduce_ok ({|let f = \x -> x >>> a|} ^ "\n" ^ {|f("hello")|}) in
  Alcotest.(check string) "printed"
    {|Seq(StringLit("hello"), Var("a"))|}
    (Printer.to_string ast)

let test_reduce_string_lit_apply_error () =
  match reduce_ok ({|let s = "hello"|} ^ "\n" ^ {|s("world")|}) with
  | _ -> Alcotest.fail "expected reduce error"
  | exception Reducer.Reduce_error (_, msg) ->
    Alcotest.(check bool) "error mentions string literal"
      true (contains msg "string literal")

let test_parse_let_simple () =
  let tokens = Lexer.tokenize "let f = a >>> b\nf" in
  let ast = Parser.parse_program tokens in
  match ast.desc with
  | Let ("f", value, body) ->
    (match value.desc with
     | Seq _ -> ()
     | _ -> Alcotest.fail "expected Seq value");
    (match body.desc with
     | Var "f" -> ()
     | _ -> Alcotest.fail "expected Var f body")
  | _ -> Alcotest.fail "expected Let"

let test_parse_let_multiple () =
  let tokens = Lexer.tokenize "let a = x\nlet b = y\na >>> b" in
  let ast = Parser.parse_program tokens in
  match ast.desc with
  | Let ("a", _, inner) ->
    (match inner.desc with
     | Let ("b", _, body) ->
       (match body.desc with
        | Seq _ -> ()
        | _ -> Alcotest.fail "expected Seq body")
     | _ -> Alcotest.fail "expected nested Let")
  | _ -> Alcotest.fail "expected Let"

let test_parse_let_with_lambda () =
  let tokens = Lexer.tokenize "let f = \\ x -> x >>> a\nf(b)" in
  let ast = Parser.parse_program tokens in
  match ast.desc with
  | Let ("f", value, body) ->
    (match value.desc with
     | Lambda _ -> ()
     | _ -> Alcotest.fail "expected Lambda value");
    (match body.desc with
     | App (_, _) -> ()
     | _ -> Alcotest.fail "expected App body")
  | _ -> Alcotest.fail "expected Let"

let test_parse_let_scope () =
  (* Without scope tracking, a in b's value is parsed as Var "a" *)
  let tokens = Lexer.tokenize "let a = x\nlet b = a\nb" in
  let ast = Parser.parse_program tokens in
  match ast.desc with
  | Let ("a", _, inner) ->
    (match inner.desc with
     | Let ("b", value, _) ->
       (match value.desc with
        | Var "a" -> ()
        | _ -> Alcotest.fail "expected Var a in b's value")
     | _ -> Alcotest.fail "expected nested Let")
  | _ -> Alcotest.fail "expected Let"

let test_parse_no_let_is_program () =
  let tokens = Lexer.tokenize "a >>> b" in
  let ast = Parser.parse_program tokens in
  match ast.desc with
  | Seq _ -> ()
  | _ -> Alcotest.fail "expected Seq"

let test_parse_lambda_single_param () =
  let ast = parse_ok "\\ x -> a >>> b" in
  match ast.desc with
  | Lambda (["x"], body) ->
    (match body.desc with
     | Seq _ -> ()
     | _ -> Alcotest.fail "expected Seq body")
  | _ -> Alcotest.fail "expected Lambda"

let test_parse_lambda_multi_param () =
  let ast = parse_ok "\\ x, y -> a" in
  match ast.desc with
  | Lambda (["x"; "y"], _) -> ()
  | _ -> Alcotest.fail "expected Lambda with two params"

let test_parse_lambda_var_in_body () =
  let ast = parse_ok "\\ x -> x >>> a" in
  match ast.desc with
  | Lambda (["x"], body) ->
    (match body.desc with
     | Seq (lhs, _) ->
       (match lhs.desc with
        | Var "x" -> ()
        | _ -> Alcotest.fail "expected Var x")
     | _ -> Alcotest.fail "expected Seq")
  | _ -> Alcotest.fail "expected Lambda"

let test_parse_lambda_in_group () =
  let ast = parse_ok "(\\ x -> x) >>> a" in
  match ast.desc with
  | Seq (lhs, _) ->
    (match lhs.desc with
     | Group inner ->
       (match inner.desc with
        | Lambda _ -> ()
        | _ -> Alcotest.fail "expected Lambda inside Group")
     | _ -> Alcotest.fail "expected Group")
  | _ -> Alcotest.fail "expected Seq"

let test_lex_backslash () =
  let tokens = Lexer.tokenize "\\ x" in
  match (List.hd tokens).token with
  | Lexer.BACKSLASH -> ()
  | _ -> Alcotest.fail "expected BACKSLASH token"

let test_lex_let_keyword () =
  let tokens = Lexer.tokenize "let x" in
  match (List.hd tokens).token with
  | Lexer.LET -> ()
  | _ -> Alcotest.fail "expected LET token"

let test_lex_equals () =
  let tokens = Lexer.tokenize "=" in
  match (List.hd tokens).token with
  | Lexer.EQUALS -> ()
  | _ -> Alcotest.fail "expected EQUALS token"

let test_lex_let_in_ident () =
  let tokens = Lexer.tokenize "letter" in
  match (List.hd tokens).token with
  | Lexer.IDENT "letter" -> ()
  | _ -> Alcotest.fail "expected IDENT letter"

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
  ; "question token", `Quick, test_lex_question
  ; "question with space", `Quick, test_lex_question_with_space
  ; "question after string", `Quick, test_lex_question_after_string
  ; "ident loc span", `Quick, test_lex_ident_loc_span
  ; "operator loc span", `Quick, test_lex_operator_loc_span
  ; "string loc span", `Quick, test_lex_string_loc_span
  ; "question loc span", `Quick, test_lex_question_loc_span
  ; "eof loc span", `Quick, test_lex_eof_loc_span
  ; "unicode ident loc span", `Quick, test_lex_unicode_ident_loc_span
  ; "double colon", `Quick, test_lex_double_colon
  ; "arrow token", `Quick, test_lex_arrow
  ; "type annotation tokens", `Quick, test_lex_type_annotation
  ; "colon still works", `Quick, test_lex_colon_still_works
  ; "arrow not negative", `Quick, test_lex_arrow_not_negative
  ; "arrow no whitespace", `Quick, test_lex_arrow_no_whitespace
  ; "arrow no whitespace in type ann", `Quick, test_lex_arrow_no_whitespace_in_type_ann
  ; "ident with hyphen before arrow", `Quick, test_lex_ident_with_hyphen_before_arrow
  ; "backslash token", `Quick, test_lex_backslash
  ; "let keyword", `Quick, test_lex_let_keyword
  ; "equals token", `Quick, test_lex_equals
  ; "let prefix in ident", `Quick, test_lex_let_in_ident
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
  ; "string question", `Quick, test_parse_string_question
  ; "node question", `Quick, test_parse_node_question
  ; "bare node question", `Quick, test_parse_bare_node_question
  ; "question with space", `Quick, test_parse_question_with_space
  ; "question in loop", `Quick, test_parse_question_in_loop
  ; "question in group", `Quick, test_parse_question_in_group
  ; "comment on node question", `Quick, test_parse_comment_on_node_question
  ; "comment on string question", `Quick, test_parse_comment_on_string_question
  ; "node loc span", `Quick, test_parse_node_loc
  ; "seq loc span", `Quick, test_parse_seq_loc
  ; "group loc span", `Quick, test_parse_group_loc
  ; "loop loc span", `Quick, test_parse_loop_loc
  ; "multiline loc span", `Quick, test_parse_multiline_loc
  ; "question loc span", `Quick, test_parse_question_loc
  ; "node with args loc span", `Quick, test_parse_node_with_args_loc
  ; "unicode node loc span", `Quick, test_parse_unicode_node_loc
  ; "type ann no whitespace", `Quick, test_parse_type_ann_no_whitespace
  ; "type ann bare node", `Quick, test_parse_type_ann_bare_node
  ; "type ann node with args", `Quick, test_parse_type_ann_node_with_args
  ; "type ann optional", `Quick, test_parse_type_ann_optional
  ; "type ann in seq", `Quick, test_parse_type_ann_in_seq
  ; "type ann mixed", `Quick, test_parse_type_ann_mixed
  ; "type ann on group", `Quick, test_parse_type_ann_on_group
  ; "type ann on loop", `Quick, test_parse_type_ann_on_loop
  ; "type ann on question", `Quick, test_parse_type_ann_on_question
  ; "type ann unicode", `Quick, test_parse_type_ann_unicode
  ; "type ann with comment", `Quick, test_parse_type_ann_with_comment
  ; "type ann incomplete error", `Quick, test_parse_type_ann_incomplete_error
  ; "type ann missing output error", `Quick, test_parse_type_ann_missing_output_error
  ; "type ann loc span", `Quick, test_parse_type_ann_loc
  ; "type ann loc no ann", `Quick, test_parse_type_ann_loc_no_ann
  ; "lambda single param", `Quick, test_parse_lambda_single_param
  ; "lambda multi param", `Quick, test_parse_lambda_multi_param
  ; "lambda var in body", `Quick, test_parse_lambda_var_in_body
  ; "lambda in group", `Quick, test_parse_lambda_in_group
  ; "let simple", `Quick, test_parse_let_simple
  ; "let multiple", `Quick, test_parse_let_multiple
  ; "let with lambda", `Quick, test_parse_let_with_lambda
  ; "let scope", `Quick, test_parse_let_scope
  ; "no let is program", `Quick, test_parse_no_let_is_program
  ; "string lit", `Quick, test_parse_string_lit
  ; "string lit as positional arg", `Quick, test_parse_string_lit_as_positional_arg
  ; "string lit alone", `Quick, test_parse_string_lit_alone
  ; "string lit in par", `Quick, test_parse_string_lit_in_par
  ]

let checker_tests =
  [ "loop plain no error", `Quick, test_check_loop_plain_no_error
  ; "loop with unicode nodes", `Quick, test_check_loop_unicode_no_error
  ; "question with alt", `Quick, test_check_question_with_alt
  ; "question without alt", `Quick, test_check_question_without_alt
  ; "question with intermediate steps", `Quick, test_check_question_with_intermediate_steps
  ; "question alt in par no match", `Quick, test_check_question_alt_in_par_no_match
  ; "question in loop", `Quick, test_check_question_in_loop
  ; "question in loop no alt", `Quick, test_check_question_in_loop_no_alt
  ; "multiple questions", `Quick, test_check_multiple_questions
  ; "multiple questions unmatched", `Quick, test_check_multiple_questions_unmatched
  ; "existing alt no warning", `Quick, test_check_existing_alt_no_warning
  ; "question in group with alt", `Quick, test_check_question_in_group_with_alt
  ; "question in fanout branch", `Quick, test_check_question_in_fanout_branch
  ; "question in fanout branch no alt", `Quick, test_check_question_in_fanout_branch_no_alt
  ; "alt before question still warns", `Quick, test_check_alt_before_question_still_warns
  ; "question not at tail alt operand", `Quick, test_check_question_not_at_tail_alt_operand
  ; "question tail as alt operand", `Quick, test_check_question_tail_as_alt_operand
  ; "question direct alt operand", `Quick, test_check_question_direct_alt_operand
  ; "question multiple with tail alt operand", `Quick, test_check_question_multiple_with_tail_alt_operand
  ; "question warning loc", `Quick, test_check_question_warning_loc
  ; "string lit no error", `Quick, test_check_string_lit_no_error
  ; "string lit question with alt", `Quick, test_check_string_lit_question_with_alt
  ]

let test_print_type_ann () =
  let ast = parse_ok "fetch :: URL -> HTML" in
  Alcotest.(check string) "printed"
    {|TypeAnn(Var("fetch"), "URL", "HTML")|}
    (Printer.to_string ast)

let test_print_type_ann_in_seq () =
  let ast = parse_ok "a :: X -> Y >>> b :: Y -> Z" in
  Alcotest.(check string) "printed"
    {|Seq(TypeAnn(Var("a"), "X", "Y"), TypeAnn(Var("b"), "Y", "Z"))|}
    (Printer.to_string ast)

let test_print_no_type_ann () =
  let ast = parse_ok "a >>> b" in
  Alcotest.(check string) "printed"
    {|Seq(Var("a"), Var("b"))|}
    (Printer.to_string ast)

let test_print_lambda () =
  let ast = parse_ok "\\ x -> a" in
  Alcotest.(check string) "printed"
    {|Lambda(["x"], Var("a"))|}
    (Printer.to_string ast)

let test_print_var () =
  let ast = parse_ok "\\ x -> x" in
  match ast.desc with
  | Lambda (_, body) ->
    Alcotest.(check string) "printed"
      "Var(\"x\")"
      (Printer.to_string body)
  | _ -> Alcotest.fail "expected Lambda"

let test_print_app () =
  let tokens = Lexer.tokenize "let f = \\ x -> x\nf(a)" in
  let ast = Parser.parse_program tokens in
  match ast.desc with
  | Let (_, _, body) ->
    Alcotest.(check string) "printed"
      {|App(Var("f"), [Positional(Var("a"))])|}
      (Printer.to_string body)
  | _ -> Alcotest.fail "expected Let"

let test_print_let () =
  let tokens = Lexer.tokenize "let f = a\nf" in
  let ast = Parser.parse_program tokens in
  Alcotest.(check string) "printed"
    {|Let("f", Var("a"), Var("f"))|}
    (Printer.to_string ast)

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
  ; "comment dropped", `Quick, test_print_comment
  ; "question string", `Quick, test_print_question_string
  ; "question node", `Quick, test_print_question_node
  ; "string lit", `Quick, test_print_string_lit
  ; "type annotation", `Quick, test_print_type_ann
  ; "type annotation in seq", `Quick, test_print_type_ann_in_seq
  ; "no type annotation unchanged", `Quick, test_print_no_type_ann
  ; "lambda", `Quick, test_print_lambda
  ; "var", `Quick, test_print_var
  ; "app", `Quick, test_print_app
  ; "let", `Quick, test_print_let
  ]

(* Integration: full pipeline parse_program >>> reduce >>> check *)
let test_integration_let_and_check () =
  let input = "let f = \\ x -> x >>> a\nf(b)" in
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

let integration_tests =
  [ "let and check", `Quick, test_integration_let_and_check
  ; "backward compat", `Quick, test_integration_backward_compat
  ]

let reducer_tests =
  [ "no lambda passthrough", `Quick, test_reduce_no_lambda
  ; "let simple", `Quick, test_reduce_let_simple
  ; "lambda apply", `Quick, test_reduce_lambda_apply
  ; "lambda multi param", `Quick, test_reduce_lambda_multi_param
  ; "let chain", `Quick, test_reduce_let_chain
  ; "nested application", `Quick, test_reduce_nested_application
  ; "free variable as var", `Quick, test_reduce_free_variable
  ; "arity mismatch error", `Quick, test_reduce_arity_mismatch
  ; "free var apply survives", `Quick, test_reduce_free_var_apply
  ; "curried free var apply", `Quick, test_reduce_curried_free_var_apply
  ; "string lit passthrough", `Quick, test_reduce_string_lit_passthrough
  ; "string lit as arg", `Quick, test_reduce_string_lit_as_arg
  ; "string lit apply error", `Quick, test_reduce_string_lit_apply_error
  ]

(* Lambda with type annotations in body *)
let test_reduce_lambda_with_type_ann () =
  let ast = reduce_ok "let f = \\ x -> x :: A -> B\nf(a)" in
  Alcotest.(check string) "printed"
    {|TypeAnn(Var("a"), "A", "B")|}
    (Printer.to_string ast)

(* Lambda with Arrow operators in args *)
let test_reduce_lambda_complex_args () =
  let ast = reduce_ok "let f = \\ x, y -> x >>> y\nf(a >>> b, c)" in
  Alcotest.(check string) "printed"
    {|Seq(Seq(Var("a"), Var("b")), Var("c"))|}
    (Printer.to_string ast)

(* Unicode in lambda params *)
let test_parse_lambda_unicode_param () =
  let ast = parse_ok "\\ \xe8\xa7\xb8\xe7\x99\xbc -> \xe8\xa7\xb8\xe7\x99\xbc >>> \xe5\xae\x8c\xe6\x88\x90" in
  match ast.desc with
  | Lambda (["\xe8\xa7\xb8\xe7\x99\xbc"], _) -> ()
  | _ -> Alcotest.fail "expected Lambda with unicode param"

(* Let binding with unicode name *)
let test_parse_let_unicode_name () =
  let tokens = Lexer.tokenize "let \xe5\xaf\xa9\xe6\x9f\xbb = a >>> b\n\xe5\xaf\xa9\xe6\x9f\xbb" in
  let ast = Parser.parse_program tokens in
  match ast.desc with
  | Let ("\xe5\xaf\xa9\xe6\x9f\xbb", _, _) -> ()
  | _ -> Alcotest.fail "expected Let with unicode name"

(* Empty pipeline body after let *)
let test_parse_let_error_no_body () =
  match Lexer.tokenize "let f = a" |> Parser.parse_program with
  | _ -> Alcotest.fail "expected parse error (no body after let)"
  | exception Parser.Parse_error _ -> ()

(* Lambda with zero params — should be parse error *)
let test_parse_lambda_no_params () =
  match Lexer.tokenize "\\ -> a" |> Parser.parse_program with
  | _ -> Alcotest.fail "expected parse error"
  | exception Parser.Parse_error _ -> ()

(* Positional args on undefined name — now survives reduction as free Var *)
let test_reduce_positional_on_undefined () =
  let ast = reduce_ok "f(a, b)" in
  Alcotest.(check string) "printed"
    {|App(Var("f"), [Positional(Var("a")), Positional(Var("b"))])|}
    (Printer.to_string ast)

(* let keyword can no longer be used as a node name *)
let test_parse_let_keyword_not_node () =
  match Lexer.tokenize "let >>> a" |> Parser.parse_program with
  | _ -> Alcotest.fail "expected parse error (let is now a keyword)"
  | exception Parser.Parse_error _ -> ()

(* Comments inside lambda body *)
let test_parse_lambda_with_comment () =
  let ast = parse_ok "\\ x -> x -- hello\n>>> a" in
  match ast.desc with
  | Lambda _ -> ()
  | _ -> Alcotest.fail "expected Lambda"

(* Duplicate lambda params — should be parse error *)
let test_parse_lambda_duplicate_params () =
  match Lexer.tokenize "\\ x, x -> x" |> Parser.parse_program with
  | _ -> Alcotest.fail "expected parse error (duplicate param)"
  | exception Parser.Parse_error (_, msg) ->
    Alcotest.(check bool) "mentions duplicate" true (contains msg "duplicate")

(* Empty application f() — now parses OK, but arity error at reduce *)
let test_reduce_empty_application_arity () =
  match reduce_ok "let f = \\ x -> x\nf()" with
  | _ -> Alcotest.fail "expected reduce error (arity mismatch)"
  | exception Reducer.Reduce_error (_, msg) ->
    Alcotest.(check bool) "mentions arity" true (contains msg "arity")

(* Trailing comma in args — should be parse error *)
let test_parse_trailing_comma_args () =
  match Lexer.tokenize "f(a,)" |> Parser.parse_program with
  | _ -> Alcotest.fail "expected parse error (trailing comma)"
  | exception Parser.Parse_error (_, msg) ->
    Alcotest.(check bool) "mentions trailing comma" true (contains msg "trailing comma")

let test_reduce_capture_avoiding () =
  let ast = reduce_ok "let apply = \\ f, x -> f(x)\nlet id = \\ x -> x\napply(id, a)" in
  Alcotest.(check string) "printed"
    {|Var("a")|}
    (Printer.to_string ast)

(* === New feature tests: mixed args === *)

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
  | App ({ desc = Var "noop"; _ }, []) -> ()
  | _ -> Alcotest.fail "expected App(Var noop, [])"

let test_reduce_mixed_args () =
  let ast = reduce_ok "let v = a >>> b\npush(remote: origin, v)" in
  Alcotest.(check string) "printed"
    {|App(Var("push"), [Named(remote: Ident("origin")), Positional(Seq(Var("a"), Var("b")))])|}
    (Printer.to_string ast)

let test_reduce_named_args_on_lambda_error () =
  reduce_fails "let f = \\ x -> x\nf(key: val)"

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
  let _ = check_ok "let v = a >>> b\npush(remote: origin, v)" in
  ()

let test_check_question_in_positional_arg () =
  let warnings = check_ok_with_warnings "push(remote: origin, inner?)" in
  Alcotest.(check int) "1 warning from isolated arg" 1 (List.length warnings)

let test_check_app_question_with_alt () =
  let _ = check_ok "check(strict: true)? >>> (pass ||| fail)" in
  ()

let test_integration_mixed_args () =
  let input = "let v = some_pipeline\npush(remote: origin, v)" in
  let tokens = Lexer.tokenize input in
  let ast = Parser.parse_program tokens in
  let reduced = Reducer.reduce ast in
  let result = Checker.check reduced in
  Alcotest.(check int) "no warnings" 0 (List.length result.Checker.warnings)

let edge_case_tests =
  [ "lambda with type ann", `Quick, test_reduce_lambda_with_type_ann
  ; "lambda complex args", `Quick, test_reduce_lambda_complex_args
  ; "lambda unicode param", `Quick, test_parse_lambda_unicode_param
  ; "let unicode name", `Quick, test_parse_let_unicode_name
  ; "let error no body", `Quick, test_parse_let_error_no_body
  ; "lambda no params error", `Quick, test_parse_lambda_no_params
  ; "positional on undefined survives", `Quick, test_reduce_positional_on_undefined
  ; "let keyword not node", `Quick, test_parse_let_keyword_not_node
  ; "lambda with comment", `Quick, test_parse_lambda_with_comment
  ; "lambda duplicate params", `Quick, test_parse_lambda_duplicate_params
  ; "capture avoiding substitution", `Quick, test_reduce_capture_avoiding
  ; "empty application arity", `Quick, test_reduce_empty_application_arity
  ; "trailing comma args", `Quick, test_parse_trailing_comma_args
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
  ]

let () =
  Alcotest.run "compose-dsl"
    [ "Lexer", lexer_tests
    ; "Parser", parser_tests
    ; "Checker", checker_tests
    ; "Printer", printer_tests
    ; "Reducer", reducer_tests
    ; "Integration", integration_tests
    ; "Edge cases", edge_case_tests
    ; "Mixed args", mixed_arg_tests
    ]
