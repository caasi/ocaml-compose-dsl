# Unit Value (`()`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `()` as a unit value expression and type annotation token, eliminating zero-arg application from the AST.

**Architecture:** Add `Unit` variant to `expr_desc` as a leaf node. Parser produces `Unit` when it sees `LPAREN RPAREN` (via one-token lookahead). `noop()` becomes `App(Var "noop", [Positional Unit])` instead of `App(Var "noop", [])`. Type annotations accept `()` as `"()"` string. All downstream modules add mechanical `Unit` arms alongside existing `StringLit` handling.

**Tech Stack:** OCaml 5.1, Alcotest, dune 3.0

**Spec:** `docs/superpowers/specs/2026-03-28-unit-value-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/ast.ml` | Modify | Add `Unit` to `expr_desc` |
| `lib/parser.ml` | Modify | `parse_term` (LPAREN lookahead), `parse_call_args` (empty→Unit), `parse_type_ann` (accept `()`), `attach_comments_right` (Unit arm) |
| `lib/reducer.ml` | Modify | Add `Unit` arms to `free_vars`, `desugar`, `substitute`, `beta_reduce`, `verify` |
| `lib/checker.ml` | Modify | Add `Unit` arms to `normalize`, `scan_questions`, `go` |
| `lib/printer.ml` | Modify | Add `Unit` arm to `to_string` |
| `README.md` | Modify | Update EBNF: `term` adds `"(" , ")"`, `type_name` production |
| `test/test_parser.ml` | Modify | Update `test_parse_node_empty_parens`, add 8 new tests |
| `test/test_integration.ml` | Modify | Update `test_parse_empty_parens_app` |
| `test/test_reducer.ml` | Modify | Update `test_reduce_empty_application_arity`, add 1 new test |
| `test/test_checker.ml` | Modify | Add 1 new test |
| `test/test_printer.ml` | Modify | Add 1 new test |

---

## Task 1: AST + Printer + Downstream Leaf Arms

Add `Unit` to the AST and make all modules compile. TDD: write printer test first.

**Files:**
- Modify: `lib/ast.ml:15` (`expr_desc` type)
- Modify: `lib/printer.ml:19-36` (`to_string`)
- Modify: `lib/reducer.ml` (5 functions)
- Modify: `lib/checker.ml` (3 functions)
- Modify: `lib/parser.ml:109-120` (`attach_comments_right`)
- Modify: `test/test_printer.ml`

- [ ] **Step 1: Write the failing printer test**

Add to `test/test_printer.ml` before the `let tests` list:

```ocaml
let test_print_unit () =
  let ast = { Ast.loc = { start = { line = 1; col = 1 }; end_ = { line = 1; col = 2 } };
              desc = Ast.Unit; type_ann = None } in
  Alcotest.(check string) "unit" "Unit" (Printer.to_string ast)
```

Register in the `tests` list:

```ocaml
  ; "unit", `Quick, test_print_unit
```

- [ ] **Step 2: Run test to verify it fails**

```bash
dune test 2>&1 | head --lines=20
```

Expected: compilation error — `Unit` is not a variant of `expr_desc`.

- [ ] **Step 3: Add `Unit` to `expr_desc` in `lib/ast.ml`**

Add `Unit` as the first variant, before `Var`:

```ocaml
and expr_desc =
  | Unit                             (** () — unit value *)
  | Var of string                    (** variable reference, bound or free *)
```

- [ ] **Step 4: Add `Unit` arm to `lib/printer.ml`**

In `to_string`, add after `let base = match e.desc with`:

```ocaml
    | Unit -> "Unit"
```

- [ ] **Step 5: Add `Unit` arm to `attach_comments_right` in `lib/parser.ml:109-120`**

Add `Unit` to the leaf-node line:

```ocaml
    | Var _ | App _ | Lambda _ | Let _ | Unit -> e
```

- [ ] **Step 6: Add `Unit` arms to `lib/reducer.ml`**

Five functions need `Unit` alongside existing `StringLit` handling:

In `free_vars` (line 11), add `| Unit` to the `StringLit` arm:

```ocaml
  | StringLit _ | Unit -> StringSet.empty
```

In `desugar` (line 44), add `| Unit` to the leaf line:

```ocaml
  | Var _ | StringLit _ | Unit -> e
```

In `substitute` (line 58), add `| Unit` to the existing leaf arm (already after the `Var v when v = name` guard):

```ocaml
  | Var _ | StringLit _ | Unit -> e
```

In `beta_reduce` (line 141), update the leaf line:

```ocaml
  | Var _ | StringLit _ | Let _ | Unit -> e
```

In `verify` (line 173), add `| Unit` to the `StringLit` arm:

```ocaml
  | StringLit _ | Unit -> ()
```

- [ ] **Step 7: Add `Unit` arms to `lib/checker.ml`**

In `normalize` (line 14), update the leaf line:

```ocaml
  | Var _ | StringLit _ | Unit -> e
```

In `scan_questions` (line 30), update the leaf line:

```ocaml
  | Var _ | StringLit _ | Unit -> counter
```

In `go` (line 54-55), add `| Unit` to the `StringLit` arm for consistency with other modules:

```ocaml
    | Var _ -> ()
    | StringLit _ | Unit -> ()
```

In `check_question_balance` / `tail_has_question` — these use wildcards already, no change needed.

- [ ] **Step 8: Verify the build compiles and printer test passes**

```bash
dune test
```

Expected: all existing tests pass, new printer test passes.

- [ ] **Step 9: Commit**

```bash
git add lib/ast.ml lib/printer.ml lib/parser.ml lib/reducer.ml lib/checker.ml test/test_printer.ml
git commit -m "feat(ast): add Unit variant to expr_desc with downstream support"
```

---

## Task 2: Parser — `parse_term` Unit Production

Make `()` parse as `Unit` expression (standalone and with `?`).

**Files:**
- Modify: `lib/parser.ml:252-256` (`parse_term` LPAREN branch)
- Modify: `test/test_parser.ml`

- [ ] **Step 1: Write the failing tests**

Add to `test/test_parser.ml` before the `let tests` list:

```ocaml
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
```

Register in the `tests` list:

```ocaml
  ; "unit standalone", `Quick, test_parse_unit_standalone
  ; "unit in seq", `Quick, test_parse_unit_in_seq
  ; "unit nested", `Quick, test_parse_unit_nested
  ; "unit question", `Quick, test_parse_unit_question
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
dune exec test/main.exe -- test Parser 2>&1 | tail --lines=10
```

Expected: 4 new tests FAIL (currently `()` triggers parse error or produces `Group`).

- [ ] **Step 3: Implement `parse_term` LPAREN branch change**

Replace `lib/parser.ml:252-256`:

```ocaml
  | Lexer.LPAREN ->
    advance st;
    let t_next = current st in
    (match t_next.token with
     | Lexer.RPAREN ->
       advance st;
       let unit_expr = mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } Unit in
       let _ = eat_comments st in
       let t2 = current st in
       (match t2.token with
        | Lexer.QUESTION ->
          advance st;
          mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (Question unit_expr)
        | _ -> unit_expr)
     | _ ->
       let inner = parse_program_inner st in
       expect st (fun tok -> tok = Lexer.RPAREN) "expected ')'";
       mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (Group inner))
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
dune exec test/main.exe -- test Parser
```

Expected: all Parser tests pass including 4 new ones.

- [ ] **Step 5: Also add a lambda-returns-unit test**

Add to `test/test_parser.ml` before the `let edge_case_tests` list:

```ocaml
let test_parse_lambda_returns_unit () =
  match desc_of "\\ x -> ()" with
  | Ast.Lambda (["x"], { desc = Ast.Unit; _ }) -> ()
  | _ -> Alcotest.fail "expected Lambda([x], Unit)"
```

Register in `edge_case_tests`:

```ocaml
  ; "lambda returns unit", `Quick, test_parse_lambda_returns_unit
```

- [ ] **Step 6: Run tests**

```bash
dune test
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/parser.ml test/test_parser.ml
git commit -m "feat(parser): parse () as Unit expression with optional trailing ?"
```

---

## Task 3: Parser — Empty Call Args Become `[Positional Unit]`

Change `noop()` from `App(Var "noop", [])` to `App(Var "noop", [Positional Unit])`.

**Files:**
- Modify: `lib/parser.ml:86-107` (`parse_call_args`)
- Modify: `test/test_parser.ml:16-19` (`test_parse_node_empty_parens`)
- Modify: `test/test_integration.ml:51-54` (`test_parse_empty_parens_app`)
- Modify: `test/test_reducer.ml:118-123` (`test_reduce_empty_application_arity`)

- [ ] **Step 1: Update `test_parse_node_empty_parens` to expect Unit**

Replace `test/test_parser.ml:16-19`:

```ocaml
let test_parse_node_empty_parens () =
  match desc_of "noop()" with
  | Ast.App ({ desc = Ast.Var "noop"; _ }, [Positional { desc = Ast.Unit; _ }]) -> ()
  | _ -> Alcotest.fail "expected App(Var noop, [Positional Unit])"
```

- [ ] **Step 2: Update `test_parse_empty_parens_app` in integration**

Replace `test/test_integration.ml:51-54`:

```ocaml
let test_parse_empty_parens_app () =
  match desc_of "noop()" with
  | App ({ desc = Var "noop"; _ }, [Positional { desc = Unit; _ }]) -> ()
  | _ -> Alcotest.fail "expected App(Var noop, [Positional Unit])"
```

- [ ] **Step 3: Update `test_reduce_empty_application_arity`**

Replace `test/test_reducer.ml:118-123`:

```ocaml
(* Empty application f() — now applies Unit, so identity returns Unit *)
let test_reduce_empty_application_arity () =
  let ast = reduce_ok "let f = \\ x -> x in f()" in
  match ast.desc with
  | Ast.Unit -> ()
  | _ -> Alcotest.fail "expected Unit (identity applied to unit)"
```

- [ ] **Step 4: Run tests to verify they fail**

```bash
dune test 2>&1 | tail --lines=20
```

Expected: the 3 updated tests FAIL (parser still produces empty args `[]`).

- [ ] **Step 5: Implement `parse_call_args` change**

In `lib/parser.ml`, modify `parse_call_args` (line 86-107). Change the `RPAREN` match inside `go` to produce a Unit arg when args list is still empty:

Replace:

```ocaml
and parse_call_args st =
  let args = ref [] in
  let rec go () =
    let t = current st in
    match t.token with
    | Lexer.RPAREN -> ()
    | _ ->
```

With:

```ocaml
and parse_call_args st =
  let t_start = current st in
  let args = ref [] in
  let rec go () =
    let t = current st in
    match t.token with
    | Lexer.RPAREN ->
      if !args = [] then
        args := [Positional (mk_expr { start = t_start.loc.start; end_ = t.loc.start } Unit)]
    | _ ->
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
dune test
```

Expected: all tests pass.

- [ ] **Step 7: Add a reducer test for unit passthrough**

Add to `test/test_reducer.ml` before `let tests`:

```ocaml
let test_reduce_unit_passthrough () =
  let ast = reduce_ok "()" in
  match ast.desc with
  | Ast.Unit -> ()
  | _ -> Alcotest.fail "expected Unit to survive reduction"
```

Register in `tests`:

```ocaml
  ; "unit passthrough", `Quick, test_reduce_unit_passthrough
```

- [ ] **Step 8: Run tests**

```bash
dune test
```

Expected: all tests pass.

- [ ] **Step 9: Commit**

```bash
git add lib/parser.ml test/test_parser.ml test/test_integration.ml test/test_reducer.ml
git commit -m "feat(parser): empty call args produce [Positional Unit], eliminating zero-arg application"
```

---

## Task 4: Parser — Type Annotation `()`

Support `()` in type annotations: `:: () -> Server`, `:: Status -> ()`.

**Files:**
- Modify: `lib/parser.ml:122-139` (`parse_type_ann`)
- Modify: `test/test_parser.ml`

- [ ] **Step 1: Write the failing tests**

Add to `test/test_parser.ml` before `let tests`:

```ocaml
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
```

Register in `tests`:

```ocaml
  ; "type ann unit input", `Quick, test_parse_unit_type_ann_input
  ; "type ann unit output", `Quick, test_parse_unit_type_ann_output
  ; "type ann unit both", `Quick, test_parse_unit_type_ann_both
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
dune exec test/main.exe -- test Parser 2>&1 | tail --lines=10
```

Expected: 3 new tests FAIL (parser rejects `()` in type annotation position).

- [ ] **Step 3: Implement `parse_type_ann` change**

Replace `lib/parser.ml:122-139` with a version that accepts `LPAREN RPAREN` as an alternative to `IDENT` in both input and output positions:

```ocaml
and parse_type_name st =
  let t = current st in
  match t.token with
  | Lexer.IDENT name -> advance st; name
  | Lexer.LPAREN ->
    advance st;
    expect st (fun tok -> tok = Lexer.RPAREN) "expected ')' in unit type '()'";
    "()"
  | _ -> raise (Parse_error (t.loc.start, "expected type name or '()' after '::'"))

and parse_type_ann st =
  let t = current st in
  match t.token with
  | Lexer.DOUBLE_COLON ->
    advance st;
    let input = parse_type_name st in
    expect st (fun tok -> tok = Lexer.ARROW) "expected '->' in type annotation";
    let output = parse_type_name st in
    Some { input; output }
  | _ -> None
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
dune test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/parser.ml test/test_parser.ml
git commit -m "feat(parser): accept () in type annotations as unit type"
```

---

## Task 5: Checker Test + EBNF Update

Add checker test and update README EBNF.

**Files:**
- Modify: `test/test_checker.ml`
- Modify: `README.md:36-45`

- [ ] **Step 1: Write checker test**

Add to `test/test_checker.ml` before `let tests`:

```ocaml
let test_check_unit_no_warnings () =
  let result = Checker.check (parse_ok "()") in
  Alcotest.(check int) "no warnings" 0 (List.length result.Checker.warnings)
```

Register in `tests`:

```ocaml
  ; "unit no warnings", `Quick, test_check_unit_no_warnings
```

- [ ] **Step 2: Run test to verify it passes**

```bash
dune exec test/main.exe -- test Checker
```

Expected: PASS (Unit arms already added in Task 1).

- [ ] **Step 3: Update EBNF in `README.md`**

Replace `README.md:36-45`:

```ebnf
type_expr   = type_name , "->" , type_name ;
type_name   = ident | "(" , ")" ;

term     = ident , [ "(" , [ call_args ] , ")" ] , [ "?" ]
                                                    (* ident with optional args and question *)
         | string , [ "?" ]                        (* string literal, optionally question;
                                                      AST represents both as Question(expr) *)
         | "(" , ")" , [ "?" ]                     (* unit value, with optional question *)
         | "loop" , "(" , seq_expr , ")"            (* feedback loop *)
         | "(" , program , ")"                     (* grouping — disambiguation: LPAREN then
                                                      peek; if RPAREN → unit, else → group *)
         | lambda
         ;
```

- [ ] **Step 4: Verify CLAUDE.md literate mode still works**

```bash
dune exec ocaml-compose-dsl -- --literate CLAUDE.md
```

Expected: exits 0, no errors.

- [ ] **Step 5: Run full test suite**

```bash
dune test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add test/test_checker.ml README.md
git commit -m "feat: add unit checker test and update EBNF grammar"
```

---

## Task 6: Final Verification

**Files:**
- None (verification only)

- [ ] **Step 1: Run full test suite**

```bash
dune test
```

Expected: 0 failures.

- [ ] **Step 2: Verify CLI end-to-end**

```bash
echo '()' | dune exec ocaml-compose-dsl
echo '() >>> a' | dune exec ocaml-compose-dsl
echo 'noop()' | dune exec ocaml-compose-dsl
echo '(())' | dune exec ocaml-compose-dsl
echo 'node :: () -> Server' | dune exec ocaml-compose-dsl
echo '\x -> ()' | dune exec ocaml-compose-dsl
echo 'let f = \x -> x in f()' | dune exec ocaml-compose-dsl
dune exec ocaml-compose-dsl -- --literate CLAUDE.md
dune exec ocaml-compose-dsl -- --literate README.md
```

Expected: valid AST output for all.

- [ ] **Step 3: Verify AST docstring is updated**

Check `lib/ast.ml` line 24 — the `Question` docstring says "parser allows on Var, StringLit, App". Update to include `Unit`:

```ocaml
  | Question of expr                (** [?] — parser allows on Var, StringLit, App, Unit *)
```

- [ ] **Step 4: Commit if any changes**

```bash
git add lib/ast.ml
git commit -m "docs(ast): update Question docstring to include Unit"
```
