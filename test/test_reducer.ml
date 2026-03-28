open Compose_dsl
open Helpers

let test_reduce_no_lambda () =
  let ast = reduce_ok "a >>> b" in
  Alcotest.(check string) "printed"
    {|Seq(Var("a"), Var("b"))|}
    (Printer.to_string ast)

let test_reduce_let_simple () =
  let ast = reduce_ok "let f = a >>> b in f" in
  Alcotest.(check string) "printed"
    {|Seq(Var("a"), Var("b"))|}
    (Printer.to_string ast)

let test_reduce_lambda_apply () =
  let ast = reduce_ok "let f = \\ x -> x >>> a in f(b)" in
  Alcotest.(check string) "printed"
    {|Seq(Var("b"), Var("a"))|}
    (Printer.to_string ast)

let test_reduce_lambda_multi_param () =
  let ast = reduce_ok "let f = \\ x, y -> x >>> y in f(a, b)" in
  Alcotest.(check string) "printed"
    {|Seq(Var("a"), Var("b"))|}
    (Printer.to_string ast)

let test_reduce_let_chain () =
  let ast = reduce_ok "let a = x in let b = a in b" in
  Alcotest.(check string) "printed"
    {|Var("x")|}
    (Printer.to_string ast)

let test_reduce_nested_application () =
  let ast = reduce_ok "let f = \\ x -> x in let g = \\ y -> f(y) in g(a)" in
  Alcotest.(check string) "printed"
    {|Var("a")|}
    (Printer.to_string ast)

let test_reduce_free_variable () =
  (* y is free in the lambda body — survives as Var *)
  let ast = reduce_ok "let f = \\ x -> y in f(a)" in
  Alcotest.(check string) "printed"
    {|Var("y")|}
    (Printer.to_string ast)

let test_reduce_arity_mismatch () =
  reduce_fails "let f = \\ x, y -> x in f(a)"

let test_reduce_free_var_apply () =
  (* Applying a bound variable that resolves to a free Var now survives *)
  let ast = reduce_ok "let f = a in f(b)" in
  Alcotest.(check string) "printed"
    {|App(Var("a"), [Positional(Var("b"))])|}
    (Printer.to_string ast)

let test_reduce_curried_free_var_apply () =
  (* Curried application on free var: let g = f(b) then g(c) *)
  let ast = reduce_ok "let g = f(b) in g(c)" in
  Alcotest.(check string) "printed"
    {|App(App(Var("f"), [Positional(Var("b"))]), [Positional(Var("c"))])|}
    (Printer.to_string ast)

let test_reduce_curried_free_var_lambda_rejected () =
  (* Lambda hidden inside curried free var app must be caught by verify *)
  match reduce_ok "let g = f(\\ x -> x) in g(a)" with
  | _ -> Alcotest.fail "expected reduce error (lambda not fully applied)"
  | exception Reducer.Reduce_error (_, msg) ->
    Alcotest.(check bool) "mentions lambda" true (contains msg "lambda")

let test_reduce_deep_curried_free_var_apply () =
  (* Depth-3 curried free var: let h = g(d) where g = f(b) *)
  let ast = reduce_ok "let g = f(b) in let h = g(c) in h(d)" in
  Alcotest.(check string) "printed"
    {|App(App(App(Var("f"), [Positional(Var("b"))]), [Positional(Var("c"))]), [Positional(Var("d"))])|}
    (Printer.to_string ast)

let test_reduce_string_lit_passthrough () =
  let ast = reduce_ok {|"hello" >>> a|} in
  Alcotest.(check string) "printed"
    {|Seq(StringLit("hello"), Var("a"))|}
    (Printer.to_string ast)

let test_reduce_string_lit_as_arg () =
  let ast = reduce_ok {|let f = \x -> x >>> a in f("hello")|} in
  Alcotest.(check string) "printed"
    {|Seq(StringLit("hello"), Var("a"))|}
    (Printer.to_string ast)

let test_reduce_string_lit_apply_error () =
  match reduce_ok {|let s = "hello" in s("world")|} with
  | _ -> Alcotest.fail "expected reduce error"
  | exception Reducer.Reduce_error (_, msg) ->
    Alcotest.(check bool) "error mentions string literal"
      true (contains msg "string literal")

(* Lambda with type annotations in body *)
let test_reduce_lambda_with_type_ann () =
  let ast = reduce_ok "let f = \\ x -> x :: A -> B in f(a)" in
  Alcotest.(check string) "printed"
    {|TypeAnn(Var("a"), "A", "B")|}
    (Printer.to_string ast)

(* Lambda with Arrow operators in args *)
let test_reduce_lambda_complex_args () =
  let ast = reduce_ok "let f = \\ x, y -> x >>> y in f(a >>> b, c)" in
  Alcotest.(check string) "printed"
    {|Seq(Seq(Var("a"), Var("b")), Var("c"))|}
    (Printer.to_string ast)

(* Positional args on undefined name — now survives reduction as free Var *)
let test_reduce_positional_on_undefined () =
  let ast = reduce_ok "f(a, b)" in
  Alcotest.(check string) "printed"
    {|App(Var("f"), [Positional(Var("a")), Positional(Var("b"))])|}
    (Printer.to_string ast)

(* Empty application f() — applies Unit, so identity returns Unit *)
let test_reduce_empty_call_applies_unit () =
  let ast = reduce_ok "let f = \\ x -> x in f()" in
  match ast.desc with
  | Ast.Unit -> ()
  | _ -> Alcotest.fail "expected Unit (identity applied to unit)"

let test_reduce_capture_avoiding () =
  let ast = reduce_ok "let apply = \\ f, x -> f(x) in let id = \\ x -> x in apply(id, a)" in
  Alcotest.(check string) "printed"
    {|Var("a")|}
    (Printer.to_string ast)

let test_reduce_unit_passthrough () =
  let ast = reduce_ok "()" in
  match ast.desc with
  | Ast.Unit -> ()
  | _ -> Alcotest.fail "expected Unit to survive reduction"

let tests =
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
  ; "curried free var lambda rejected", `Quick, test_reduce_curried_free_var_lambda_rejected
  ; "deep curried free var apply", `Quick, test_reduce_deep_curried_free_var_apply
  ; "string lit passthrough", `Quick, test_reduce_string_lit_passthrough
  ; "string lit as arg", `Quick, test_reduce_string_lit_as_arg
  ; "string lit apply error", `Quick, test_reduce_string_lit_apply_error
  ; "lambda with type ann", `Quick, test_reduce_lambda_with_type_ann
  ; "lambda complex args", `Quick, test_reduce_lambda_complex_args
  ; "positional on undefined survives", `Quick, test_reduce_positional_on_undefined
  ; "capture avoiding substitution", `Quick, test_reduce_capture_avoiding
  ; "empty call applies unit", `Quick, test_reduce_empty_call_applies_unit
  ; "unit passthrough", `Quick, test_reduce_unit_passthrough
  ]
