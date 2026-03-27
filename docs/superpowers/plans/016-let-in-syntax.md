# `let ... in` Syntax Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace implicit let scoping with explicit `in` keyword, making scope boundaries visible and enabling future `;` separator.

**Architecture:** Add `IN` keyword token to lexer, require `in` after let value in parser, update `parse_term` grouping to accept `program`-level grammar inside parentheses. No changes to AST, Reducer, Checker, or Printer.

**Tech Stack:** OCaml, Alcotest, dune

**Spec:** `docs/superpowers/specs/2026-03-28-let-in-syntax-design.md`

---

### Task 1: Add `IN` Token to Lexer

**Files:**
- Modify: `lib/lexer.ml:1-3` (token type), `lib/lexer.ml:92-96` (read_ident keyword matching)
- Test: `test/test_*.ml`

- [ ] **Step 1: Write failing lexer tests**

Add after the last lexer test function (around line 405) and register in `lexer_tests`:

```ocaml
let test_lex_in_keyword () =
  let tokens = Lexer.tokenize "in" in
  match (List.hd tokens).token with
  | Lexer.IN -> ()
  | _ -> Alcotest.fail "expected IN token"

let test_lex_in_inside_ident () =
  let tokens = Lexer.tokenize "input" in
  match (List.hd tokens).token with
  | Lexer.IDENT "input" -> ()
  | _ -> Alcotest.fail "expected IDENT input, not IN"

let test_lex_in_as_prefix_of_ident () =
  let tokens = Lexer.tokenize "in_progress" in
  match (List.hd tokens).token with
  | Lexer.IDENT "in_progress" -> ()
  | _ -> Alcotest.fail "expected IDENT in_progress"

let test_lex_in_after_ident () =
  let tokens = Lexer.tokenize "x in" in
  match tokens with
  | [{ token = Lexer.IDENT "x"; _ }; { token = Lexer.IN; _ }; { token = Lexer.EOF; _ }] -> ()
  | _ -> Alcotest.fail "expected IDENT x, IN, EOF"
```

Add to `lexer_tests` list:
```ocaml
  ; "in keyword", `Quick, test_lex_in_keyword
  ; "in inside ident", `Quick, test_lex_in_inside_ident
  ; "in as prefix of ident", `Quick, test_lex_in_as_prefix_of_ident
  ; "in after ident", `Quick, test_lex_in_after_ident
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dune test 2>&1 | head -30`
Expected: Compilation error — `Lexer.IN` is not defined.

- [ ] **Step 3: Add `IN` token to lexer**

In `lib/lexer.ml`, add `IN` to the token type (after `LET`):

```ocaml
  | LET (** [let] keyword *)
  | IN  (** [in] keyword *)
```

In `read_ident`, add `"in"` to the keyword match (line 92-95):

```ocaml
    let tok = match s with
      | "loop" -> LOOP
      | "let" -> LET
      | "in" -> IN
      | _ -> IDENT s
    in
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dune test 2>&1 | tail -5`
Expected: All tests pass (existing + 4 new lexer tests).

- [ ] **Step 5: Commit**

```bash
git add lib/lexer.ml test/test_*.ml
git commit -m "feat(lexer): add IN keyword token"
```

---

### Task 2: Require `in` in Parser `read_lets`

**Files:**
- Modify: `lib/parser.ml:263-288` (parse_program / read_lets)
- Test: `test/test_*.ml`

- [ ] **Step 1: Write failing parser tests for `let ... in`**

Replace existing let parse tests with `in` syntax versions. Change the test inputs:

```ocaml
let test_parse_let_simple () =
  let tokens = Lexer.tokenize "let f = a >>> b in f" in
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
  let tokens = Lexer.tokenize "let a = x in let b = y in a >>> b" in
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
  let tokens = Lexer.tokenize "let f = \\ x -> x >>> a in f(b)" in
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
  let tokens = Lexer.tokenize "let a = x in let b = a in b" in
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
```

Add new test for complex value:

```ocaml
let test_parse_let_complex_value () =
  let tokens = Lexer.tokenize "let f = a >>> b in f >>> c" in
  let ast = Parser.parse_program tokens in
  Alcotest.(check string) "printed"
    {|Let("f", Seq(Var("a"), Var("b")), Seq(Var("f"), Var("c")))|}
    (Printer.to_string ast)
```

Register in `parser_tests`:
```ocaml
  ; "let complex value", `Quick, test_parse_let_complex_value
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dune test 2>&1 | grep -A2 "FAIL"`
Expected: The `let ... in` tests fail because parser still uses old syntax (doesn't expect `in`).

- [ ] **Step 3: Modify parser to require `in`**

In `lib/parser.ml`, modify `read_lets` inside `parse_program` (lines 269-279):

```ocaml
    | Lexer.LET ->
      advance st;
      let t_name = current st in
      let name = match t_name.token with
        | Lexer.IDENT s -> advance st; s
        | _ -> raise (Parse_error (t_name.loc.start, "expected identifier after 'let'"))
      in
      expect st (fun tok -> tok = Lexer.EQUALS) "expected '=' after let binding name";
      let value = parse_seq_expr st in
      let t_in = current st in
      (match t_in.token with
       | Lexer.IN -> advance st
       | _ ->
         let hint = Printf.sprintf
           "expected 'in' after let binding value\nHint: let bindings now require 'in'. Change:\n  let %s = expr\n  body\nto:\n  let %s = expr in body"
           name name
         in
         raise (Parse_error (t_in.loc.start, hint)));
      let rest = read_lets () in
      mk_expr { start = t.loc.start; end_ = rest.loc.end_ } (Let (name, value, rest))
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dune test 2>&1 | tail -5`
Expected: New let-in tests pass. Some other tests that used old syntax may still fail — that's expected and will be fixed in Task 4.

- [ ] **Step 5: Commit**

```bash
git add lib/parser.ml test/test_*.ml
git commit -m "feat(parser): require 'in' keyword after let binding value"
```

---

### Task 3: Update `parse_term` Grouping to Accept `program`

**Files:**
- Modify: `lib/parser.ml:252-256` (parse_term LPAREN branch)
- Test: `test/test_*.ml`

- [ ] **Step 1: Write failing test for parenthesized let-in**

```ocaml
let test_parse_let_parenthesized_value () =
  let tokens = Lexer.tokenize "let x = (let y = a in y) in x" in
  let ast = Parser.parse_program tokens in
  Alcotest.(check string) "printed"
    {|Let("x", Group(Let("y", Var("a"), Var("y"))), Var("x"))|}
    (Printer.to_string ast)
```

Register in `parser_tests`:
```ocaml
  ; "let parenthesized value", `Quick, test_parse_let_parenthesized_value
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dune exec test/test_compose_dsl.exe -- test Parser 'let parenthesized value'`
Expected: FAIL — `parse_term`'s `LPAREN` branch calls `parse_seq_expr`, which doesn't handle `let`.

- [ ] **Step 3: Update `parse_term` to use `read_lets` inside parens**

The challenge is that `read_lets` is local to `parse_program`. We need to extract it or make the grouping branch call a program-level parser.

In `lib/parser.ml`, extract `read_lets` as a mutually-recursive function visible to `parse_term`. Change `parse_program` to expose the inner parser:

First, move the `read_lets` logic into a new `and parse_program_inner st =` function that is mutually recursive with `parse_term` etc.:

```ocaml
and parse_program_inner st =
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
    let value = parse_seq_expr st in
    let t_in = current st in
    (match t_in.token with
     | Lexer.IN -> advance st
     | _ ->
       let hint = Printf.sprintf
         "expected 'in' after let binding value\nHint: let bindings now require 'in'. Change:\n  let %s = expr\n  body\nto:\n  let %s = expr in body"
         name name
       in
       raise (Parse_error (t_in.loc.start, hint)));
    let rest = parse_program_inner st in
    mk_expr { start = t.loc.start; end_ = rest.loc.end_ } (Let (name, value, rest))
  | _ ->
    parse_seq_expr st
```

Then update `parse_term`'s `LPAREN` branch (line 252-256):

```ocaml
  | Lexer.LPAREN ->
    advance st;
    let inner = parse_program_inner st in
    expect st (fun tok -> tok = Lexer.RPAREN) "expected ')'";
    mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (Group inner)
```

And simplify `parse_program` to just create state and call `parse_program_inner`:

```ocaml
let parse_program tokens =
  let st = make tokens in
  let ast = parse_program_inner st in
  let t_end = current st in
  (match t_end.token with
   | Lexer.EOF -> ()
   | _ -> raise (Parse_error (t_end.loc.start, "expected end of input")));
  ast
```

Note: `parse_program_inner` no longer checks for EOF — that's `parse_program`'s job. Inside parens, EOF check is replaced by `expect RPAREN`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `dune test 2>&1 | tail -5`
Expected: Parenthesized let-in test passes.

- [ ] **Step 5: Commit**

```bash
git add lib/parser.ml test/test_*.ml
git commit -m "feat(parser): support let...in inside parenthesized groups"
```

---

### Task 4: Update All Existing Tests to Use `in` Syntax

**Files:**
- Modify: `test/test_*.ml` — all tests that use old `let` syntax

- [ ] **Step 1: Identify and update all test inputs using old let syntax**

Every test that uses `let x = expr\n...` must change to `let x = expr in ...`. Here is the complete list of tests with their old and new inputs:

**Reducer tests:**
- `test_reduce_let_simple` (line 1123): `"let f = a >>> b\nf"` → `"let f = a >>> b in f"`
- `test_reduce_lambda_apply` (line 1129): `"let f = \\ x -> x >>> a\nf(b)"` → `"let f = \\ x -> x >>> a in f(b)"`
- `test_reduce_lambda_multi_param` (line 1135): `"let f = \\ x, y -> x >>> y\nf(a, b)"` → `"let f = \\ x, y -> x >>> y in f(a, b)"`
- `test_reduce_let_chain` (line 1141): `"let a = x\nlet b = a\nb"` → `"let a = x in let b = a in b"`
- `test_reduce_nested_application` (line 1147): `"let f = \\ x -> x\nlet g = \\ y -> f(y)\ng(a)"` → `"let f = \\ x -> x in let g = \\ y -> f(y) in g(a)"`
- `test_reduce_free_variable` (line 1153): `"let f = \\ x -> y\nf(a)"` → `"let f = \\ x -> y in f(a)"`
- `test_reduce_arity_mismatch` (line 1160): `"let f = \\ x, y -> x\nf(a)"` → `"let f = \\ x, y -> x in f(a)"`
- `test_reduce_free_var_apply` (line 1164): `"let f = a\nf(b)"` → `"let f = a in f(b)"`
- `test_reduce_curried_free_var_apply` (line 1171): `"let g = f(b)\ng(c)"` → `"let g = f(b) in g(c)"`
- `test_reduce_curried_free_var_lambda_rejected` (line 1178): `"let g = f(\\ x -> x)\ng(a)"` → `"let g = f(\\ x -> x) in g(a)"`
- `test_reduce_deep_curried_free_var_apply` (line 1185): `"let g = f(b)\nlet h = g(c)\nh(d)"` → `"let g = f(b) in let h = g(c) in h(d)"`
- `test_reduce_string_lit_as_arg` (line 1197): `` {|let f = \x -> x >>> a|} ^ "\n" ^ {|f("hello")|} `` → `` {|let f = \x -> x >>> a in f("hello")|} ``
- `test_reduce_string_lit_apply_error` (line 1203): `` {|let s = "hello"|} ^ "\n" ^ {|s("world")|} `` → `` {|let s = "hello" in s("world")|} ``

**Printer tests:**
- `test_print_app` (line 1544): `"let f = \\ x -> x\nf(a)"` → `"let f = \\ x -> x in f(a)"`
- `test_print_let` (line 1554): `"let f = a\nf"` → `"let f = a in f"`

**Integration tests:**
- `test_integration_let_and_check` (line 1586): `"let f = \\ x -> x >>> a\nf(b)"` → `"let f = \\ x -> x >>> a in f(b)"`

**Edge case tests:**
- `test_reduce_lambda_with_type_ann` (line 1626): `"let f = \\ x -> x :: A -> B\nf(a)"` → `"let f = \\ x -> x :: A -> B in f(a)"`
- `test_reduce_lambda_complex_args` (line 1633): `"let f = \\ x, y -> x >>> y\nf(a >>> b, c)"` → `"let f = \\ x, y -> x >>> y in f(a >>> b, c)"`
- `test_parse_let_unicode_name` (line 1647): `"let \xe5\xaf\xa9\xe6\x9f\xbb = a >>> b\n\xe5\xaf\xa9\xe6\x9f\xbb"` → `"let \xe5\xaf\xa9\xe6\x9f\xbb = a >>> b in \xe5\xaf\xa9\xe6\x9f\xbb"`
- `test_reduce_empty_application_arity` (line 1694): `"let f = \\ x -> x\nf()"` → `"let f = \\ x -> x in f()"`
- `test_reduce_capture_avoiding` (line 1707): `"let apply = \\ f, x -> f(x)\nlet id = \\ x -> x\napply(id, a)"` → `"let apply = \\ f, x -> f(x) in let id = \\ x -> x in apply(id, a)"`

**Mixed arg tests:**
- `test_reduce_mixed_args` (line 1750): `"let v = a >>> b\npush(remote: origin, v)"` → `"let v = a >>> b in push(remote: origin, v)"`
- `test_reduce_named_args_on_lambda_error` (line 1756): `"let f = \\ x -> x\nf(key: val)"` → `"let f = \\ x -> x in f(key: val)"`
- `test_check_mixed_args_no_error` (line 1771): `"let v = a >>> b\npush(remote: origin, v)"` → `"let v = a >>> b in push(remote: origin, v)"`
- `test_integration_mixed_args` (line 1783): `"let v = some_pipeline\npush(remote: origin, v)"` → `"let v = some_pipeline in push(remote: origin, v)"`

**Markdown integration:**
- `test_md_literate_end_to_end` (line 1971): `"# Doc\n\n```arrow\nlet f = a >>> b\nf\n```\n\nText\n"` → `"# Doc\n\n```arrow\nlet f = a >>> b in f\n```\n\nText\n"`

- [ ] **Step 2: Update `test_parse_let_error_no_body` for new error message**

This test (line 1654) should verify the new migration hint error:

```ocaml
let test_parse_let_error_no_body () =
  match Lexer.tokenize "let f = a" |> Parser.parse_program with
  | _ -> Alcotest.fail "expected parse error (no 'in' after let)"
  | exception Parser.Parse_error (_, msg) ->
    Alcotest.(check bool) "mentions 'in'" true (contains msg "in")
```

- [ ] **Step 3: Run tests to verify all pass**

Run: `dune test 2>&1 | tail -5`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add test/test_*.ml
git commit -m "test: update all let tests to use 'in' syntax"
```

---

### Task 5: Add New Parser Error Tests

**Files:**
- Modify: `test/test_*.ml`

- [ ] **Step 1: Write error tests for let-in edge cases**

```ocaml
let test_parse_let_old_syntax_error () =
  match Lexer.tokenize "let x = a\nx" |> Parser.parse_program with
  | _ -> Alcotest.fail "expected parse error (old syntax)"
  | exception Parser.Parse_error (_, msg) ->
    Alcotest.(check bool) "migration hint" true (contains msg "in")

let test_parse_let_in_lambda_body_error () =
  match Lexer.tokenize "\\ x -> let y = x in y" |> Parser.parse_program with
  | _ -> Alcotest.fail "expected parse error (let not valid in lambda body)"
  | exception Parser.Parse_error _ -> ()

let test_parse_let_in_positional_arg_error () =
  match Lexer.tokenize "f(let x = a in x)" |> Parser.parse_program with
  | _ -> Alcotest.fail "expected parse error (let not valid in positional arg)"
  | exception Parser.Parse_error _ -> ()

let test_parse_let_ident_starting_with_in () =
  let ast = parse_ok "let x = in_progress in x" in
  Alcotest.(check string) "printed"
    {|Let("x", Var("in_progress"), Var("x"))|}
    (Printer.to_string ast)
```

Register in `edge_case_tests`:
```ocaml
  ; "let old syntax error", `Quick, test_parse_let_old_syntax_error
  ; "let in lambda body error", `Quick, test_parse_let_in_lambda_body_error
  ; "let in positional arg error", `Quick, test_parse_let_in_positional_arg_error
  ; "let ident starting with in", `Quick, test_parse_let_ident_starting_with_in
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `dune test 2>&1 | tail -5`
Expected: All pass (these test current behavior after Task 2-3 changes).

- [ ] **Step 3: Commit**

```bash
git add test/test_*.ml
git commit -m "test: add let...in edge case and error tests"
```

---

### Task 6: Update README EBNF and Examples

**Files:**
- Modify: `README.md` — EBNF (lines 15-73), let examples (lines 167-186)

- [ ] **Step 1: Update EBNF grammar**

Change lines 16-18:
```
program = { let_binding } , pipeline ;

let_binding = "let" , ident , "=" , seq_expr ;
```
to:
```
program     = let_expr | pipeline ;

let_expr    = "let" , ident , "=" , seq_expr , "in" , program ;
```

Change line 40:
```
         | "(" , seq_expr , ")"                    (* grouping *)
```
to:
```
         | "(" , program , ")"                     (* grouping — accepts let_expr *)
```

Change line 57:
```
reserved    = "let" | "loop" ;
```
to:
```
reserved    = "let" | "loop" | "in" ;
```

- [ ] **Step 2: Update let examples in README**

Lines 168-171 — lambda example:
```
let greet = \name -> hello(to: name) >>> respond in
greet(alice) >>> greet(bob)
```

Lines 173-181 — complex example:
```
let review = \trigger, fix ->
  loop(trigger >>> (pass ||| fix))
in
let phase1 = gather >>> review(check?, rework) in
let phase2 = build >>> review(test?, fix) in
phase1 >>> phase2
```

Lines 183-186 — mixed args example:
```
let v = some_pipeline in
push(remote: origin, v)
```

- [ ] **Step 3: Verify README is valid literate Arrow**

Run: `dune exec ocaml-compose-dsl -- --literate README.md`
Expected: Exit 0 (all arrow blocks valid). If any arrow blocks in README contain old `let` syntax, this will catch them.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs(README): update EBNF and examples for let...in syntax"
```

---

### Task 7: Update CLAUDE.md Arrow Blocks

**Files:**
- Modify: `CLAUDE.md` — arrow code blocks containing `let`

- [ ] **Step 1: Update arrow blocks in CLAUDE.md**

The pipeline block (lines 33-38):
```arrow
let lex = Lexer :: String -> Token in
let parse = Parser :: Token -> Ast in       -- parse_program entry point
let reduce = Reducer :: Ast -> Ast in       -- desugar let, beta reduce lambda
let check = Checker :: Ast -> Result in
let md = Markdown :: Markdown -> String in  -- literate mode: extract arrow blocks
let pipeline = md >>> lex >>> parse >>> reduce >>> check in
pipeline
```

The verify/test block (lines 64-68):
```arrow
let verify = verify_ebnf :: Code -> Spec in   -- check README.md EBNF still matches parser/lexer
let test =
  update_tests :: Spec -> Test             -- update or add tests in test/test_*.ml
  >>> dune_test :: Test -> Pass in             -- run dune test, confirm all pass
let implement = implement :: Code -> Code >>> verify >>> test in
implement
```

The version bump block (lines 87-96):
```arrow
let docs =
  update_docs(file: "CLAUDE.md")
  &&& update_docs(file: "README.md")
  &&& update_docs(file: "CHANGELOG.md") in
let version_bump =
  bump(file: "dune-project")
  >>> docs
  >>> build -- dune build to regenerate opam files
  >>> test  -- dune test to confirm nothing broke
  >>> commit in
version_bump
```

The releasing block (lines 101-106) — check if it has `let`:
```arrow
version_bump
  >>> tag(format: "vX.Y.Z")
  >>> push(remote: origin, tag: "vX.Y.Z")
  >>> wait_ci -- wait for CI release workflow to complete
  >>> run(script: "scripts/release-macos-x86_64.sh") -- local Intel Mac upload
```
(No `let`, no change needed.)

- [ ] **Step 2: Update Ast description in CLAUDE.md**

Line 41 describes `Let` as `` Let (`let x = expr`) ``. Change to `` Let (`let x = expr in body`) ``.

- [ ] **Step 3: Update Future Ideas in CLAUDE.md**

Line 119 — remove the "`in` keyword for let scope" bullet (it's now implemented).

Line 120 — keep "`let ... in` as expression form" but update the description to note that `let ... in` inside parens is already supported (Task 3), and the remaining work is lifting it into `seq_expr` directly.

- [ ] **Step 4: Verify CLAUDE.md is valid literate Arrow**

Run: `dune exec ocaml-compose-dsl -- --literate CLAUDE.md`
Expected: Exit 0.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(CLAUDE.md): update arrow blocks and descriptions for let...in syntax"
```

---

### Task 8: Update CHANGELOG and Version Bump

**Files:**
- Modify: `CHANGELOG.md`, `dune-project`

- [ ] **Step 1: Update CHANGELOG**

Add under `## [Unreleased]`:
```markdown
## [0.9.0] - 2026-03-28

### Changed
- **BREAKING:** `let` bindings now require `in` keyword to delimit scope: `let x = expr in body` (previously `let x = expr` with implicit "rest of program" scope)
- `( ... )` grouping now accepts full program grammar (including `let ... in`) inside parentheses

### Added
- `IN` keyword token in lexer
- Migration hint error message when old `let` syntax (without `in`) is detected
```

- [ ] **Step 2: Bump version in dune-project**

Change `(version 0.8.0)` to `(version 0.9.0)`.

- [ ] **Step 3: Rebuild to regenerate opam files**

Run: `dune build`
Expected: Build succeeds, opam files updated.

- [ ] **Step 4: Run full test suite**

Run: `dune test`
Expected: All tests pass.

- [ ] **Step 5: Verify literate mode on both docs**

Run: `dune exec ocaml-compose-dsl -- --literate README.md && dune exec ocaml-compose-dsl -- --literate CLAUDE.md`
Expected: Both exit 0.

- [ ] **Step 6: Commit**

```bash
git add CHANGELOG.md dune-project ocaml-compose-dsl.opam ocaml-compose-dsl-lib.opam
git commit -m "chore: bump version to 0.9.0"
```

---

### Task 9: Final Verification

- [ ] **Step 1: Run full test suite one more time**

Run: `dune test`
Expected: All tests pass.

- [ ] **Step 2: Verify clean build**

Run: `dune clean && dune build && dune test`
Expected: Clean build succeeds, all tests pass.

- [ ] **Step 3: Spot-check CLI with new syntax**

Run: `echo 'let x = a >>> b in x >>> c' | dune exec ocaml-compose-dsl`
Expected: Prints AST with `Let("x", Seq(...), Seq(...))`.

Run: `echo 'let x = a' | dune exec ocaml-compose-dsl`
Expected: Error with migration hint mentioning `in`.

- [ ] **Step 4: Verify literate mode**

Run: `dune exec ocaml-compose-dsl -- --literate README.md && dune exec ocaml-compose-dsl -- --literate CLAUDE.md`
Expected: Both exit 0.
