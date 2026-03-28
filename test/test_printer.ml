open Compose_dsl
open Helpers

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
  let tokens = Lexer.tokenize "let f = \\ x -> x in f(a)" in
  let ast = Parser.parse_program tokens in
  match ast.desc with
  | Let (_, _, body) ->
    Alcotest.(check string) "printed"
      {|App(Var("f"), [Positional(Var("a"))])|}
      (Printer.to_string body)
  | _ -> Alcotest.fail "expected Let"

let test_print_let () =
  let tokens = Lexer.tokenize "let f = a in f" in
  let ast = Parser.parse_program tokens in
  Alcotest.(check string) "printed"
    {|Let("f", Var("a"), Var("f"))|}
    (Printer.to_string ast)

let test_print_unit () =
  let ast = { Ast.loc = { start = { line = 1; col = 1 }; end_ = { line = 1; col = 3 } };
              desc = Ast.Unit; type_ann = None } in
  Alcotest.(check string) "unit" "Unit" (Printer.to_string ast)

let tests =
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
  ; "unit", `Quick, test_print_unit
  ]
