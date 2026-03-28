open Compose_dsl
open Helpers

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
  | Ast.App ({ desc = Ast.Var "noop"; _ }, [Positional { desc = Ast.Unit; _ }]) -> ()
  | _ -> Alcotest.fail "expected App(Var noop, [Positional Unit])"

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
  let msg = parse_error_msg "a(" in
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

(* === Type annotation parser tests === *)

let test_parse_type_ann_no_whitespace () =
  let ast = parse_ok "node::A->B" in
  Alcotest.(check (option (pair string string))) "type_ann"
    (Some ("A", "B"))
    (Option.map (fun (t : Ast.type_ann) -> (t.input, t.output)) ast.type_ann)

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
  let msg = parse_error_msg "node :: A" in
  Alcotest.(check bool) "error mentions ->" true (contains msg "->")

let test_parse_type_ann_missing_output_error () =
  let msg = parse_error_msg "node :: A ->" in
  Alcotest.(check bool) "error mentions ->" true (contains msg "->")

(* === String lit parse tests === *)

let test_parse_string_lit () =
  match desc_of {|"hello" >>> a|} with
  | Ast.Seq ({ desc = Ast.StringLit "hello"; _ }, { desc = Ast.Var "a"; _ }) -> ()
  | _ -> Alcotest.fail "expected Seq(StringLit, Var)"

let test_parse_string_lit_as_positional_arg () =
  let ast = reduce_ok {|let f = \x -> x >>> a in f("hello")|} in
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

(* === Let/lambda parser tests === *)

let test_parse_let_simple () =
  let ast = parse_ok "let f = a >>> b in f" in
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
  let ast = parse_ok "let a = x in let b = y in a >>> b" in
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
  let ast = parse_ok "let f = \\ x -> x >>> a in f(b)" in
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
  let ast = parse_ok "let a = x in let b = a in b" in
  match ast.desc with
  | Let ("a", _, inner) ->
    (match inner.desc with
     | Let ("b", value, _) ->
       (match value.desc with
        | Var "a" -> ()
        | _ -> Alcotest.fail "expected Var a in b's value")
     | _ -> Alcotest.fail "expected nested Let")
  | _ -> Alcotest.fail "expected Let"

let test_parse_let_complex_value () =
  let ast = parse_ok "let f = a >>> b in f >>> c" in
  Alcotest.(check string) "printed"
    {|Let("f", Seq(Var("a"), Var("b")), Seq(Var("f"), Var("c")))|}
    (Printer.to_string ast)

let test_parse_let_parenthesized_value () =
  let ast = parse_ok "let x = (let y = a in y) in x" in
  Alcotest.(check string) "printed"
    {|Let("x", Group(Let("y", Var("a"), Var("y"))), Var("x"))|}
    (Printer.to_string ast)

let test_parse_no_let_is_program () =
  let ast = parse_ok "a >>> b" in
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

(* === Edge case parse tests === *)

(* Unicode in lambda params *)
let test_parse_lambda_unicode_param () =
  let ast = parse_ok "\\ \xe8\xa7\xb8\xe7\x99\xbc -> \xe8\xa7\xb8\xe7\x99\xbc >>> \xe5\xae\x8c\xe6\x88\x90" in
  match ast.desc with
  | Lambda (["\xe8\xa7\xb8\xe7\x99\xbc"], _) -> ()
  | _ -> Alcotest.fail "expected Lambda with unicode param"

(* Let binding with unicode name *)
let test_parse_let_unicode_name () =
  let ast = parse_ok "let \xe5\xaf\xa9\xe6\x9f\xbb = a >>> b in \xe5\xaf\xa9\xe6\x9f\xbb" in
  match ast.desc with
  | Let ("\xe5\xaf\xa9\xe6\x9f\xbb", _, _) -> ()
  | _ -> Alcotest.fail "expected Let with unicode name"

(* Missing 'in' after let binding *)
let test_parse_let_error_no_body () =
  let msg = parse_error_msg "let f = a" in
  Alcotest.(check bool) "mentions 'in'" true (contains msg "in")

(* Lambda with zero params — should be parse error *)
let test_parse_lambda_no_params () =
  parse_fails "\\ -> a"

(* let keyword can no longer be used as a node name *)
let test_parse_let_keyword_not_node () =
  parse_fails "let >>> a"

(* Comments inside lambda body *)
let test_parse_lambda_with_comment () =
  let ast = parse_ok "\\ x -> x -- hello\n>>> a" in
  match ast.desc with
  | Lambda _ -> ()
  | _ -> Alcotest.fail "expected Lambda"

(* Duplicate lambda params — should be parse error *)
let test_parse_lambda_duplicate_params () =
  match parse_ok "\\ x, x -> x" with
  | _ -> Alcotest.fail "expected parse error (duplicate param)"
  | exception Ast.Duplicate_param (_, msg) ->
    Alcotest.(check bool) "mentions duplicate" true (contains msg "duplicate")

(* Trailing comma in args — should be parse error *)
let test_parse_trailing_comma_args () =
  let msg = parse_error_msg "f(a,)" in
  Alcotest.(check bool) "mentions trailing comma" true (contains msg "trailing comma")

(* === Let-in edge case tests === *)

let test_parse_let_old_syntax_error () =
  parse_fails "let x = a\nx"

let test_parse_let_in_lambda_body_error () =
  parse_fails "\\ x -> let y = x in y"

let test_parse_let_in_positional_arg_error () =
  parse_fails "f(let x = a in x)"

let test_parse_in_as_term_error () =
  parse_fails "a >>> in"

let test_parse_let_ident_starting_with_in () =
  let ast = parse_ok "let x = in_progress in x" in
  Alcotest.(check string) "printed"
    {|Let("x", Var("in_progress"), Var("x"))|}
    (Printer.to_string ast)

let test_parse_unit_type_ann_input () =
  let ast = parse_ok "node :: () -> Output" in
  match ast.type_ann with
  | Some { input = "()"; output = "Output" } -> ()
  | _ -> Alcotest.fail "expected type_ann { input = \"()\"; output = \"Output\" }"

let test_parse_unit_type_ann_output () =
  let ast = parse_ok "node :: Input -> ()" in
  match ast.type_ann with
  | Some { input = "Input"; output = "()" } -> ()
  | _ -> Alcotest.fail "expected type_ann { input = \"Input\"; output = \"()\" }"

let test_parse_unit_type_ann_both () =
  let ast = parse_ok "node :: () -> ()" in
  match ast.type_ann with
  | Some { input = "()"; output = "()" } -> ()
  | _ -> Alcotest.fail "expected type_ann { input = \"()\"; output = \"()\" }"

let test_parse_unit_standalone () =
  match desc_of "()" with
  | Ast.Unit -> ()
  | _ -> Alcotest.fail "expected Unit"

let test_parse_unit_in_seq () =
  match desc_of "() >>> a" with
  | Ast.Seq ({ desc = Ast.Unit; _ }, { desc = Ast.Var "a"; _ }) -> ()
  | _ -> Alcotest.fail "expected Seq(Unit, Var a)"

let test_parse_unit_nested () =
  match desc_of "(())" with
  | Ast.Group { desc = Ast.Unit; _ } -> ()
  | _ -> Alcotest.fail "expected Group(Unit)"

let test_parse_unit_question () =
  match desc_of "()?" with
  | Ast.Question { desc = Ast.Unit; _ } -> ()
  | _ -> Alcotest.fail "expected Question(Unit)"

let tests =
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
  ; "let complex value", `Quick, test_parse_let_complex_value
  ; "let parenthesized value", `Quick, test_parse_let_parenthesized_value
  ; "no let is program", `Quick, test_parse_no_let_is_program
  ; "string lit", `Quick, test_parse_string_lit
  ; "string lit as positional arg", `Quick, test_parse_string_lit_as_positional_arg
  ; "string lit alone", `Quick, test_parse_string_lit_alone
  ; "string lit in par", `Quick, test_parse_string_lit_in_par
  ; "unit standalone", `Quick, test_parse_unit_standalone
  ; "unit in seq", `Quick, test_parse_unit_in_seq
  ; "unit nested", `Quick, test_parse_unit_nested
  ; "unit question", `Quick, test_parse_unit_question
  ; "type ann unit input", `Quick, test_parse_unit_type_ann_input
  ; "type ann unit output", `Quick, test_parse_unit_type_ann_output
  ; "type ann unit both", `Quick, test_parse_unit_type_ann_both
  ]

let test_parse_lambda_returns_unit () =
  match desc_of "\\ x -> ()" with
  | Ast.Lambda (["x"], { desc = Ast.Unit; _ }) -> ()
  | _ -> Alcotest.fail "expected Lambda([x], Unit)"

let edge_case_tests =
  [ "lambda returns unit", `Quick, test_parse_lambda_returns_unit
  ; "lambda unicode param", `Quick, test_parse_lambda_unicode_param
  ; "let unicode name", `Quick, test_parse_let_unicode_name
  ; "let error no body", `Quick, test_parse_let_error_no_body
  ; "lambda no params error", `Quick, test_parse_lambda_no_params
  ; "let keyword not node", `Quick, test_parse_let_keyword_not_node
  ; "lambda with comment", `Quick, test_parse_lambda_with_comment
  ; "lambda duplicate params", `Quick, test_parse_lambda_duplicate_params
  ; "trailing comma args", `Quick, test_parse_trailing_comma_args
  ; "let old syntax error", `Quick, test_parse_let_old_syntax_error
  ; "let in lambda body error", `Quick, test_parse_let_in_lambda_body_error
  ; "let in positional arg error", `Quick, test_parse_let_in_positional_arg_error
  ; "let ident starting with in", `Quick, test_parse_let_ident_starting_with_in
  ; "in as term error", `Quick, test_parse_in_as_term_error
  ]
