# String Literal as First-Class Expression — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Make string literals valid expressions so they can be used as positional arguments, in pipelines, and anywhere a `term` can appear.

**Architecture:** Add `StringLit of string` to `expr_desc`, remove the `question_term` intermediate type, and change `Question of question_term` to `Question of expr`. Update all downstream modules (parser, reducer, checker, printer) and their pattern matches. TDD: write failing tests first, then implement.

**Tech Stack:** OCaml 5.1, Alcotest, dune

**Spec:** `docs/superpowers/specs/2026-03-26-string-literal-expr-design.md`

---

### Task 1: AST — Add `StringLit`, remove `question_term`, change `Question`

**Files:**
- Modify: `lib/ast.ml`

This task will break compilation across the entire project. That's expected — subsequent tasks fix each module one by one.

- [x] **Step 1: Remove `question_term` type and update `expr_desc`**

In `lib/ast.ml`, delete the `question_term` type (lines 14–16) and modify `expr_desc`:

```ocaml
(* DELETE these lines: *)
type question_term =
  | QNode of node
  | QString of string

(* In expr_desc, REPLACE: *)
  | Question of question_term
(* WITH: *)
  | StringLit of string              (** string literal as expression *)
  | Question of expr                 (** [?] — parser restricts to Node/StringLit *)
```

The full `expr_desc` should be:

```ocaml
type expr = { loc : loc; desc : expr_desc; type_ann : type_ann option }
and expr_desc =
  | Node of node
  | StringLit of string              (** string literal as expression *)
  | Seq of expr * expr               (** [>>>] *)
  | Par of expr * expr               (** [***] *)
  | Fanout of expr * expr            (** [&&&] *)
  | Alt of expr * expr               (** [|||] *)
  | Loop of expr
  | Group of expr
  | Question of expr                 (** [?] — parser restricts to Node/StringLit *)
  | Lambda of string list * expr     (** [\x, y -> body] *)
  | Var of string                    (** [variable reference] *)
  | App of expr * expr list          (** [f(arg1, arg2)] *)
  | Let of string * expr * expr      (** [let x = expr] followed by rest of program *)
```

- [x] **Step 2: Verify the project does NOT compile**

Run: `dune build 2>&1 | head -5`
Expected: Compilation errors in printer.ml, parser.ml, reducer.ml, checker.ml, and tests (missing `question_term`, exhaustiveness warnings for `StringLit`).

- [x] **Step 3: Commit**

```bash
git add lib/ast.ml
git commit -m "feat(ast): add StringLit, remove question_term, change Question to take expr"
```

---

### Task 2: Printer — Handle `StringLit` and new `Question`

**Files:**
- Modify: `lib/printer.ml`
- Test: `test/test_compose_dsl.ml` (printer tests)

- [x] **Step 1: Write failing tests**

Add to `test/test_compose_dsl.ml`, near the existing `test_print_question_string` / `test_print_question_node`:

```ocaml
let test_print_string_lit () =
  let ast = parse_ok {|"hello" >>> a|} in
  let s = Printer.to_string ast in
  Alcotest.(check string) "string lit"
    {|Seq(StringLit("hello"), Node("a", [], []))|}
    s
```

Register in `printer_tests`:
```ocaml
  ; "string lit", `Quick, test_print_string_lit
```

- [x] **Step 2: Update printer.ml**

Delete `question_term_to_string` entirely. In `to_string`, replace:

```ocaml
    | Question qt -> Printf.sprintf "Question(%s)" (question_term_to_string qt)
```

with:

```ocaml
    | StringLit s -> Printf.sprintf "StringLit(%S)" s
    | Question inner -> Printf.sprintf "Question(%s)" (to_string inner)
```

- [x] **Step 3: Update existing printer test expectations**

`test_print_question_string` — change expected from:
```
Seq(Question(QString("earth is not flat")), ...)
```
to:
```
Seq(Question(StringLit("earth is not flat")), ...)
```

`test_print_question_node` — change expected from:
```
Seq(Question(QNode("validate", [method: Ident("test_suite")], [])), ...)
```
to:
```
Seq(Question(Node("validate", [method: Ident("test_suite")], [])), ...)
```

- [x] **Step 4: Verify printer.ml compiles (other modules still broken)**

Run: `dune build 2>&1 | grep "Error" | grep -v "printer" | head -5`
Expected: Errors in parser.ml, reducer.ml, checker.ml — but NOT printer.ml.

- [x] **Step 5: Commit**

```bash
git add lib/printer.ml test/test_compose_dsl.ml
git commit -m "feat(printer): handle StringLit and Question(expr)"
```

---

### Task 3: Reducer — Add `StringLit` passthrough to all functions

**Files:**
- Modify: `lib/reducer.ml`
- Test: `test/test_compose_dsl.ml` (reducer tests)

- [x] **Step 1: Write failing test**

Add to test file near existing reducer tests:

```ocaml
let test_reduce_string_lit_passthrough () =
  let ast = reduce_ok {|"hello" >>> a|} in
  Alcotest.(check string) "printed"
    {|Seq(StringLit("hello"), Node("a", [], []))|}
    (Printer.to_string ast)

let test_reduce_string_lit_as_arg () =
  let ast = reduce_ok ({|let f = \x -> x >>> a|} ^ "\n" ^ {|f("hello")|}) in
  Alcotest.(check string) "printed"
    {|Seq(StringLit("hello"), Node("a", [], []))|}
    (Printer.to_string ast)
```

```ocaml
let test_reduce_string_lit_apply_error () =
  reduce_fails ({|let s = "hello"|} ^ "\n" ^ {|s("world")|})
```

Register in `reducer_tests`:
```ocaml
  ; "string lit passthrough", `Quick, test_reduce_string_lit_passthrough
  ; "string lit as arg", `Quick, test_reduce_string_lit_as_arg
  ; "string lit apply error", `Quick, test_reduce_string_lit_apply_error
```

- [x] **Step 2: Update all pattern matches in reducer.ml**

**`free_vars`** — change:
```ocaml
  | Node _ | Question _ -> StringSet.empty
```
to:
```ocaml
  | Node _ | StringLit _ -> StringSet.empty
  | Question inner -> free_vars inner
```

**`desugar`** — change:
```ocaml
  | Node _ | Var _ | Question _ -> e
```
to:
```ocaml
  | Node _ | Var _ | StringLit _ -> e
  | Question inner -> { e with desc = Question (desugar inner) }
```

**`substitute`** — change:
```ocaml
  | Node _ | Question _ -> e
```
to:
```ocaml
  | Node _ | StringLit _ -> e
  | Question inner -> { e with desc = Question (substitute fresh_name name replacement inner) }
```

**`beta_reduce`** — change:
```ocaml
  | Node _ | Var _ | Question _ | Let _ -> e
```
to:
```ocaml
  | Node _ | Var _ | StringLit _ | Let _ -> e
  | Question inner -> { e with desc = Question (beta_reduce fresh_name inner) }
```

Also in `beta_reduce`, the `App` branch matches on `fn'.desc` to give specific errors. Add a `StringLit` case:
```ocaml
     | StringLit s ->
       raise (Reduce_error (e.loc.start,
         Printf.sprintf "'%s' is a string literal and cannot be applied" s))
```

**`verify`** — change:
```ocaml
  | Node _ | Question _ -> ()
```
to:
```ocaml
  | Node _ | StringLit _ -> ()
  | Question inner -> verify inner
```

- [x] **Step 3: Verify reducer.ml compiles**

Run: `dune build 2>&1 | grep "Error" | grep -v "reducer\|printer" | head -5`
Expected: Errors only in parser.ml, checker.ml, tests.

- [x] **Step 4: Commit**

```bash
git add lib/reducer.ml test/test_compose_dsl.ml
git commit -m "feat(reducer): add StringLit passthrough, recurse into Question(expr)"
```

---

### Task 4: Checker — Add `StringLit` leaf handling

**Files:**
- Modify: `lib/checker.ml`
- Test: `test/test_compose_dsl.ml` (checker tests)

- [x] **Step 1: Write failing test**

```ocaml
let test_check_string_lit_no_error () =
  let _ = check_ok {|"hello" >>> a|} in
  ()

let test_check_string_lit_question_with_alt () =
  let warnings = check_ok_with_warnings {|"is valid"? >>> (yes ||| no)|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)
```

Register in `checker_tests`:
```ocaml
  ; "string lit no error", `Quick, test_check_string_lit_no_error
  ; "string lit question with alt", `Quick, test_check_string_lit_question_with_alt
```

- [x] **Step 2: Update checker.ml**

**`normalize`** — change:
```ocaml
  | Node _ | Question _ -> e
```
to:
```ocaml
  | Node _ | StringLit _ -> e
  | Question inner -> { e with desc = Question (normalize inner) }
```

**`scan_questions`** — change:
```ocaml
    | Node _ -> counter
```
to:
```ocaml
    | Node _ | StringLit _ -> counter
```

And change:
```ocaml
    | Lambda _ | Var _ | App _ | Let _ -> counter
```
to (just for clarity, `StringLit` is already handled above):
```ocaml
    | Lambda _ | Var _ | App _ | Let _ -> counter
```

**`tail_has_question`** — the catch-all `_ -> false` covers `StringLit` already. No change needed.

**`go`** — change:
```ocaml
    | Question _ -> ()
```
to:
```ocaml
    | StringLit _ -> ()
    | Question _ -> ()
```

- [x] **Step 3: Verify checker.ml compiles**

Run: `dune build 2>&1 | grep "Error" | grep -v "checker\|reducer\|printer" | head -5`
Expected: Errors only in parser.ml and tests.

- [x] **Step 4: Commit**

```bash
git add lib/checker.ml test/test_compose_dsl.ml
git commit -m "feat(checker): add StringLit leaf handling, update Question patterns"
```

---

### Task 5: Parser — Accept bare strings, update Question construction

**Files:**
- Modify: `lib/parser.ml`
- Test: `test/test_compose_dsl.ml` (parser tests)

- [x] **Step 1: Write failing tests**

```ocaml
let test_parse_string_lit () =
  match desc_of {|"hello" >>> a|} with
  | Ast.Seq ({ desc = Ast.StringLit "hello"; _ }, { desc = Ast.Node { name = "a"; _ }; _ }) -> ()
  | other -> Alcotest.fail (Printf.sprintf "unexpected: %s" (Printer.to_string { loc = { start = { line = 1; col = 1 }; end_ = { line = 1; col = 1 } }; desc = other; type_ann = None }))

let test_parse_string_lit_positional_arg () =
  let ast = reduce_ok "let greet = \\name -> hello(name)\ngreet(\"alice\")" in
  Alcotest.(check string) "printed"
    {|Node("hello", [], [])|}
    (Printer.to_string ast)
```

Wait — `hello(name)` where `name` is in scope would produce `App(Node("hello"), [Var("name")])`, and after reduction with `"alice"` it becomes `App(Node("hello"), [StringLit("alice")])`. But `Node("hello")` is not a lambda, so `beta_reduce` would error with "'hello' is not a function". Let me use a simpler test:

```ocaml
let test_parse_string_lit () =
  match desc_of {|"hello" >>> a|} with
  | Ast.Seq ({ desc = Ast.StringLit "hello"; _ }, { desc = Ast.Node { name = "a"; _ }; _ }) -> ()
  | _ -> Alcotest.fail "expected Seq(StringLit, Node)"

let test_parse_string_lit_as_positional_arg () =
  let ast = reduce_ok ({|let f = \x -> x >>> a|} ^ "\n" ^ {|f("hello")|}) in
  Alcotest.(check string) "printed"
    {|Seq(StringLit("hello"), Node("a", [], []))|}
    (Printer.to_string ast)

let test_parse_string_lit_alone () =
  match desc_of {|"just a string"|} with
  | Ast.StringLit "just a string" -> ()
  | _ -> Alcotest.fail "expected StringLit"

let test_parse_string_lit_in_par () =
  match desc_of {|"left" *** "right"|} with
  | Ast.Par ({ desc = Ast.StringLit "left"; _ }, { desc = Ast.StringLit "right"; _ }) -> ()
  | _ -> Alcotest.fail "expected Par(StringLit, StringLit)"
```

Register in `parser_tests`:
```ocaml
  ; "string lit", `Quick, test_parse_string_lit
  ; "string lit as positional arg", `Quick, test_parse_string_lit_as_positional_arg
  ; "string lit alone", `Quick, test_parse_string_lit_alone
  ; "string lit in par", `Quick, test_parse_string_lit_in_par
```

- [x] **Step 2: Update `parse_term` STRING branch**

Replace lines 195–203 in `lib/parser.ml`:

```ocaml
  | Lexer.STRING s ->
    advance st;
    let _ = eat_comments st in
    let t2 = current st in
    (match t2.token with
     | Lexer.QUESTION ->
       advance st;
       mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (Question (QString s))
     | _ -> raise (Parse_error (t.loc.start, "bare string is not a valid term; did you mean to add '?'?")))
```

with:

```ocaml
  | Lexer.STRING s ->
    advance st;
    let str_end = st.last_loc.end_ in
    let _ = eat_comments st in
    let t2 = current st in
    let str_expr = mk_expr { start = t.loc.start; end_ = str_end } (StringLit s) in
    (match t2.token with
     | Lexer.QUESTION ->
       advance st;
       mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (Question str_expr)
     | _ -> str_expr)
```

- [x] **Step 3: Update IDENT `?` path — `QNode` to `Question(Node expr)`**

In `parse_term`, the named-args branch (around line 233) has:

```ocaml
            mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (Question (QNode n))
```

Replace with:

```ocaml
            let node_expr = mk_expr { start = t.loc.start; end_ = rparen_end } (Node n) in
            mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (Question node_expr)
```

And around line 287:

```ocaml
            mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (Question (QNode n))
```

Replace with:

```ocaml
            let node_expr = mk_expr { start = t.loc.start; end_ = ident_end } (Node n) in
            mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (Question node_expr)
```

- [x] **Step 4: Update `attach_comments_right`**

Replace:
```ocaml
    | Question (QNode n) -> { e with desc = Question (QNode { n with comments = n.comments @ comments }) }
    | Question (QString _) -> e
```

with:

```ocaml
    | StringLit _ -> e
    | Question inner -> { e with desc = Question (attach_comments_right inner comments) }
```

This recurses into the inner expression. For `Question(Node n)`, comments will be attached to the node. For `Question(StringLit _)`, comments are dropped (same as old `QString` behavior).

- [x] **Step 5: Update error message**

Replace line 306:
```ocaml
  | _ -> raise (Parse_error (t.loc.start, "expected node, string with '?', '(', 'loop', or '\\' (lambda)"))
```

with:

```ocaml
  | _ -> raise (Parse_error (t.loc.start, "expected node, string, '(', 'loop', or '\\' (lambda)"))
```

- [x] **Step 6: Update existing test expectations**

Tests that match `Ast.Question (Ast.QString s)` need to change to `Ast.Question { desc = Ast.StringLit s; _ }`:

- `test_parse_string_question` (line 855): `Question (Ast.QString "earth is not flat")` → `Question { desc = Ast.StringLit "earth is not flat"; _ }`
- `test_parse_question_with_space` (line 872): `Question (Ast.QString "hello")` → `Question { desc = Ast.StringLit "hello"; _ }`
- `test_parse_question_in_loop` (line 884): `Question (Ast.QString "all pass")` → `Question { desc = Ast.StringLit "all pass"; _ }`
- `test_parse_question_in_group` (line 890): `Question (Ast.QString "is valid")` → `Question { desc = Ast.StringLit "is valid"; _ }`
- `test_parse_comment_on_string_question` (line 770): `Question (Ast.QString "hello")` → `Question { desc = Ast.StringLit "hello"; _ }`

Tests that match `Ast.Question (Ast.QNode { ... })` need to change to `Ast.Question { desc = Ast.Node { ... }; _ }`:

- `test_parse_node_question` (line 861): `Question (Ast.QNode { name = "validate"; _ })` → `Question { desc = Ast.Node { name = "validate"; _ }; _ }`
- `test_parse_bare_node_question` (line 866): `Question (Ast.QNode { name = "check"; args = []; _ })` → `Question { desc = Ast.Node { name = "check"; args = []; _ }; _ }`
- `test_parse_comment_on_node_question` (line 763): `Question (Ast.QNode { name = "validate"; comments = ["important"]; _ })` → `Question { desc = Ast.Node { name = "validate"; comments = ["important"]; _ }; _ }`

Tests for bare string error — these tests must be **removed or replaced** since bare strings are now valid:

- `test_parse_bare_string_error` (line 875–876): Change to a success test
- `test_parse_bare_string_alone_error` (line 878–879): Change to a success test

Remove from `parser_tests`:
```ocaml
  ; "error: bare string", `Quick, test_parse_bare_string_error
  ; "error: bare string alone", `Quick, test_parse_bare_string_alone_error
```

Replace the test functions:

```ocaml
let test_parse_bare_string_in_seq () =
  match desc_of {|"bare string" >>> a|} with
  | Ast.Seq ({ desc = Ast.StringLit "bare string"; _ }, _) -> ()
  | _ -> Alcotest.fail "expected Seq(StringLit, ...)"

let test_parse_bare_string_alone () =
  match desc_of {|"just a string"|} with
  | Ast.StringLit "just a string" -> ()
  | _ -> Alcotest.fail "expected StringLit"
```

Register replacements in `parser_tests`:
```ocaml
  ; "bare string in seq", `Quick, test_parse_bare_string_in_seq
  ; "bare string alone", `Quick, test_parse_bare_string_alone
```

- [x] **Step 7: Run all tests**

Run: `dune test`
Expected: All tests pass.

- [x] **Step 8: Commit**

```bash
git add lib/parser.ml test/test_compose_dsl.ml
git commit -m "feat(parser): accept bare string literals as terms, update Question construction"
```

---

### Task 6: EBNF and documentation updates

**Files:**
- Modify: `README.md` (EBNF grammar section)
- Modify: `CLAUDE.md` (Ast documentation)

- [x] **Step 1: Update EBNF in README.md**

Replace the `term` and `question_term` productions (lines 35–44) with:

```ebnf
term     = node , [ "?" ]                          (* node, optionally question *)
         | string , [ "?" ]                        (* string literal, optionally question;
                                                      AST represents both as Question(expr) *)
         | "loop" , "(" , seq_expr , ")"            (* feedback loop *)
         | "(" , seq_expr , ")"                    (* grouping *)
         | lambda
         ;
```

Delete the standalone `question_term` production entirely.

- [x] **Step 2: Update CLAUDE.md Ast documentation**

In the `Ast` bullet point, add `StringLit` to the list of ADT variants and update the `Question` description. Change:

> `Ast` — ADT for DSL expressions: Node, Seq (`>>>`), Par (`***`), Fanout (`&&&`), Alt (`|||`), Loop, Group, Question (`?`), Lambda (`\x -> body`), Var (variable reference), App (positional application), Let (`let x = expr`). Lambda, Var, App, and Let are reduced away by the Reducer before structural checking. Values: String, Ident, Number (with optional unit suffix, e.g. `100mg`), List. Question uses `question_term` (QNode | QString) to constrain what `?` can wrap.

to:

> `Ast` — ADT for DSL expressions: Node, StringLit (string literal as expression), Seq (`>>>`), Par (`***`), Fanout (`&&&`), Alt (`|||`), Loop, Group, Question (`?`), Lambda (`\x -> body`), Var (variable reference), App (positional application), Let (`let x = expr`). Lambda, Var, App, and Let are reduced away by the Reducer before structural checking. Values: String, Ident, Number (with optional unit suffix, e.g. `100mg`), List. Question takes an `expr` directly (parser restricts to Node or StringLit).

- [x] **Step 3: Run full test suite**

Run: `dune test`
Expected: All tests pass.

- [x] **Step 4: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: update EBNF grammar and Ast documentation for StringLit"
```

---

### Task 7: Final verification

- [x] **Step 1: Run full test suite one more time**

Run: `dune test`
Expected: All tests pass.

- [x] **Step 2: Test the CLI with the motivating example**

Run:
```bash
echo 'let greet = \name -> hello >>> name
greet("alice")' | dune exec ocaml-compose-dsl
```
Expected: Success (exit 0), outputs `Seq(Node("hello", [], []), StringLit("alice"))`.

- [x] **Step 3: Test string question still works via CLI**

Run:
```bash
echo '"is this ok"? >>> (yes ||| no)' | dune exec ocaml-compose-dsl
```
Expected: Success, outputs `Seq(Question(StringLit("is this ok")), Group(Alt(Node("yes", [], []), Node("no", [], []))))`.

- [x] **Step 4: Test bare string alone via CLI**

Run:
```bash
echo '"hello world"' | dune exec ocaml-compose-dsl
```
Expected: Success, outputs `StringLit("hello world")`.
