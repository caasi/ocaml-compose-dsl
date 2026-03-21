# Question Operator (`?`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `?` (question) operator to produce explicit Either values for `|||` branching, with well-formedness warnings.

**Architecture:** Four-layer change following existing module boundaries: Lexer (new token) → Parser (new term) → Checker (warning mechanism) → Printer (new format). AST gets a `question_term` type. CLI pipes warnings to stderr. TDD throughout.

**Tech Stack:** OCaml 5.1, Dune, Alcotest

**Spec:** `docs/superpowers/specs/2026-03-22-question-operator-design.md`

---

### Task 1: AST — Add `question_term` type and `Question` variant

**Files:**
- Modify: `lib/ast.ml`

- [ ] **Step 1: Add `question_term` type and `Question` variant to `expr`**

In `lib/ast.ml`, add between the `node` type and `expr` type:

```ocaml
type question_term =
  | QNode of node
  | QString of string
```

And add to the `expr` type:

```ocaml
  | Question of question_term
```

- [ ] **Step 2: Verify the project builds (expect exhaustive match warnings)**

Run: `dune build 2>&1`
Expected: Build succeeds but with warnings about non-exhaustive pattern matches in `parser.ml`, `checker.ml`, `printer.ml`. This confirms the compiler sees the new variant. These will be fixed in subsequent tasks.

- [ ] **Step 3: Commit**

```bash
git add lib/ast.ml
git commit -m "feat(ast): add question_term type and Question variant"
```

---

### Task 2: Lexer — Add `QUESTION` token

**Files:**
- Modify: `lib/lexer.ml`
- Test: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write failing test — `?` tokenizes to `QUESTION`**

Add to `test/test_compose_dsl.ml` after the existing lexer tests:

```ocaml
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
```

Register in `lexer_tests`:

```ocaml
  ; "question token", `Quick, test_lex_question
  ; "question with space", `Quick, test_lex_question_with_space
  ; "question after string", `Quick, test_lex_question_after_string
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dune test 2>&1 | tail -20`
Expected: Compilation error — `Lexer.QUESTION` is not defined.

- [ ] **Step 3: Add `QUESTION` token to lexer**

In `lib/lexer.ml`, add `QUESTION` to the `token` type (after `LOOP`):

```ocaml
  | QUESTION
```

In the `match c with` block inside the `while` loop (before the catch-all `| c ->` line), add:

```ocaml
      | '?' -> tokens := { token = QUESTION; pos = p } :: !tokens; advance ()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dune test 2>&1 | tail -20`
Expected: All 3 new lexer tests PASS. Existing tests still pass.

- [ ] **Step 5: Commit**

```bash
git add lib/lexer.ml test/test_compose_dsl.ml
git commit -m "feat(lexer): add QUESTION token for '?'"
```

---

### Task 3: Parser — Parse `question_term`

**Files:**
- Modify: `lib/parser.ml`
- Test: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write failing tests — `string?` and `node?` parse to `Question`**

Add to `test/test_compose_dsl.ml` after existing parser tests:

```ocaml
let test_parse_string_question () =
  let ast = parse_ok {|"earth is not flat"? >>> (believe ||| doubt)|} in
  match ast with
  | Ast.Seq (Ast.Question (Ast.QString "earth is not flat"), Ast.Group (Ast.Alt (Ast.Node _, Ast.Node _))) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "unexpected AST: %s" (Printer.to_string ast))

let test_parse_node_question () =
  let ast = parse_ok "validate(method: test_suite)? >>> (deploy ||| rollback)" in
  match ast with
  | Ast.Seq (Ast.Question (Ast.QNode { name = "validate"; _ }), Ast.Group (Ast.Alt _)) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "unexpected AST: %s" (Printer.to_string ast))

let test_parse_bare_node_question () =
  let ast = parse_ok "check? >>> (yes ||| no)" in
  match ast with
  | Ast.Seq (Ast.Question (Ast.QNode { name = "check"; args = []; _ }), _) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "unexpected AST: %s" (Printer.to_string ast))

let test_parse_question_with_space () =
  let ast = parse_ok {|"hello" ? >>> (a ||| b)|} in
  match ast with
  | Ast.Seq (Ast.Question (Ast.QString "hello"), _) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "unexpected AST: %s" (Printer.to_string ast))

let test_parse_bare_string_error () =
  parse_fails {|"bare string" >>> a|}

let test_parse_bare_string_alone_error () =
  parse_fails {|"just a string"|}

let test_parse_question_in_loop () =
  let ast = parse_ok {|loop(generate >>> "all pass"? >>> (exit ||| continue))|} in
  match ast with
  | Ast.Loop (Ast.Seq (_, Ast.Seq (Ast.Question (Ast.QString "all pass"), Ast.Group (Ast.Alt _)))) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "unexpected AST: %s" (Printer.to_string ast))

let test_parse_question_in_group () =
  let ast = parse_ok {|("is valid"?) >>> (accept ||| reject)|} in
  match ast with
  | Ast.Seq (Ast.Group (Ast.Question (Ast.QString "is valid")), _) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "unexpected AST: %s" (Printer.to_string ast))
```

Register in `parser_tests`:

```ocaml
  ; "string question", `Quick, test_parse_string_question
  ; "node question", `Quick, test_parse_node_question
  ; "bare node question", `Quick, test_parse_bare_node_question
  ; "question with space", `Quick, test_parse_question_with_space
  ; "error: bare string", `Quick, test_parse_bare_string_error
  ; "error: bare string alone", `Quick, test_parse_bare_string_alone_error
  ; "question in loop", `Quick, test_parse_question_in_loop
  ; "question in group", `Quick, test_parse_question_in_group
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dune test 2>&1 | tail -20`
Expected: FAIL — parser doesn't handle STRING or QUESTION tokens in `parse_term`.

- [ ] **Step 3: Update `attach_comments_right` for `Question`**

In `lib/parser.ml`, add the `Question` case to `attach_comments_right` (after the `Loop` line):

```ocaml
    | Question (QNode n) -> Question (QNode { n with comments = n.comments @ comments })
    | Question (QString _) -> expr
```

- [ ] **Step 4: Implement `parse_term` changes**

In `lib/parser.ml`, modify `parse_term`. Add two new cases before the catch-all error:

```ocaml
  | Lexer.STRING s ->
    advance st;
    let _ = eat_comments st in
    let t2 = current st in
    (match t2.token with
     | Lexer.QUESTION ->
       advance st;
       Question (QString s)
     | _ -> raise (Parse_error (t.pos, "bare string is not a valid term; did you mean to add '?'?")))
  | Lexer.IDENT name ->
    advance st;
    let t = current st in
    (match t.token with
     | Lexer.LPAREN ->
       advance st;
       let args = parse_args st in
       expect st (fun t -> t = Lexer.RPAREN) "expected ')'";
       let comments = eat_comments st in
       let n = { name; args; comments } in
       let t2 = current st in
       (match t2.token with
        | Lexer.QUESTION -> advance st; Question (QNode n)
        | _ -> Node n)
     | _ ->
       let comments = eat_comments st in
       let n = { name; args = []; comments } in
       let t2 = current st in
       (match t2.token with
        | Lexer.QUESTION -> advance st; Question (QNode n)
        | _ -> Node n))
```

Update the catch-all error message:

```ocaml
  | _ -> raise (Parse_error (t.pos, "expected node, string with '?', '(' or 'loop'"))
```

Note: The existing `IDENT` case is replaced with the new version that checks for trailing `?`. The existing `LOOP` and `LPAREN` cases remain unchanged.

- [ ] **Step 5: Run tests to verify they pass**

Run: `dune test 2>&1 | tail -20`
Expected: All 7 new parser tests PASS. All existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add lib/parser.ml test/test_compose_dsl.ml
git commit -m "feat(parser): parse question_term (string? and node?)"
```

---

### Task 4: Printer — Add `Question` output

**Files:**
- Modify: `lib/printer.ml`
- Test: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write failing tests**

Add to `test/test_compose_dsl.ml` after existing printer tests:

```ocaml
let test_print_question_string () =
  let ast = parse_ok {|"earth is not flat"? >>> (believe ||| doubt)|} in
  let s = Printer.to_string ast in
  Alcotest.(check string) "question string" {|Seq(Question(QString("earth is not flat")), Group(Alt(Node("believe", [], []), Node("doubt", [], []))))|} s

let test_print_question_node () =
  let ast = parse_ok "validate(method: test_suite)? >>> (deploy ||| rollback)" in
  let s = Printer.to_string ast in
  Alcotest.(check string) "question node" {|Seq(Question(QNode("validate", [method: Ident("test_suite")], [])), Group(Alt(Node("deploy", [], []), Node("rollback", [], []))))|} s
```

Register in `printer_tests`:

```ocaml
  ; "question string", `Quick, test_print_question_string
  ; "question node", `Quick, test_print_question_node
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dune test 2>&1 | tail -20`
Expected: FAIL — non-exhaustive match in `printer.ml` `to_string`.

- [ ] **Step 3: Add `Question` cases to printer**

In `lib/printer.ml`, add a `question_term_to_string` function and the `Question` case:

```ocaml
let question_term_to_string = function
  | QNode n -> Printf.sprintf "QNode(%s)" (node_to_string_inner n)
  | QString s -> Printf.sprintf "QString(%S)" s
```

Where `node_to_string_inner` is the existing `node_to_string` body extracted (without the `Node(...)` wrapper). Refactor `node_to_string` to use it:

```ocaml
let node_to_string_inner (n : node) =
  Printf.sprintf "%S, [%s], [%s]"
    n.name
    (String.concat ", " (List.map arg_to_string n.args))
    (String.concat ", " (List.map (Printf.sprintf "%S") n.comments))

let node_to_string (n : node) =
  Printf.sprintf "Node(%s)" (node_to_string_inner n)

let question_term_to_string = function
  | QNode n -> Printf.sprintf "QNode(%s)" (node_to_string_inner n)
  | QString s -> Printf.sprintf "QString(%S)" s
```

Add to `to_string`:

```ocaml
  | Question qt -> Printf.sprintf "Question(%s)" (question_term_to_string qt)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dune test 2>&1 | tail -20`
Expected: All 2 new printer tests PASS. All existing tests still pass.

- [ ] **Step 5: Commit**

```bash
git add lib/printer.ml test/test_compose_dsl.ml
git commit -m "feat(printer): add Question output format"
```

---

### Task 5: Checker — Add warning mechanism and `?` without `|||` rule

**Files:**
- Modify: `lib/checker.ml`
- Test: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write failing tests**

Add to `test/test_compose_dsl.ml`:

```ocaml
let check_warnings input =
  let ast = parse_ok input in
  let result = Checker.check ast in
  result.warnings

let check_ok_with_warnings input =
  let ast = parse_ok input in
  let result = Checker.check ast in
  Alcotest.(check int) "no errors" 0 (List.length result.errors);
  result.warnings

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
```

Register in `checker_tests`:

```ocaml
  ; "question with alt", `Quick, test_check_question_with_alt
  ; "question without alt", `Quick, test_check_question_without_alt
  ; "question with intermediate steps", `Quick, test_check_question_with_intermediate_steps
  ; "question alt in par no match", `Quick, test_check_question_alt_in_par_no_match
  ; "question in loop", `Quick, test_check_question_in_loop
  ; "question in loop no alt", `Quick, test_check_question_in_loop_no_alt
  ; "multiple questions", `Quick, test_check_multiple_questions
  ; "multiple questions unmatched", `Quick, test_check_multiple_questions_unmatched
  ; "existing alt no warning", `Quick, test_check_existing_alt_no_warning
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dune test 2>&1 | tail -20`
Expected: Compilation error — `Checker.check` returns `error list`, not a record with `warnings`.

- [ ] **Step 3: Update existing test helpers for new checker return type**

The checker's return type changes from `error list` to `{ errors: error list; warnings: warning list }`. Update the existing helpers:

```ocaml
let check_ok input =
  let ast = parse_ok input in
  let result = Checker.check ast in
  Alcotest.(check int) "no errors" 0 (List.length result.Checker.errors);
  ast

let check_fails input =
  let ast = parse_ok input in
  let result = Checker.check ast in
  Alcotest.(check bool) "has errors" true (List.length result.Checker.errors > 0);
  result.Checker.errors
```

- [ ] **Step 4: Implement checker changes**

In `lib/checker.ml`, add the warning type and update `check`:

```ocaml
open Ast

type error = { message : string }
type warning = { message : string }
type result = { errors : error list; warnings : warning list }

let check expr =
  let errors = ref [] in
  let warnings = ref [] in
  let add_error msg = errors := { message = msg } :: !errors in
  let add_warning msg = warnings := { message = msg } :: !warnings in
  let rec count_question_seq = function
    | Seq (a, b) ->
      let qa = count_question_node a in
      let qb = count_question_seq b in
      qa + qb
    | e -> count_question_node e
  and count_question_node = function
    | Question _ -> 1
    | Alt _ -> -1
    | Node _ -> 0
    | Seq (a, b) -> count_question_node a + count_question_seq b
    | Par _ | Fanout _ | Loop _ | Group _ -> 0
  in
  let check_question_balance expr =
    let n = count_question_seq expr in
    let unmatched = max 0 n in
    for _ = 1 to unmatched do
      add_warning "'?' without matching '|||' in scope"
    done
  in
  let rec go = function
    | Node n ->
      if n.name = "" && n.comments = [] then
        add_error "node has no purpose (no name and no comments)"
    | Seq (a, b) -> go a; go b
    | Par (a, b) ->
      check_question_balance a;
      check_question_balance b;
      go a; go b
    | Fanout (a, b) ->
      check_question_balance a;
      check_question_balance b;
      go a; go b
    | Alt (a, b) -> go a; go b
    | Loop body ->
      let has_eval = ref false in
      let rec scan = function
        | Node n ->
          if String.length n.name >= 4 &&
             (let s = String.lowercase_ascii n.name in
              let len = String.length s in
              s = "evaluate" || s = "eval" || s = "check" || s = "test"
              || s = "judge" || s = "verify" || s = "validate"
              || (len >= 4 && String.sub s 0 4 = "eval")
              || (len >= 5 && String.sub s 0 5 = "check")) then
            has_eval := true
        | Seq (a, b) | Par (a, b) | Fanout (a, b) | Alt (a, b) -> scan a; scan b
        | Loop inner -> scan inner
        | Group inner -> scan inner
        | Question _ -> ()
      in
      scan body;
      if not !has_eval then
        add_error "loop has no evaluation/termination node (expected a node like 'evaluate', 'check', 'verify', etc.)";
      check_question_balance body;
      go body
    | Group inner ->
      check_question_balance inner;
      go inner
    | Question _ -> ()
  in
  check_question_balance expr;
  go expr;
  { errors = List.rev !errors; warnings = List.rev !warnings }
```

Key points:
- `count_question_seq` walks a `Seq` chain: `Question` → +1, `Alt` → -1. Does NOT descend into `Par`, `Fanout`, `Loop`, `Group` (those are separate scopes).
- `check_question_balance` is called at each scope boundary (top-level, Loop body, Group body, each Par/Fanout branch).
- `go` recurses into everything for error checking, calling `check_question_balance` at scope boundaries.

- [ ] **Step 5: Update `bin/main.ml` for new checker return type**

In `bin/main.ml`, update the checker result handling:

```ocaml
    | ast ->
      let result = Compose_dsl.Checker.check ast in
      List.iter
        (fun (w : Compose_dsl.Checker.warning) ->
          Printf.eprintf "warning: %s\n" w.message)
        result.warnings;
      if result.errors = [] then (
        print_endline (Compose_dsl.Printer.to_string ast);
        exit 0)
      else (
        List.iter
          (fun (e : Compose_dsl.Checker.error) ->
            Printf.eprintf "check error: %s\n" e.message)
          result.errors;
        exit 1)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `dune test 2>&1 | tail -20`
Expected: All 9 new checker tests PASS. All existing tests still pass.

- [ ] **Step 7: Commit**

```bash
git add lib/checker.ml bin/main.ml test/test_compose_dsl.ml
git commit -m "feat(checker): add warning mechanism and '?' without '|||' rule"
```

---

### Task 6: Update README EBNF and documentation

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update README EBNF**

Add the `question_term` production to the EBNF in `README.md`, before the `term` rule:

```ebnf
question_term = string , "?"
              | node , "?"
              ;
```

Update the `term` rule to include `question_term`:

```ebnf
term     = node
         | "loop" , "(" , seq_expr , ")"
         | "(" , seq_expr , ")"
         | question_term
         ;
```

- [ ] **Step 2: Add `?` to the Arrow Semantics table**

Add a row to the operator table:

```
| `?`     | question       | `Arrow a (Either a a)`                        |
```

- [ ] **Step 3: Add a `?` example to README**

Add after the existing examples:

```
"earth is not flat"?
  >>> (believe ||| doubt)
```

```
loop(
  generate >>> verify >>> "all tests pass"?
  >>> (continue ||| fix_and_retry)
)
```

- [ ] **Step 4: Update CLAUDE.md if needed**

Add `Question` to the Ast module description in CLAUDE.md:

```
- `Ast` — ADT for DSL expressions: Node, Seq (`>>>`), Par (`***`), Fanout (`&&&`), Alt (`|||`), Loop, Group, Question (`?`). Values: String, Ident, Number (with optional unit suffix, e.g. `100mg`), List. Question uses `question_term` (QNode | QString) to constrain what `?` can wrap.
```

- [ ] **Step 5: Run tests to make sure nothing broke**

Run: `dune test 2>&1 | tail -20`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: document question operator (?) in README and CLAUDE.md"
```

---

### Task 7: End-to-end CLI verification

**Files:** None (manual verification only)

- [ ] **Step 1: Test success with `?` and `|||`**

Run: `echo '"earth is not flat"? >>> (believe ||| doubt)' | dune exec ocaml-compose-dsl`
Expected stdout: `Seq(Question(QString("earth is not flat")), Group(Alt(Node("believe", [], []), Node("doubt", [], []))))`
Expected stderr: (empty)
Expected exit: 0

- [ ] **Step 2: Test warning output**

Run: `echo '"ready"? >>> process' | dune exec ocaml-compose-dsl`
Expected stdout: AST output
Expected stderr: `warning: '?' without matching '|||' in scope`
Expected exit: 0

- [ ] **Step 3: Test bare string error**

Run: `echo '"bare string" >>> a' | dune exec ocaml-compose-dsl`
Expected stderr: parse error containing `bare string is not a valid term`
Expected exit: 1

- [ ] **Step 4: Run full test suite one last time**

Run: `dune test`
Expected: All tests PASS, no warnings.

- [ ] **Step 5: Commit any remaining changes (if any)**

Only if there were fixes needed from the E2E verification.
