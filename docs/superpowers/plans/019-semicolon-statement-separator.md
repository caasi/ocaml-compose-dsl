# Semicolon Statement Separator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `;` as a statement separator so that multiple independent pipelines can coexist in a single program, enabling natural literate-mode workflows.

**Architecture:** New `type program = expr list` in AST. Parser returns `expr list` via `;`-separated `stmt` rules. Reducer, Checker, and Printer gain `_program` functions that map over the list. Markdown.combine changes its inter-block separator from `\n` to `;\n`. CLI wires everything together.

**Tech Stack:** OCaml 5.1, Menhir (LALR parser generator with incremental API), sedlex (PPX-based lexer), Alcotest (test framework), dune (build system)

**Spec:** `docs/superpowers/specs/2026-03-28-semicolon-statement-separator-design.md`

---

### Task 1: AST — Add `type program`

**Files:**
- Modify: `lib/ast.ml:28` (after `expr_desc` definition, before `call_arg`)

- [ ] **Step 1: Add the type definition**

Insert after the `Let` constructor (line 28), before the `call_arg` type (line 30):

```ocaml
type program = expr list
```

- [ ] **Step 2: Verify it compiles**

Run: `dune build`
Expected: SUCCESS (type alias, no consumers yet)

- [ ] **Step 3: Commit**

```bash
git add lib/ast.ml
git commit --message "feat: add program type alias to AST"
```

---

### Task 2: Lexer — Add `SEMICOLON` token

**Files:**
- Modify: `lib/lexer.ml:4-27` (token re-export block)
- Modify: `lib/lexer.ml:161-169` (single-char token rules in `read_token`)
- Test: `test/test_lexer.ml`

- [ ] **Step 1: Write the failing test**

Add to `test/test_lexer.ml` before the `tests` list:

```ocaml
let test_lex_semicolon () =
  let tokens = Lexer.tokenize "a; b" in
  match tokens with
  | [ { token = IDENT "a"; _ }
    ; { token = SEMICOLON; _ }
    ; { token = IDENT "b"; _ }
    ; { token = EOF; _ } ] -> ()
  | _ -> Alcotest.fail "expected [IDENT a; SEMICOLON; IDENT b; EOF]"
```

Add to the `tests` list at the end:

```ocaml
  ; "semicolon", `Quick, test_lex_semicolon
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dune test 2>&1 | head --lines=20`
Expected: Compilation error — `SEMICOLON` is not a known token constructor.

- [ ] **Step 3: Add SEMICOLON to token re-export**

In `lib/lexer.ml`, the token re-export block (lines 4-27) lists all `Parser.token` constructors alphabetically. Add `SEMICOLON` between `SEQ` (line 6) and `RPAREN` (line 7):

```ocaml
type token = Parser.token =
  | STRING of string
  | SEQ
  | SEMICOLON
  | RPAREN
  ...
```

- [ ] **Step 4: Add SEMICOLON to parser token declarations**

In `lib/parser.mly`, add to the token declarations (after line 20):

```
%token SEMICOLON
```

- [ ] **Step 5: Add lexer rule for `;`**

In `lib/lexer.ml`, in the single-char token section (lines 161-169), add after the `BACKSLASH` rule (line 169):

```ocaml
  | ';' -> let s = current_pos st in (Parser.SEMICOLON, s, end_pos st)
```

- [ ] **Step 6: Run test to verify it passes**

Run: `dune test`
Expected: All tests pass, including the new `semicolon` test.

- [ ] **Step 7: Commit**

```bash
git add lib/lexer.ml lib/parser.mly test/test_lexer.ml
git commit --message "feat: add SEMICOLON token to lexer and parser"
```

---

### Task 3: Parser — `;`-separated statements

This is the core task. The parser return type changes, cascading into `parse_errors.ml` and test helpers.

**Files:**
- Modify: `lib/parser.mly:23-36` (start declaration, program/program_inner rules)
- Modify: `lib/parser.mly:95` (term LPAREN rule — `program_inner` → `stmt`)
- Modify: `lib/parse_errors.ml:11` (return type)
- Modify: `lib/parser.messages` (regenerate for new grammar states)
- Modify: `test/helpers.ml:3-6` (adapt to `program` return type)
- Test: `test/test_parser.ml`

- [ ] **Step 1: Write the failing tests**

Add to `test/test_parser.ml` before the `edge_case_tests` list:

```ocaml
let test_parse_two_statements () =
  let prog = parse_program_ok "a >>> b; c >>> d" in
  Alcotest.(check int) "two statements" 2 (List.length prog);
  (match prog with
   | [{ desc = Ast.Seq _; _ }; { desc = Ast.Seq _; _ }] -> ()
   | _ -> Alcotest.fail "expected [Seq; Seq]")

let test_parse_trailing_semicolon () =
  let prog = parse_program_ok "a >>> b;" in
  Alcotest.(check int) "one statement" 1 (List.length prog)

let test_parse_single_statement () =
  let prog = parse_program_ok "a >>> b" in
  Alcotest.(check int) "one statement" 1 (List.length prog)

let test_parse_let_in_statement () =
  let prog = parse_program_ok "let x = a in x; b" in
  Alcotest.(check int) "two statements" 2 (List.length prog);
  (match prog with
   | [{ desc = Ast.Let _; _ }; { desc = Ast.Var "b"; _ }] -> ()
   | _ -> Alcotest.fail "expected [Let; Var(b)]")

let test_parse_semicolon_in_parens_error () =
  parse_fails "(a; b)"

let test_parse_empty_statement_error () =
  parse_fails ";a"

let test_parse_double_semicolon_error () =
  parse_fails "a;; b"

let test_parse_empty_input_error () =
  parse_fails ""

let test_parse_whitespace_only_error () =
  parse_fails "   "

let test_parse_stmt_with_type_ann () =
  let prog = parse_program_ok "a :: A -> B; c :: C -> D" in
  Alcotest.(check int) "two statements" 2 (List.length prog)
```

Add these to the `edge_case_tests` list:

```ocaml
  ; "two statements", `Quick, test_parse_two_statements
  ; "trailing semicolon", `Quick, test_parse_trailing_semicolon
  ; "single statement program", `Quick, test_parse_single_statement
  ; "let in statement", `Quick, test_parse_let_in_statement
  ; "semicolon in parens error", `Quick, test_parse_semicolon_in_parens_error
  ; "empty statement error", `Quick, test_parse_empty_statement_error
  ; "double semicolon error", `Quick, test_parse_double_semicolon_error
  ; "empty input error", `Quick, test_parse_empty_input_error
  ; "whitespace only error", `Quick, test_parse_whitespace_only_error
  ; "stmt with type ann", `Quick, test_parse_stmt_with_type_ann
```

- [ ] **Step 2: Add `parse_program_ok` to test helpers**

In `test/helpers.ml`, add after `parse_ok` (line 4):

```ocaml
let parse_program_ok input =
  Parse_errors.parse input
```

Change `parse_ok` to extract a single statement from the program list:

```ocaml
let parse_ok input =
  match Parse_errors.parse input with
  | [e] -> e
  | prog ->
    Alcotest.fail
      (Printf.sprintf "expected single statement, got %d" (List.length prog))
```

Update `desc_of` (line 6) — no change needed, it calls `parse_ok` which still returns `expr`.

- [ ] **Step 3: Run tests to verify they fail**

Run: `dune test 2>&1 | head --lines=20`
Expected: Compilation error — `parse_program_ok` is defined but `Parse_errors.parse` still returns `Ast.expr`, not `Ast.program`. The type mismatch will prevent compilation.

- [ ] **Step 4: Update parser grammar**

Replace the start declaration and rules in `lib/parser.mly`.

Change line 23 from:

```
%start <Ast.expr> program
```

to:

```
%start <Ast.program> program
```

Replace the `program` and `program_inner` rules (lines 27-36) with:

```menhir
program:
  | s=stmts EOF { s }
;

stmts:
  | s=stmt { [s] }
  | s=stmt SEMICOLON rest=stmts { s :: rest }
  | s=stmt SEMICOLON { [s] }
;

stmt:
  | LET name=IDENT EQUALS value=seq_expr IN rest=stmt
    { mk_expr $loc (Let (name, value, rest)) }
  | e=seq_expr
    { e }
;
```

Update the `term` rule — change line 95 from:

```
  | LPAREN inner=program_inner RPAREN
```

to:

```
  | LPAREN inner=stmt RPAREN
```

- [ ] **Step 5: Regenerate parser.messages**

The grammar states have changed. Update `parser.messages`:

```bash
cd /Users/caasi/GitHub/caasi/ocaml-compose-dsl
# Update existing messages to match new state numbers
menhir --table lib/parser.mly --update-errors lib/parser.messages > /tmp/parser.messages.updated
cp /tmp/parser.messages.updated lib/parser.messages

# List all possible error states in new grammar
menhir --table lib/parser.mly --list-errors > /tmp/parser.messages.all

# Compare to find missing entries
menhir --table lib/parser.mly --compare-errors /tmp/parser.messages.all --compare-errors lib/parser.messages 2>&1 || true
```

For any missing entries reported by `--compare-errors`, add appropriate error messages to `lib/parser.messages`. Common new states to handle:

- `SEMICOLON` at program start → "expected identifier, string, '(', 'loop', or '\\' (lambda)"
- `SEMICOLON SEMICOLON` → "expected identifier, string, '(', 'loop', or '\\' (lambda)"
- `stmt SEMICOLON` followed by unexpected token → appropriate message

After adding all missing entries, verify:

```bash
dune build
```

Expected: SUCCESS — `parser_messages.ml` is regenerated without errors.

- [ ] **Step 6: Update parse_errors.ml return type**

The return type of `parse` in `lib/parse_errors.ml` changes automatically since it's inferred from `Parser.Incremental.program`'s return type (which is now `Ast.program`). No code changes needed — the type signature is inferred. Verify:

```bash
dune build
```

Expected: SUCCESS.

- [ ] **Step 7: Run tests to verify they pass**

Run: `dune test`
Expected: All tests pass, including the new semicolon tests and all existing tests (which use `parse_ok` → single-statement extraction).

- [ ] **Step 8: Commit**

```bash
git add lib/parser.mly lib/parser.messages lib/parse_errors.ml test/helpers.ml test/test_parser.ml
git commit --message "feat: add semicolon statement separator to parser"
```

---

### Task 4: Reducer — Add `reduce_program`

**Files:**
- Modify: `lib/reducer.ml:185` (after `reduce`)
- Test: `test/test_reducer.ml`

- [ ] **Step 1: Write the failing test**

Add to `test/test_reducer.ml`:

```ocaml
let test_reduce_program_independent_scopes () =
  let prog = Helpers.parse_program_ok "let x = a in x; let x = b in x" in
  let reduced = Reducer.reduce_program prog in
  Alcotest.(check int) "two statements" 2 (List.length reduced);
  (match reduced with
   | [{ desc = Ast.Var "a"; _ }; { desc = Ast.Var "b"; _ }] -> ()
   | _ -> Alcotest.fail "expected [Var(a); Var(b)] — independent scopes")

let test_reduce_program_single () =
  let prog = Helpers.parse_program_ok "a >>> b" in
  let reduced = Reducer.reduce_program prog in
  Alcotest.(check int) "one statement" 1 (List.length reduced)
```

Add to the `tests` list:

```ocaml
  ; "program independent scopes", `Quick, test_reduce_program_independent_scopes
  ; "program single", `Quick, test_reduce_program_single
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dune test 2>&1 | head --lines=10`
Expected: Compilation error — `Reducer.reduce_program` does not exist.

- [ ] **Step 3: Implement `reduce_program`**

Add at the end of `lib/reducer.ml` (after line 185):

```ocaml
let reduce_program (prog : Ast.program) : Ast.program =
  List.map reduce prog
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dune test`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/reducer.ml test/test_reducer.ml
git commit --message "feat: add reduce_program for multi-statement programs"
```

---

### Task 5: Checker — Add `check_program`

**Files:**
- Modify: `lib/checker.ml:104` (after `check`)
- Test: `test/test_checker.ml`

- [ ] **Step 1: Write the failing test**

Add to `test/test_checker.ml`:

```ocaml
let test_check_program_merges_warnings () =
  let prog = Helpers.parse_program_ok "a?; b?" in
  let reduced = Reducer.reduce_program prog in
  let result = Checker.check_program reduced in
  Alcotest.(check int) "two warnings (one per stmt)" 2
    (List.length result.Checker.warnings)

let test_check_program_no_warnings () =
  let prog = Helpers.parse_program_ok "a >>> b; c >>> d" in
  let reduced = Reducer.reduce_program prog in
  let result = Checker.check_program reduced in
  Alcotest.(check int) "no warnings" 0
    (List.length result.Checker.warnings)
```

Add to the `tests` list:

```ocaml
  ; "program merges warnings", `Quick, test_check_program_merges_warnings
  ; "program no warnings", `Quick, test_check_program_no_warnings
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dune test 2>&1 | head --lines=10`
Expected: Compilation error — `Checker.check_program` does not exist.

- [ ] **Step 3: Implement `check_program`**

Add at the end of `lib/checker.ml` (after line 104):

```ocaml
let check_program (prog : Ast.program) : result =
  let warnings = List.concat_map (fun e -> (check e).warnings) prog in
  { warnings }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dune test`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/checker.ml test/test_checker.ml
git commit --message "feat: add check_program for multi-statement programs"
```

---

### Task 6: Printer — Add `program_to_string`

**Files:**
- Modify: `lib/printer.ml:42` (after `to_string`)
- Test: `test/test_printer.ml`

- [ ] **Step 1: Write the failing test**

Add to `test/test_printer.ml`:

```ocaml
let test_print_program_multi () =
  let prog = Helpers.parse_program_ok "a >>> b; c >>> d" in
  let s = Printer.program_to_string prog in
  Alcotest.(check string) "two statements"
    "Seq(Var(\"a\"), Var(\"b\"));\nSeq(Var(\"c\"), Var(\"d\"))" s

let test_print_program_single () =
  let prog = Helpers.parse_program_ok "a >>> b" in
  let s = Printer.program_to_string prog in
  Alcotest.(check string) "single statement"
    "Seq(Var(\"a\"), Var(\"b\"))" s
```

Add to the `tests` list:

```ocaml
  ; "program multi", `Quick, test_print_program_multi
  ; "program single", `Quick, test_print_program_single
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dune test 2>&1 | head --lines=10`
Expected: Compilation error — `Printer.program_to_string` does not exist.

- [ ] **Step 3: Implement `program_to_string`**

Add at the end of `lib/printer.ml` (after line 41):

```ocaml
let program_to_string (prog : Ast.program) : string =
  String.concat ";\n" (List.map to_string prog)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `dune test`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/printer.ml test/test_printer.ml
git commit --message "feat: add program_to_string for multi-statement programs"
```

---

### Task 7: Markdown.combine — Semicolon separator

**Files:**
- Modify: `lib/markdown.ml:104` (separator line in `combine`)
- Test: `test/test_markdown.ml`

- [ ] **Step 1: Write the failing test**

Add to `test/test_markdown.ml` before the `tests` list:

```ocaml
let test_md_combine_semicolon_separator () =
  let blocks = [
    { Markdown.content = "a >>> b\n"; markdown_start = 5 };
    { Markdown.content = "c >>> d\n"; markdown_start = 15 };
  ] in
  let source, _table = Markdown.combine blocks in
  (* Expect: "a >>> b\n;\nc >>> d\n" *)
  assert (Helpers.contains source ";");
  (* Verify both blocks are present *)
  assert (Helpers.contains source "a >>> b");
  assert (Helpers.contains source "c >>> d")

let test_md_combine_single_no_semicolon () =
  let blocks = [
    { Markdown.content = "a >>> b\n"; markdown_start = 5 };
  ] in
  let source, _table = Markdown.combine blocks in
  assert (not (Helpers.contains source ";"))
```

Add to the `tests` list:

```ocaml
  ; "combine semicolon separator", `Quick, test_md_combine_semicolon_separator
  ; "combine single no semicolon", `Quick, test_md_combine_single_no_semicolon
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dune exec test/main.exe -- test Markdown 18`
Expected: FAIL — `test_md_combine_semicolon_separator` fails because `contains source ";"` is false (separator is `\n`, not `;\n`).

- [ ] **Step 3: Change separator in combine**

In `lib/markdown.ml`, change line 104 from:

```ocaml
        if current_line > 1 then Buffer.add_char buf '\n';
```

to:

```ocaml
        if current_line > 1 then Buffer.add_string buf ";\n";
```

- [ ] **Step 4: Update existing combine test**

The existing `test_md_combine_multiple` (line 97 of `test/test_markdown.ml`) asserts the exact combined source string. Update it to reflect the new `;\n` separator:

Change the expected string from:

```ocaml
  Alcotest.(check string) "source" "a >>> b\n\nc >>> d\ne >>> f\n" source;
```

to:

```ocaml
  Alcotest.(check string) "source" "a >>> b\n;\nc >>> d\ne >>> f\n" source;
```

The offset table assertions (lines 98-104) remain unchanged — `;\n` has the same newline count as `\n`.

- [ ] **Step 5: Run test to verify it passes**

Run: `dune test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/markdown.ml test/test_markdown.ml
git commit --message "feat: use semicolon separator in Markdown.combine"
```

---

### Task 8: CLI — Wire up program-level functions

**Files:**
- Modify: `bin/main.ml:93-116` (parse/reduce/check/print call chain)
- Test: `test/test_integration.ml`

- [ ] **Step 1: Write the failing integration test**

Add to `test/test_integration.ml`:

```ocaml
let test_integration_multi_statement () =
  let prog = Helpers.parse_program_ok "let x = a in x; b >>> c" in
  let reduced = Reducer.reduce_program prog in
  let result = Checker.check_program reduced in
  Alcotest.(check int) "no warnings" 0 (List.length result.Checker.warnings);
  let output = Printer.program_to_string reduced in
  assert (Helpers.contains output "Var(\"a\")");
  assert (Helpers.contains output "Seq")
```

Add to the `tests` list:

```ocaml
  ; "multi statement", `Quick, test_integration_multi_statement
```

- [ ] **Step 2: Run test to verify it passes**

Run: `dune test`
Expected: PASS — the test uses `parse_program_ok`, `reduce_program`, `check_program`, `program_to_string` which are all implemented already.

- [ ] **Step 3: Update CLI main.ml**

In `bin/main.ml`, replace lines 93-116 (the match/reduce/check/print chain):

```ocaml
  match Compose_dsl.Parse_errors.parse source with
  | exception Compose_dsl.Lexer.Lex_error (pos, msg) ->
    Printf.eprintf "lex error at %d:%d: %s\n" (tl pos.line) pos.col msg;
    exit 1
  | exception Compose_dsl.Parse_errors.Parse_error (pos, msg) ->
    Printf.eprintf "parse error at %d:%d: %s\n" (tl pos.line) pos.col msg;
    exit 1
  | exception Compose_dsl.Ast.Duplicate_param (pos, msg) ->
    Printf.eprintf "parse error at %d:%d: %s\n" (tl pos.line) pos.col msg;
    exit 1
  | prog ->
      let prog = match Compose_dsl.Reducer.reduce_program prog with
        | reduced -> reduced
        | exception Compose_dsl.Reducer.Reduce_error (pos, msg) ->
          Printf.eprintf "reduce error at %d:%d: %s\n" (tl pos.line) pos.col msg;
          exit 1
      in
      let result = Compose_dsl.Checker.check_program prog in
      List.iter
        (fun (w : Compose_dsl.Checker.warning) ->
          Printf.eprintf "warning at %d:%d: %s\n" (tl w.loc.start.line) w.loc.start.col w.message)
        result.warnings;
      print_endline (Compose_dsl.Printer.program_to_string prog);
      exit 0
```

- [ ] **Step 4: Verify CLI works end-to-end**

Run manual tests:

```bash
# Single statement (backward compat)
echo 'a >>> b' | dune exec ocaml-compose-dsl
# Expected: Seq(Var("a"), Var("b"))

# Multiple statements
echo 'a >>> b; c >>> d' | dune exec ocaml-compose-dsl
# Expected:
# Seq(Var("a"), Var("b"));
# Seq(Var("c"), Var("d"))

# Trailing semicolon
echo 'a >>> b;' | dune exec ocaml-compose-dsl
# Expected: Seq(Var("a"), Var("b"))

# Let across semicolons (independent scopes)
echo 'let x = a in x; let x = b in x' | dune exec ocaml-compose-dsl
# Expected:
# Var("a");
# Var("b")
```

- [ ] **Step 5: Run full test suite**

Run: `dune test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add bin/main.ml test/test_integration.ml
git commit --message "feat: wire up program-level functions in CLI"
```

---

### Task 9: Markdown integration — Literate mode end-to-end

**Files:**
- Test: `test/test_markdown.ml`

- [ ] **Step 1: Write literate-mode integration test**

Add to `test/test_markdown.ml` before the `integration_tests` list:

```ocaml
let test_md_literate_multi_block () =
  let input = "# Doc\n\n```arrow\na >>> b\n```\n\nText\n\n```arrow\nc >>> d\n```\n" in
  let blocks = Markdown.extract input in
  Alcotest.(check int) "two blocks" 2 (List.length blocks);
  let source, _table = Markdown.combine blocks in
  (* combine inserts ;\n between blocks *)
  let prog = Helpers.parse_program_ok source in
  Alcotest.(check int) "two statements" 2 (List.length prog);
  let reduced = Reducer.reduce_program prog in
  let _result = Checker.check_program reduced in
  ()
```

Add to the `integration_tests` list:

```ocaml
  ; "literate multi block", `Quick, test_md_literate_multi_block
```

- [ ] **Step 2: Run test to verify it passes**

Run: `dune test`
Expected: PASS — combine now inserts `;\n` between blocks, parser handles `;`.

- [ ] **Step 3: Commit**

```bash
git add test/test_markdown.ml
git commit --message "test: add literate mode multi-block integration test"
```

---

### Task 10: Documentation — Update EBNF, README, and CLAUDE.md

**Files:**
- Modify: `README.md:16-25,46-47` (EBNF grammar)
- Modify: `CLAUDE.md` (arrow blocks + prose)

- [ ] **Step 1: Update EBNF in README.md**

Replace lines 16-25 of `README.md`:

```ebnf
program     = stmt , { ";" , stmt } , [ ";" ] ;

stmt        = let_expr | pipeline ;

let_expr    = "let" , ident , "=" , seq_expr , "in" , stmt ;

lambda  = "\" , ident , { "," , ident } , "->" , seq_expr ;
                                                    (* body is seq_expr, not stmt;
                                                       let_expr is only valid at stmt level
                                                       or inside grouping parens *)

pipeline = seq_expr ;
```

Also update the grouping comment in the `term` rule (line 46-47):

```ebnf
         | "(" , stmt , ")"                        (* grouping — allows let bindings
                                                      but not semicolons inside parens *)
```

- [ ] **Step 2: Rewrite CLAUDE.md arrow blocks**

The four `arrow` blocks in CLAUDE.md currently chain via trailing `let ... in` across blocks. With `;\n` separators between blocks, this causes parse errors because `in` expects a body expression but gets `SEMICOLON`. Rewrite each block to be self-contained.

**Block 1** (lines 32-38) — remove `pipeline` binding, use inline expression:

```arrow
let parse = Parse_errors :: String -> Program in -- Menhir incremental API; drives Lexer internally
let reduce = Reducer :: Ast -> Ast in        -- desugar let, beta reduce lambda
let check = Checker :: Ast -> Result in
let md = Markdown :: Markdown -> String in   -- literate mode: extract arrow blocks
md >>> parse >>> reduce >>> check
```

**Block 2** (lines 63-69) — remove `implement` binding, use inline expression:

```arrow
let verify = verify_ebnf :: Code -> Spec in   -- check README.md EBNF still matches parser/lexer
let test =
  update_tests :: Spec -> Test             -- update or add tests under test/ (e.g., test_lexer.ml, test_parser.ml)
  >>> dune_test :: Test -> Pass in             -- run dune test, confirm all pass
implement :: Code -> Code >>> verify >>> test
```

**Block 3** (lines 86-97) — remove `version_bump` binding, inline the pipeline:

```arrow
let docs =
  update_docs(file: "CLAUDE.md")
  &&& update_docs(file: "README.md")
  &&& update_docs(file: "CHANGELOG.md") in
bump(file: "dune-project")
  >>> docs
  >>> build -- dune build to regenerate opam files
  >>> test  -- dune test to confirm nothing broke
  >>> commit
```

**Block 4** (lines 101-107) — no change needed (`version_bump` is now a free variable, which is valid):

```arrow
version_bump
  >>> tag(format: "vX.Y.Z")
  >>> push(remote: origin, tag: "vX.Y.Z")
  >>> wait_ci -- wait for CI release workflow to complete
  >>> run(script: "scripts/release-macos-x86_64.sh") -- local Intel Mac upload
```

- [ ] **Step 3: Update CLAUDE.md prose**

Update the literate mode note near line 8 from:

> The `arrow` blocks in this file form a single chained program via `let ... in` — validate them together with `dune exec ocaml-compose-dsl -- --literate CLAUDE.md`, not individually.

to:

> The `arrow` blocks in this file are independent statements separated by `;` — validate them together with `dune exec ocaml-compose-dsl -- --literate CLAUDE.md`.

Update the `Parse_errors` module description (line 43) to reflect `string -> Ast.program`.

- [ ] **Step 4: Verify literate mode**

Run: `dune exec ocaml-compose-dsl -- --literate README.md`
Expected: Exit 0.

Run: `dune exec ocaml-compose-dsl -- --literate CLAUDE.md`
Expected: Exit 0.

- [ ] **Step 5: Run full test suite one final time**

Run: `dune test`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add README.md CLAUDE.md
git commit --message "docs: update EBNF and rewrite CLAUDE.md arrow blocks for semicolon separator"
```

---

### Task 12: Parser — Tolerant semicolons (amendment 2026-03-29)

**Motivation:** Copilot review on PR #32 identified that `Markdown.combine` inserting `";\n"` between blocks causes a parse error when an extracted arrow block is empty. More broadly, the strict separator grammar is unnecessarily fragile — `a;;b` and `;a` fail even though the intent is clear. See spec amendment "Tolerant Semicolons" for design rationale and alternatives considered.

**Files:**
- Modify: `lib/parser.mly` (replace `stmts` with `semi_sep_stmts` + `semi_tail`)
- Modify: `lib/parser.messages` (regenerate for new parser states)
- Modify: `test/test_parser.ml` (update error tests, add tolerant semicolon tests)
- Modify: `test/test_markdown.ml` (add empty arrow block regression test)
- Modify: `bin/main.ml` (handle empty program `[]`)
- Modify: `README.md` (update EBNF)

- [ ] **Step 1: Update tests (TDD)**

Change existing error tests that are now valid:
- `test_parse_empty_statement_error` (`;a`) → expect `[a]`
- `test_parse_double_semicolon_error` (`a;; b`) → expect `[a; b]`
- `test_parse_empty_input_error` (`""`) → expect `[]`
- `test_parse_whitespace_only_error` (`"   "`) → expect `[]`

Add new tests:
- `test_parse_consecutive_semicolons`: `a;;;;;;b` → `[a; b]`
- `test_parse_leading_semicolons`: `;;;a` → `[a]`
- `test_parse_only_semicolons`: `;;;` → `[]`
- `test_parse_semicolons_between_stmts`: `a; ; ; b` → `[a; b]`

Add regression test in `test_markdown.ml`:
- `test_md_combine_empty_block`: empty arrow block + non-empty block → parses OK

Run: `dune test`
Expected: Tests fail (parser not yet updated).

- [ ] **Step 2: Update parser grammar**

Replace `stmts` in `parser.mly`:

```menhir
semi_sep_stmts:
  | /* empty */                           { [] }
  | SEMICOLON semi_sep_stmts              { $2 }
  | s=stmt rest=semi_tail                 { s :: rest }
;

semi_tail:
  | /* empty */                           { [] }
  | SEMICOLON rest=semi_sep_stmts         { rest }
;
```

Update `program` rule to use `semi_sep_stmts`.

- [ ] **Step 3: Regenerate parser.messages**

```bash
menhir --list-errors lib/parser.mly > /tmp/parser.messages.new
menhir --merge-errors /tmp/parser.messages.new --merge-errors lib/parser.messages lib/parser.mly > /tmp/parser.messages.merged
cp /tmp/parser.messages.merged lib/parser.messages
```

Add error messages for any new states.

- [ ] **Step 4: Handle empty program in CLI**

Update `bin/main.ml` to handle `[]` (empty program) gracefully — either print nothing or print a placeholder.

- [ ] **Step 5: Update EBNF in README.md**

```ebnf
program   = { ";" } , [ stmt , { ";" , { ";" } , stmt } , { ";" } ] ;
```

Or equivalently in prose: a program is zero or more statements separated by one or more semicolons, with optional leading and trailing semicolons.

- [ ] **Step 6: Run full test suite**

Run: `dune test`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/parser.mly lib/parser.messages test/test_parser.ml test/test_markdown.ml bin/main.ml README.md
git commit --message "feat: allow consecutive and leading semicolons in program grammar"
```
