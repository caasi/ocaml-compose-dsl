# Lambda and Let Binding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add lambda expressions (`\x -> expr`), let bindings (`let x = expr`), variable references, and positional-arg application to the Arrow DSL, with beta reduction before structural checking.

**Architecture:** Three new tokens (`BACKSLASH`, `LET`, `EQUALS`) in lexer; four new AST nodes (`Lambda`, `Var`, `App`, `Let`); parser extended with scope tracking (a `StringSet`) to distinguish `Var` from `Node`; new `reducer.ml` module for desugaring `Let` and performing beta reduction; existing `checker.ml` unchanged (runs on reduced AST); pipeline in `main.ml` becomes `parse >>> reduce >>> check`.

**Tech Stack:** OCaml 5.1, Dune, Alcotest

**Spec:** `docs/superpowers/specs/2026-03-26-lambda-and-let-binding-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/ast.ml` | Modify | Add `Lambda`, `Var`, `App`, `Let` to `expr_desc` |
| `lib/lexer.ml` | Modify | Add `BACKSLASH`, `LET`, `EQUALS` tokens; `let` keyword in `read_ident` |
| `lib/parser.ml` | Modify | Add scope tracking, `parse_program`, `parse_lambda`, positional args |
| `lib/reducer.ml` | Create | New module: desugar `Let`, beta reduce, verify fully reduced |
| `lib/printer.ml` | Modify | Handle new AST node types |
| `lib/checker.ml` | Modify | Handle new nodes in `normalize` and `check` (pass-through for pre-reduction diagnostics) |
| `bin/main.ml` | Modify | Insert `Reducer.reduce` between parse and check |
| `test/test_compose_dsl.ml` | Modify | Add tests for all new features |
| `README.md` | Modify | Update EBNF grammar |

---

### Task 0: Create feature branch

- [ ] **Step 1: Create and switch to feature branch**

```bash
git checkout -b feat/lambda-let-binding
```

---

### Task 1: AST — add new node types

**Files:**
- Modify: `lib/ast.ml`

- [ ] **Step 1: Add new variants to `expr_desc`**

In `lib/ast.ml`, add four new variants at the end of the `expr_desc` type:

```ocaml
type expr = { loc : loc; desc : expr_desc; type_ann : type_ann option }
and expr_desc =
  | Node of node
  | Seq of expr * expr (** [>>>] *)
  | Par of expr * expr (** [***] *)
  | Fanout of expr * expr (** [&&&] *)
  | Alt of expr * expr (** [|||] *)
  | Loop of expr
  | Group of expr
  | Question of question_term
  | Lambda of string list * expr    (** [\x, y -> body] *)
  | Var of string                   (** [variable reference] *)
  | App of expr * expr list         (** [f(arg1, arg2)] *)
  | Let of string * expr * expr     (** [let x = e1 in e2] *)
```

- [ ] **Step 2: Build — expect compilation errors**

Run: `dune build`
Expected: FAIL — exhaustive pattern matches in `checker.ml`, `printer.ml`, and `parser.ml` will be incomplete. This is expected; we fix these in subsequent tasks.

- [ ] **Step 3: Fix `checker.ml` — add wildcard cases for new nodes**

In `lib/checker.ml`, update `normalize` to pass through new nodes, and update `check`/`go`/`scan_questions`/`tail_has_question` to handle them. Since the checker runs on **reduced** AST (which should never contain these nodes), add defensive cases:

In `normalize`:
```ocaml
  | Lambda _ | Var _ | App _ | Let _ -> e
```

In `scan_questions`:
```ocaml
    | Lambda _ | Var _ | App _ | Let _ -> counter
```

In `tail_has_question`:
```ocaml
    | Lambda _ | Var _ | App _ | Let _ -> false
```

In `go`:
```ocaml
    | Lambda _ | Var _ | App _ | Let _ -> ()
```

- [ ] **Step 4: Fix `printer.ml` — add cases for new nodes**

In `lib/printer.ml`, update `to_string` to handle new nodes. Also update `attach_comments_right` in `parser.ml`:

In `printer.ml`, inside the `match e.desc with` in `to_string`:
```ocaml
    | Lambda (params, body) ->
      Printf.sprintf "Lambda(%s, %s)"
        (String.concat ", " params) (to_string body)
    | Var name -> Printf.sprintf "Var(%S)" name
    | App (fn, args) ->
      Printf.sprintf "App(%s, %s)" (to_string fn)
        (String.concat ", " (List.map to_string args))
    | Let (name, value, body) ->
      Printf.sprintf "Let(%S, %s, %s)" name (to_string value) (to_string body)
```

In `parser.ml`, inside `attach_comments_right`:
```ocaml
    | Lambda _ | Var _ | App _ | Let _ -> e
```

- [ ] **Step 5: Build to verify compilation succeeds**

Run: `dune build`
Expected: success.

- [ ] **Step 6: Run existing tests to verify nothing broke**

Run: `dune test`
Expected: all existing tests pass unchanged.

- [ ] **Step 7: Commit**

```bash
git add lib/ast.ml lib/checker.ml lib/printer.ml lib/parser.ml
git commit -m "feat(ast): add Lambda, Var, App, Let node types"
```

---

### Task 2: Lexer — add `BACKSLASH`, `LET`, `EQUALS` tokens

**Files:**
- Modify: `lib/lexer.ml`
- Test: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write failing tests for new tokens**

Add to `test/test_compose_dsl.ml` after the existing lexer tests (before the `lexer_tests` list):

```ocaml
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
  (* "letter" should still lex as IDENT, not LET + "ter" *)
  let tokens = Lexer.tokenize "letter" in
  match (List.hd tokens).token with
  | Lexer.IDENT "letter" -> ()
  | _ -> Alcotest.fail "expected IDENT letter"
```

Register them in `lexer_tests`:
```ocaml
  ; "backslash token", `Quick, test_lex_backslash
  ; "let keyword", `Quick, test_lex_let_keyword
  ; "equals token", `Quick, test_lex_equals
  ; "let prefix in ident", `Quick, test_lex_let_in_ident
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dune test`
Expected: FAIL — `Lexer.BACKSLASH`, `Lexer.LET`, `Lexer.EQUALS` do not exist yet.

- [ ] **Step 3: Add new token variants**

In `lib/lexer.ml`, add to the `token` type:

```ocaml
  | BACKSLASH (** [\] *)
  | LET (** [let] keyword *)
  | EQUALS (** [=] *)
```

- [ ] **Step 4: Add lexer dispatch for `\` and `=`**

In `lib/lexer.ml`, in the `match c with` inside `tokenize`, add before the final catch-all:

```ocaml
      | '\\' -> advance (); tokens := { token = BACKSLASH; loc = { start = p; end_ = pos () } } :: !tokens
      | '=' -> advance (); tokens := { token = EQUALS; loc = { start = p; end_ = pos () } } :: !tokens
```

- [ ] **Step 5: Add `let` keyword recognition in `read_ident`**

In `lib/lexer.ml`, update `read_ident` to recognize `let`:

```ocaml
    let tok = match s with
      | "loop" -> LOOP
      | "let" -> LET
      | _ -> IDENT s
    in
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `dune test`
Expected: all tests pass, including the 4 new lexer tests.

- [ ] **Step 7: Commit**

```bash
git add lib/lexer.ml test/test_compose_dsl.ml
git commit -m "feat(lexer): add BACKSLASH, LET, EQUALS tokens"
```

---

### Task 3: Parser — lambda expressions

**Files:**
- Modify: `lib/parser.ml`
- Test: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write failing tests for lambda parsing**

Add to `test/test_compose_dsl.ml`:

```ocaml
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
```

Register in `parser_tests`:
```ocaml
  ; "lambda single param", `Quick, test_parse_lambda_single_param
  ; "lambda multi param", `Quick, test_parse_lambda_multi_param
  ; "lambda var in body", `Quick, test_parse_lambda_var_in_body
  ; "lambda in group", `Quick, test_parse_lambda_in_group
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dune test`
Expected: FAIL — parser doesn't handle `BACKSLASH` token yet.

- [ ] **Step 3: Add scope tracking to parser state**

In `lib/parser.ml`, update the `state` type and `make` function:

```ocaml
module StringSet = Set.Make(String)

type state = {
  mutable tokens : Lexer.located list;
  mutable last_loc : loc;
  mutable scope : StringSet.t;
}

let make tokens = { tokens; last_loc = dummy_loc; scope = StringSet.empty }
```

- [ ] **Step 4: Add `parse_lambda` function**

In `lib/parser.ml`, add `parse_lambda` to the `rec`/`and` group with `parse_seq_expr`:

```ocaml
and parse_lambda st start_loc =
  (* BACKSLASH already consumed *)
  let params = ref [] in
  let rec read_params () =
    let t = current st in
    match t.token with
    | Lexer.IDENT name ->
      advance st;
      params := name :: !params;
      let t2 = current st in
      (match t2.token with
       | Lexer.COMMA -> advance st; read_params ()
       | Lexer.ARROW -> advance st
       | _ -> raise (Parse_error (t2.loc.start, "expected ',' or '->' in lambda")))
    | _ -> raise (Parse_error (t.loc.start, "expected parameter name"))
  in
  read_params ();
  let param_list = List.rev !params in
  let old_scope = st.scope in
  st.scope <- List.fold_left (fun s p -> StringSet.add p s) st.scope param_list;
  let body = parse_seq_expr st in
  st.scope <- old_scope;
  mk_expr { start = start_loc; end_ = body.loc.end_ } (Lambda (param_list, body))
```

- [ ] **Step 5: Update `parse_term` to handle `BACKSLASH`**

In `lib/parser.ml`, add a case in `parse_term` before the final catch-all:

```ocaml
  | Lexer.BACKSLASH ->
    let start = t.loc.start in
    advance st;
    parse_lambda st start
```

- [ ] **Step 6: Update `parse_term` for `IDENT` — scope-aware Var vs Node**

In `lib/parser.ml`, update the `Lexer.IDENT name` case in `parse_term`. When an ident is in scope, emit `Var` instead of `Node`:

Replace the `Lexer.IDENT name` case with:

```ocaml
  | Lexer.IDENT name ->
    advance st;
    let in_scope = StringSet.mem name st.scope in
    let t_next = current st in
    (match t_next.token with
     | Lexer.LPAREN ->
       advance st;
       let t_peek = current st in
       (* Disambiguation: IDENT COLON → named args, else → positional *)
       let is_named = match t_peek.token with
         | Lexer.IDENT _ ->
           (match st.tokens with
            | _ :: { Lexer.token = Lexer.COLON; _ } :: _ -> true
            | _ -> false)
         | Lexer.RPAREN -> false
           (* Empty parens: out-of-scope → is_named=false → positional branch →
              App(Node(f), []) — slightly different from existing Node{args=[]} but
              the reducer catches it as "not a function". In-scope → App(Var(f), [])
              which the reducer also catches. Acceptable edge case. *)
         | _ -> false
       in
       if is_named then begin
         if in_scope then
           raise (Parse_error (t.loc.start, Printf.sprintf "cannot pass named args to variable '%s'" name));
         let args = parse_args st in
         expect st (fun tok -> tok = Lexer.RPAREN) "expected ')'";
         let rparen_end = st.last_loc.end_ in
         let comments = eat_comments st in
         let n = { name; args; comments } in
         let t2 = current st in
         (match t2.token with
          | Lexer.QUESTION ->
            advance st;
            mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (Question (QNode n))
          | _ ->
            mk_expr { start = t.loc.start; end_ = rparen_end } (Node n))
       end else begin
         (* Positional args — lambda application *)
         let args = ref [] in
         let rec read_positional () =
           let t_check = current st in
           match t_check.token with
           | Lexer.RPAREN -> ()
           | _ ->
             args := parse_seq_expr st :: !args;
             let t_check2 = current st in
             (match t_check2.token with
              | Lexer.COMMA -> advance st; read_positional ()
              | Lexer.RPAREN -> ()
              | _ -> raise (Parse_error (t_check2.loc.start, "expected ',' or ')'")))
         in
         read_positional ();
         expect st (fun tok -> tok = Lexer.RPAREN) "expected ')'";
         let fn_expr = if in_scope
           then mk_expr t.loc (Var name)
           else mk_expr t.loc (Node { name; args = []; comments = [] })
         in
         mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (App (fn_expr, List.rev !args))
       end
     | _ ->
       if in_scope then begin
         let ident_end = st.last_loc.end_ in
         let _ = eat_comments st in
         mk_expr { start = t.loc.start; end_ = ident_end } (Var name)
       end else begin
         let ident_end = st.last_loc.end_ in
         let comments = eat_comments st in
         let n = { name; args = []; comments } in
         let t2 = current st in
         (match t2.token with
          | Lexer.QUESTION ->
            advance st;
            mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (Question (QNode n))
          | _ ->
            mk_expr { start = t.loc.start; end_ = ident_end } (Node n))
       end)
```

**Note on disambiguation:** The `is_named` check peeks at the second token in `st.tokens` (which is the token list *after* the peeked IDENT). Since `t_peek` was read via `current st` (which reads `st.tokens` head), the *next* token after it is `List.tl st.tokens |> List.hd`. However, `st.tokens` still points at `t_peek :: rest`, so we check `rest` (i.e., `st.tokens` tail) for `COLON`. The match `_ :: { token = COLON; _ } :: _` matches against `st.tokens` starting from `t_peek`, so the second element is what follows the peeked IDENT.

- [ ] **Step 7: Run tests to verify they pass**

Run: `dune test`
Expected: all tests pass, including the 4 new lambda tests.

- [ ] **Step 8: Commit**

```bash
git add lib/parser.ml test/test_compose_dsl.ml
git commit -m "feat(parser): add lambda expression parsing with scope tracking"
```

---

### Task 4: Parser — let bindings

**Files:**
- Modify: `lib/parser.ml`
- Test: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write failing tests for let binding**

Add to `test/test_compose_dsl.ml`:

```ocaml
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
  (* b references a from earlier let *)
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
  (* Backward compat: no let bindings → same as before *)
  let tokens = Lexer.tokenize "a >>> b" in
  let ast = Parser.parse_program tokens in
  match ast.desc with
  | Seq _ -> ()
  | _ -> Alcotest.fail "expected Seq"
```

Register in `parser_tests`:
```ocaml
  ; "let simple", `Quick, test_parse_let_simple
  ; "let multiple", `Quick, test_parse_let_multiple
  ; "let with lambda", `Quick, test_parse_let_with_lambda
  ; "let scope", `Quick, test_parse_let_scope
  ; "no let is program", `Quick, test_parse_no_let_is_program
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dune test`
Expected: FAIL — `Parser.parse_program` does not exist yet.

- [ ] **Step 3: Add `parse_program` function**

In `lib/parser.ml`, add a new public entry point:

```ocaml
let parse_program tokens =
  let st = make tokens in
  let rec read_lets () =
    let _ = eat_comments st in
    let t = current st in
    match t.token with
    | Lexer.LET ->
      advance st;
      let t_name = current st in
      let name = match t_name.token with
        | Lexer.IDENT s -> advance st; s
        | _ -> raise (Parse_error (t_name.loc.start, "expected identifier after 'let'"))
      in
      expect st (fun tok -> tok = Lexer.EQUALS) "expected '=' after let binding name";
      if StringSet.mem name st.scope then
        Printf.eprintf "warning at %d:%d: '%s' shadows previous binding\n"
          t_name.loc.start.line t_name.loc.start.col name;
      let old_scope = st.scope in
      let value = parse_seq_expr st in
      (* Name is in scope for subsequent bindings and body *)
      st.scope <- StringSet.add name old_scope;
      let rest = read_lets () in
      mk_expr { start = t.loc.start; end_ = rest.loc.end_ } (Let (name, value, rest))
    | _ ->
      let expr = parse_seq_expr st in
      let t_end = current st in
      (match t_end.token with
       | Lexer.EOF -> ()
       | _ -> raise (Parse_error (t_end.loc.start, "expected end of input")));
      expr
  in
  read_lets ()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dune test`
Expected: all tests pass, including the 5 new let binding tests.

- [ ] **Step 5: Commit**

```bash
git add lib/parser.ml test/test_compose_dsl.ml
git commit -m "feat(parser): add let binding and parse_program entry point"
```

---

### Task 5: Reducer — beta reduction module

**Files:**
- Create: `lib/reducer.ml`
- Test: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write failing tests for reducer**

Add to `test/test_compose_dsl.ml`:

```ocaml
(* Helper that parses with parse_program and reduces *)
let reduce_ok input =
  let tokens = Lexer.tokenize input in
  let ast = Parser.parse_program tokens in
  Reducer.reduce ast

let reduce_fails input =
  match reduce_ok input with
  | _ -> Alcotest.fail "expected reduce error"
  | exception Reducer.Reduce_error _ -> ()

let test_reduce_no_lambda () =
  (* Plain Arrow pipeline passes through unchanged *)
  let ast = reduce_ok "a >>> b" in
  Alcotest.(check string) "printed"
    "Seq(Node(\"a\", [], []), Node(\"b\", [], []))"
    (Printer.to_string ast)

let test_reduce_let_simple () =
  let ast = reduce_ok "let f = a >>> b\nf" in
  Alcotest.(check string) "printed"
    "Seq(Node(\"a\", [], []), Node(\"b\", [], []))"
    (Printer.to_string ast)

let test_reduce_lambda_apply () =
  let ast = reduce_ok "let f = \\ x -> x >>> a\nf(b)" in
  Alcotest.(check string) "printed"
    "Seq(Node(\"b\", [], []), Node(\"a\", [], []))"
    (Printer.to_string ast)

let test_reduce_lambda_multi_param () =
  let ast = reduce_ok "let f = \\ x, y -> x >>> y\nf(a, b)" in
  Alcotest.(check string) "printed"
    "Seq(Node(\"a\", [], []), Node(\"b\", [], []))"
    (Printer.to_string ast)

let test_reduce_let_chain () =
  let ast = reduce_ok "let a = x\nlet b = a\nb" in
  Alcotest.(check string) "printed"
    "Node(\"x\", [], [])"
    (Printer.to_string ast)

let test_reduce_nested_application () =
  let ast = reduce_ok "let f = \\ x -> x\nlet g = \\ y -> f(y)\ng(a)" in
  Alcotest.(check string) "printed"
    "Node(\"a\", [], [])"
    (Printer.to_string ast)

let test_reduce_free_variable () =
  reduce_fails "let f = \\ x -> y\nf(a)"

let test_reduce_arity_mismatch () =
  reduce_fails "let f = \\ x, y -> x\nf(a)"

let test_reduce_non_function_apply () =
  reduce_fails "let f = a\nf(b)"
```

Register in a new `reducer_tests` list:
```ocaml
let reducer_tests =
  [ "no lambda passthrough", `Quick, test_reduce_no_lambda
  ; "let simple", `Quick, test_reduce_let_simple
  ; "lambda apply", `Quick, test_reduce_lambda_apply
  ; "lambda multi param", `Quick, test_reduce_lambda_multi_param
  ; "let chain", `Quick, test_reduce_let_chain
  ; "nested application", `Quick, test_reduce_nested_application
  ; "free variable error", `Quick, test_reduce_free_variable
  ; "arity mismatch error", `Quick, test_reduce_arity_mismatch
  ; "non-function apply error", `Quick, test_reduce_non_function_apply
  ]
```

And add to `Alcotest.run`:
```ocaml
    ; "Reducer", reducer_tests
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dune test`
Expected: FAIL — `Reducer` module does not exist yet.

- [ ] **Step 3: Create `lib/reducer.ml`**

```ocaml
open Ast

exception Reduce_error of pos * string

(* Desugar Let into App(Lambda) *)
let rec desugar (e : expr) : expr =
  match e.desc with
  | Let (name, value, body) ->
    let value' = desugar value in
    let body' = desugar body in
    { e with desc = App ({ e with desc = Lambda ([name], body') }, [value']) }
  | Seq (a, b) -> { e with desc = Seq (desugar a, desugar b) }
  | Par (a, b) -> { e with desc = Par (desugar a, desugar b) }
  | Fanout (a, b) -> { e with desc = Fanout (desugar a, desugar b) }
  | Alt (a, b) -> { e with desc = Alt (desugar a, desugar b) }
  | Loop body -> { e with desc = Loop (desugar body) }
  | Group inner -> { e with desc = Group (desugar inner) }
  | Lambda (params, body) -> { e with desc = Lambda (params, desugar body) }
  | App (fn, args) -> { e with desc = App (desugar fn, List.map desugar args) }
  | Node _ | Var _ | Question _ -> e

(* Substitute Var(name) with replacement in expr *)
let rec substitute (name : string) (replacement : expr) (e : expr) : expr =
  match e.desc with
  | Var v when v = name -> replacement
  | Var _ -> e
  | Node _ | Question _ -> e
  | Seq (a, b) -> { e with desc = Seq (substitute name replacement a, substitute name replacement b) }
  | Par (a, b) -> { e with desc = Par (substitute name replacement a, substitute name replacement b) }
  | Fanout (a, b) -> { e with desc = Fanout (substitute name replacement a, substitute name replacement b) }
  | Alt (a, b) -> { e with desc = Alt (substitute name replacement a, substitute name replacement b) }
  | Loop body -> { e with desc = Loop (substitute name replacement body) }
  | Group inner -> { e with desc = Group (substitute name replacement inner) }
  | Lambda (params, body) ->
    (* Don't substitute if name is shadowed by a lambda param *)
    if List.mem name params then e
    else { e with desc = Lambda (params, substitute name replacement body) }
  | App (fn, args) ->
    { e with desc = App (substitute name replacement fn, List.map (substitute name replacement) args) }
  | Let (n, v, b) ->
    let v' = substitute name replacement v in
    if n = name then { e with desc = Let (n, v', b) }  (* shadowed *)
    else { e with desc = Let (n, v', substitute name replacement b) }

(* Beta reduce: App(Lambda(params, body), args) → substitute params with args in body *)
let rec beta_reduce (e : expr) : expr =
  match e.desc with
  | App (fn, args) ->
    let fn' = beta_reduce fn in
    let args' = List.map beta_reduce args in
    (match fn'.desc with
     | Lambda (params, body) ->
       let n_params = List.length params in
       let n_args = List.length args' in
       if n_params <> n_args then
         raise (Reduce_error (e.loc.start,
           Printf.sprintf "arity mismatch: expected %d arguments but got %d" n_params n_args));
       let result = List.fold_left2
         (fun acc param arg -> substitute param arg acc)
         body params args'
       in
       beta_reduce result  (* reduce again in case substitution created new redexes *)
     | Node n ->
       raise (Reduce_error (e.loc.start,
         Printf.sprintf "'%s' is not a function and cannot be applied" n.name))
     | Var v ->
       raise (Reduce_error (e.loc.start,
         Printf.sprintf "undefined variable '%s'" v))
     | _ ->
       raise (Reduce_error (e.loc.start, "expression is not a function and cannot be applied")))
  | Seq (a, b) -> { e with desc = Seq (beta_reduce a, beta_reduce b) }
  | Par (a, b) -> { e with desc = Par (beta_reduce a, beta_reduce b) }
  | Fanout (a, b) -> { e with desc = Fanout (beta_reduce a, beta_reduce b) }
  | Alt (a, b) -> { e with desc = Alt (beta_reduce a, beta_reduce b) }
  | Loop body -> { e with desc = Loop (beta_reduce body) }
  | Group inner -> { e with desc = Group (beta_reduce inner) }
  | Lambda _ -> e  (* unapplied lambda — will be caught by verify *)
  | Node _ | Var _ | Question _ | Let _ -> e

(* Verify no unreduced nodes remain *)
let rec verify (e : expr) : unit =
  match e.desc with
  | Lambda _ ->
    raise (Reduce_error (e.loc.start, "lambda expression not fully applied"))
  | Var v ->
    raise (Reduce_error (e.loc.start,
      Printf.sprintf "undefined variable '%s'" v))
  | App _ ->
    raise (Reduce_error (e.loc.start, "unreduced application"))
  | Let _ ->
    raise (Reduce_error (e.loc.start, "unreduced let binding"))
  | Seq (a, b) | Par (a, b) | Fanout (a, b) | Alt (a, b) -> verify a; verify b
  | Loop body | Group body -> verify body
  | Node _ | Question _ -> ()

let reduce (e : expr) : expr =
  let e = desugar e in
  let e = beta_reduce e in
  verify e;
  e
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dune test`
Expected: all tests pass, including the 9 new reducer tests.

- [ ] **Step 5: Commit**

```bash
git add lib/reducer.ml test/test_compose_dsl.ml
git commit -m "feat(reducer): add beta reduction module for lambda/let desugaring"
```

---

### Task 6: Wire reducer into main pipeline

**Files:**
- Modify: `bin/main.ml`
- Test: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write an integration test**

Add to `test/test_compose_dsl.ml`:

```ocaml
(* Integration: full pipeline parse_program >>> reduce >>> check *)
let test_integration_let_and_check () =
  let input = "let f = \\ x -> x >>> a\nf(b)" in
  let tokens = Lexer.tokenize input in
  let ast = Parser.parse_program tokens in
  let reduced = Reducer.reduce ast in
  let result = Checker.check reduced in
  Alcotest.(check int) "no errors" 0 (List.length result.Checker.errors)

let test_integration_backward_compat () =
  let input = "a >>> b *** c" in
  let tokens = Lexer.tokenize input in
  let ast = Parser.parse_program tokens in
  let reduced = Reducer.reduce ast in
  let result = Checker.check reduced in
  Alcotest.(check int) "no errors" 0 (List.length result.Checker.errors)
```

Add a new test suite:
```ocaml
let integration_tests =
  [ "let and check", `Quick, test_integration_let_and_check
  ; "backward compat", `Quick, test_integration_backward_compat
  ]
```

Register in `Alcotest.run`:
```ocaml
    ; "Integration", integration_tests
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `dune test`
Expected: PASS (these use the library API directly).

- [ ] **Step 3: Update `bin/main.ml` to use `parse_program` and `Reducer.reduce`**

In `bin/main.ml`, replace the parse-and-check pipeline. Change:

```ocaml
    match Compose_dsl.Parser.parse tokens with
    | exception Compose_dsl.Parser.Parse_error (pos, msg) ->
      Printf.eprintf "parse error at %d:%d: %s\n" pos.line pos.col msg;
      exit 1
    | ast ->
      let result = Compose_dsl.Checker.check ast in
```

To:

```ocaml
    match Compose_dsl.Parser.parse_program tokens with
    | exception Compose_dsl.Parser.Parse_error (pos, msg) ->
      Printf.eprintf "parse error at %d:%d: %s\n" pos.line pos.col msg;
      exit 1
    | ast ->
      let ast = match Compose_dsl.Reducer.reduce ast with
        | reduced -> reduced
        | exception Compose_dsl.Reducer.Reduce_error (pos, msg) ->
          Printf.eprintf "reduce error at %d:%d: %s\n" pos.line pos.col msg;
          exit 1
      in
      let result = Compose_dsl.Checker.check ast in
```

- [ ] **Step 4: Build and test**

Run: `dune build && dune test`
Expected: all tests pass.

- [ ] **Step 5: Manual smoke test**

```bash
echo 'let f = \x -> x >>> a\nf(b)' | dune exec ocaml-compose-dsl
```

Expected output: `Seq(Node("b", [], []), Node("a", [], []))`

```bash
echo 'a >>> b' | dune exec ocaml-compose-dsl
```

Expected output: `Seq(Node("a", [], []), Node("b", [], []))` (backward compat).

- [ ] **Step 6: Commit**

```bash
git add bin/main.ml test/test_compose_dsl.ml
git commit -m "feat(main): wire reducer into parse >>> reduce >>> check pipeline"
```

---

### Task 7: Printer — new node types

**Files:**
- Test: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write tests for printer output of new nodes**

Add to `test/test_compose_dsl.ml`:

```ocaml
let test_print_lambda () =
  let ast = parse_ok "\\ x -> a" in
  Alcotest.(check string) "printed"
    "Lambda(x, Node(\"a\", [], []))"
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
  (* Before reduction, the body is App *)
  match ast.desc with
  | Let (_, _, body) ->
    let s = Printer.to_string body in
    Alcotest.(check bool) "starts with App" true
      (String.length s >= 3 && String.sub s 0 3 = "App")
  | _ -> Alcotest.fail "expected Let"

let test_print_let () =
  let tokens = Lexer.tokenize "let f = a\nf" in
  let ast = Parser.parse_program tokens in
  let s = Printer.to_string ast in
  Alcotest.(check bool) "starts with Let" true
    (String.length s >= 3 && String.sub s 0 3 = "Let")
```

Register in `printer_tests`:
```ocaml
  ; "lambda", `Quick, test_print_lambda
  ; "var", `Quick, test_print_var
  ; "app", `Quick, test_print_app
  ; "let", `Quick, test_print_let
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `dune test`
Expected: PASS (printer was updated in Task 1).

- [ ] **Step 3: Commit**

```bash
git add test/test_compose_dsl.ml
git commit -m "test(printer): add tests for Lambda, Var, App, Let output"
```

---

### Task 8: Update README EBNF

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the EBNF grammar section**

In `README.md`, update the grammar. Add before the existing `pipeline` rule:

```ebnf
program = { let_binding } , pipeline ;

let_binding = "let" , ident , "=" , seq_expr ;

lambda  = "\" , ident , { "," , ident } , "->" , seq_expr ;
```

Update the `pipeline` rule (unchanged but now referenced by `program`):
```ebnf
pipeline = seq_expr ;
```

Update `call_args` in the node rule:
```ebnf
node     = ident , [ "(" , [ call_args ] , ")" ] ;

call_args = named_args | positional_args ;

named_args      = arg , { "," , arg } ;
positional_args = seq_expr , { "," , seq_expr } ;
```

Add `lambda` to `term`:
```ebnf
term     = node
         | "loop" , "(" , seq_expr , ")"
         | "(" , seq_expr , ")"
         | question_term
         | lambda
         ;
```

- [ ] **Step 2: Add a Lambda/Let example section**

Add after the existing examples in README.md:

```markdown
### Lambda and Let Bindings

```
let greet = \name -> hello(to: name) >>> respond
greet(alice) >>> greet(bob)
```

```
let review = \trigger, fix ->
  loop(trigger >>> (pass ||| fix))

let phase1 = gather >>> review(check?, rework)
let phase2 = build >>> review(test?, fix)

phase1 >>> phase2
```

Lambdas and let bindings are reduced to pure Arrow pipelines before structural checking. They provide abstraction without adding runtime semantics.
```

- [ ] **Step 3: Build and test**

Run: `dune build && dune test`
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: update EBNF grammar and examples for lambda/let bindings"
```

---

### Task 9: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update the library pipeline description**

In `CLAUDE.md`, update the pipeline description to include the reducer:

```arrow
Lexer :: String -> Token
  >>> Parser :: Token -> Ast
  >>> Reducer :: Ast -> Ast   -- desugar let, beta reduce lambda
  >>> Checker :: Ast -> Result
```

- [ ] **Step 2: Update the AST module description**

Add `Lambda`, `Var`, `App`, `Let` to the `Ast` description. Mention that these are reduced away before checking.

- [ ] **Step 3: Build and test**

Run: `dune build && dune test`
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for lambda/let binding and reducer module"
```

---

### Task 10: Edge case tests

**Files:**
- Test: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write edge case tests**

```ocaml
(* Lambda with type annotations in body *)
let test_reduce_lambda_with_type_ann () =
  let ast = reduce_ok "let f = \\ x -> x :: A -> B\nf(a)" in
  Alcotest.(check string) "printed"
    "TypeAnn(Node(\"a\", [], []), \"A\", \"B\")"
    (Printer.to_string ast)

(* Lambda with Arrow operators in args *)
let test_reduce_lambda_complex_args () =
  let ast = reduce_ok "let f = \\ x, y -> x >>> y\nf(a >>> b, c)" in
  Alcotest.(check string) "printed"
    "Seq(Seq(Node(\"a\", [], []), Node(\"b\", [], [])), Node(\"c\", [], []))"
    (Printer.to_string ast)

(* Unicode in lambda params *)
let test_parse_lambda_unicode_param () =
  let ast = parse_ok "\\ 觸發 -> 觸發 >>> 完成" in
  match ast.desc with
  | Lambda (["觸發"], _) -> ()
  | _ -> Alcotest.fail "expected Lambda with unicode param"

(* Let binding with unicode name *)
let test_parse_let_unicode_name () =
  let tokens = Lexer.tokenize "let 審查 = a >>> b\n審查" in
  let ast = Parser.parse_program tokens in
  match ast.desc with
  | Let ("審查", _, _) -> ()
  | _ -> Alcotest.fail "expected Let with unicode name"

(* Empty pipeline body after let *)
let test_parse_let_error_no_body () =
  match Lexer.tokenize "let f = a" |> Parser.parse_program with
  | _ -> Alcotest.fail "expected parse error (no body after let)"
  | exception Parser.Parse_error _ -> ()

(* Lambda with zero params — should be parse error *)
let test_parse_lambda_no_params () =
  match Lexer.tokenize "\\ -> a" |> Parser.parse with
  | _ -> Alcotest.fail "expected parse error"
  | exception Parser.Parse_error _ -> ()

(* Positional args on undefined name — reduce error *)
let test_reduce_positional_on_undefined () =
  reduce_fails "f(a, b)"

(* let keyword can no longer be used as a node name *)
let test_parse_let_keyword_not_node () =
  match Lexer.tokenize "let >>> a" |> Parser.parse with
  | _ -> Alcotest.fail "expected parse error (let is now a keyword)"
  | exception Parser.Parse_error _ -> ()

(* Comments inside lambda body *)
let test_parse_lambda_with_comment () =
  let ast = parse_ok "\\ x -> x -- hello\n>>> a" in
  match ast.desc with
  | Lambda _ -> ()
  | _ -> Alcotest.fail "expected Lambda"
```

Register:
```ocaml
let edge_case_tests =
  [ "lambda with type ann", `Quick, test_reduce_lambda_with_type_ann
  ; "lambda complex args", `Quick, test_reduce_lambda_complex_args
  ; "lambda unicode param", `Quick, test_parse_lambda_unicode_param
  ; "let unicode name", `Quick, test_parse_let_unicode_name
  ; "let error no body", `Quick, test_parse_let_error_no_body
  ; "lambda no params error", `Quick, test_parse_lambda_no_params
  ; "positional on undefined", `Quick, test_reduce_positional_on_undefined
  ; "let keyword not node", `Quick, test_parse_let_keyword_not_node
  ; "lambda with comment", `Quick, test_parse_lambda_with_comment
  ]
```

Add to `Alcotest.run`:
```ocaml
    ; "Edge cases", edge_case_tests
```

- [ ] **Step 2: Run tests — some may fail, iterate**

Run: `dune test`
Fix any failures. The `let_error_no_body` test verifies that `let f = a` without a subsequent expression is a parse error (the parser should hit EOF when expecting `seq_expr` for the body).

- [ ] **Step 3: Commit**

```bash
git add test/test_compose_dsl.ml
git commit -m "test: add edge case tests for lambda/let features"
```
