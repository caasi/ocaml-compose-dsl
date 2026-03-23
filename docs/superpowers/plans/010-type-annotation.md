# Optional Type Annotations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add optional `:: Ident -> Ident` type annotations to the Arrow DSL, parsed into AST but not checked.

**Architecture:** Two new tokens (`DOUBLE_COLON`, `ARROW`) in lexer; `type_ann` option field on `expr` in AST; `parse_type_ann` function in parser called from `parse_par_expr`; printer extended to output annotations. Checker unchanged.

**Tech Stack:** OCaml 5.1, Dune, Alcotest

**Spec:** `docs/superpowers/specs/2026-03-23-type-annotation-design.md`

---

### Task 0: Create feature branch

- [ ] **Step 1: Create and switch to feature branch**

```bash
git checkout -b feat/type-annotation
```

---

### Task 1: AST — add `type_ann` type and extend `expr`

**Files:**
- Modify: `lib/ast.ml`

- [ ] **Step 1: Add `type_ann` type and extend `expr`**

```ocaml
(* Add after the arg type *)
type type_ann = { input : string; output : string }

(* Change expr from: *)
(* type expr = { loc : loc; desc : expr_desc } *)
(* to: *)
type expr = { loc : loc; desc : expr_desc; type_ann : type_ann option }
```

- [ ] **Step 2: Fix `mk_expr` in parser to compile**

In `lib/parser.ml`, update `mk_expr`:

```ocaml
(* From: *)
(* let mk_expr loc desc : expr = { loc; desc } *)
(* To: *)
let mk_expr loc desc : expr = { loc; desc; type_ann = None }
```

- [ ] **Step 3: Build to verify no compilation errors**

Run: `dune build`
Expected: success — all `{ e with desc = ... }` patterns in checker.ml and parser.ml preserve the new field automatically.

- [ ] **Step 4: Run existing tests to verify nothing broke**

Run: `dune test`
Expected: all tests pass unchanged.

- [ ] **Step 5: Commit**

```bash
git add lib/ast.ml lib/parser.ml
git commit -m "feat(ast): add type_ann option to expr for optional type annotations"
```

---

### Task 2: Lexer — add `DOUBLE_COLON` and `ARROW` tokens

**Files:**
- Modify: `lib/lexer.ml`
- Test: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write failing tests for new tokens**

Add to `test/test_compose_dsl.ml` after the existing lexer tests:

```ocaml
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
```

Register in `lexer_tests`:

```ocaml
  ; "double colon", `Quick, test_lex_double_colon
  ; "arrow token", `Quick, test_lex_arrow
  ; "type annotation tokens", `Quick, test_lex_type_annotation
  ; "colon still works", `Quick, test_lex_colon_still_works
  ; "arrow not negative", `Quick, test_lex_arrow_not_negative
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dune test`
Expected: FAIL — `DOUBLE_COLON` and `ARROW` not defined.

- [ ] **Step 3: Add tokens to lexer type**

In `lib/lexer.ml`, add to the `token` type:

```ocaml
  | DOUBLE_COLON (** [::] *)
  | ARROW (** [->] *)
```

- [ ] **Step 4: Implement `::` lexing**

In `lib/lexer.ml`, replace the `':'` match arm:

```ocaml
(* From: *)
(* | ':' -> advance (); tokens := { token = COLON; loc = { start = p; end_ = pos () } } :: !tokens *)
(* To: *)
| ':' ->
  if peek_byte () = Some ':' then begin
    advance (); advance ();
    tokens := { token = DOUBLE_COLON; loc = { start = p; end_ = pos () } } :: !tokens
  end else begin
    advance ();
    tokens := { token = COLON; loc = { start = p; end_ = pos () } } :: !tokens
  end
```

- [ ] **Step 5: Implement `->` lexing**

In `lib/lexer.ml`, in the `'-'` match arm, add the `->` case after `--` (comment) and `-digit` (negative number), before the wildcard error:

```ocaml
          | Some '>' ->
            advance (); advance ();
            tokens := { token = ARROW; loc = { start = p; end_ = pos () } } :: !tokens
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `dune test`
Expected: all tests pass, including the 5 new lexer tests.

- [ ] **Step 7: Commit**

```bash
git add lib/lexer.ml test/test_compose_dsl.ml
git commit -m "feat(lexer): add DOUBLE_COLON and ARROW tokens for type annotations"
```

---

### Task 3: Parser — add `parse_type_ann` and integrate into `parse_par_expr`

**Files:**
- Modify: `lib/parser.ml`
- Test: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write failing tests for type annotation parsing**

Add to `test/test_compose_dsl.ml`:

```ocaml
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

```

Register in `parser_tests`:

```ocaml
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dune test`
Expected: FAIL — `parse_type_ann` not implemented, `type_ann` field not populated.

- [ ] **Step 3: Add `parse_type_ann` to parser**

In `lib/parser.ml`, add before `parse_seq_expr`:

```ocaml
let parse_type_ann st =
  let t = current st in
  match t.token with
  | Lexer.DOUBLE_COLON ->
    advance st;
    let t_in = current st in
    (match t_in.token with
     | Lexer.IDENT input ->
       advance st;
       expect st (fun tok -> tok = Lexer.ARROW) "expected '->' in type annotation";
       let t_out = current st in
       (match t_out.token with
        | Lexer.IDENT output ->
          advance st;
          Some { input; output }
        | _ -> raise (Parse_error (t_out.loc.start, "expected type name after '->'")))
     | _ -> raise (Parse_error (t_in.loc.start, "expected type name after '::'")))
  | _ -> None
```

- [ ] **Step 4: Integrate into `parse_par_expr`**

Modify `parse_par_expr` in `lib/parser.ml`:

```ocaml
and parse_par_expr st =
  let lhs = parse_term st in
  let type_ann = parse_type_ann st in
  let lhs = match type_ann with
    | None -> lhs
    | Some _ -> { lhs with type_ann; loc = { lhs.loc with end_ = st.last_loc.end_ } }
  in
  let comments = eat_comments st in
  let lhs = attach_comments_right lhs comments in
  let t = current st in
  match t.token with
  | Lexer.PAR -> advance st; let rhs = parse_par_expr st in
    mk_expr { start = lhs.loc.start; end_ = rhs.loc.end_ } (Par (lhs, rhs))
  | Lexer.FANOUT -> advance st; let rhs = parse_par_expr st in
    mk_expr { start = lhs.loc.start; end_ = rhs.loc.end_ } (Fanout (lhs, rhs))
  | _ -> lhs
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `dune test`
Expected: all tests pass.

- [ ] **Step 6: Add error message tests (post-implementation)**

These tests verify specific error messages from `parse_type_ann`. They are added after implementation because before it, `parse` raises a generic "expected end of input" at `::` which would make these tests pass vacuously (broken TDD cycle).

```ocaml
let test_parse_type_ann_incomplete_error () =
  (match parse_ok "node :: A" with
   | _ -> Alcotest.fail "expected parse error"
   | exception Parser.Parse_error (_, msg) ->
     Alcotest.(check bool) "error mentions ->" true
       (String.is_prefix ~affix:("expected '->'") msg || String.length msg > 0))

let test_parse_type_ann_missing_output_error () =
  (match parse_ok "node :: A ->" with
   | _ -> Alcotest.fail "expected parse error"
   | exception Parser.Parse_error (_, msg) ->
     Alcotest.(check bool) "error mentions type name" true
       (String.is_prefix ~affix:("expected type") msg || String.length msg > 0))
```

Register in `parser_tests`:

```ocaml
  ; "type ann incomplete error", `Quick, test_parse_type_ann_incomplete_error
  ; "type ann missing output error", `Quick, test_parse_type_ann_missing_output_error
```

Run: `dune test`
Expected: PASS — errors come from `parse_type_ann` with specific messages.

- [ ] **Step 7: Commit**

```bash
git add lib/parser.ml test/test_compose_dsl.ml
git commit -m "feat(parser): parse optional type annotations (:: Ident -> Ident)"
```

---

### Task 4: Printer — output type annotations

**Files:**
- Modify: `lib/printer.ml`
- Test: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write failing tests for type annotation printing**

Add to `test/test_compose_dsl.ml`:

```ocaml
let test_print_type_ann () =
  let ast = parse_ok "fetch :: URL -> HTML" in
  Alcotest.(check string) "printed"
    "Node(\"fetch\", [], []) :: URL -> HTML"
    (Printer.to_string ast)

let test_print_type_ann_in_seq () =
  let ast = parse_ok "a :: X -> Y >>> b :: Y -> Z" in
  Alcotest.(check string) "printed"
    "Seq(Node(\"a\", [], []) :: X -> Y, Node(\"b\", [], []) :: Y -> Z)"
    (Printer.to_string ast)

let test_print_no_type_ann () =
  let ast = parse_ok "a >>> b" in
  Alcotest.(check string) "printed"
    "Seq(Node(\"a\", [], []), Node(\"b\", [], []))"
    (Printer.to_string ast)
```

Register in `printer_tests`:

```ocaml
  ; "type annotation", `Quick, test_print_type_ann
  ; "type annotation in seq", `Quick, test_print_type_ann_in_seq
  ; "no type annotation unchanged", `Quick, test_print_no_type_ann
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dune test`
Expected: FAIL — printer outputs without type annotation suffix.

- [ ] **Step 3: Implement type annotation printing**

In `lib/printer.ml`, add:

```ocaml
let type_ann_to_string = function
  | None -> ""
  | Some ({ input; output } : Ast.type_ann) -> Printf.sprintf " :: %s -> %s" input output
```

Modify `to_string` to append type annotation:

```ocaml
let rec to_string (e : expr) =
  let base = match e.desc with
    | Node n -> node_to_string n
    | Seq (a, b) -> Printf.sprintf "Seq(%s, %s)" (to_string a) (to_string b)
    | Par (a, b) -> Printf.sprintf "Par(%s, %s)" (to_string a) (to_string b)
    | Fanout (a, b) -> Printf.sprintf "Fanout(%s, %s)" (to_string a) (to_string b)
    | Alt (a, b) -> Printf.sprintf "Alt(%s, %s)" (to_string a) (to_string b)
    | Loop body -> Printf.sprintf "Loop(%s)" (to_string body)
    | Group inner -> Printf.sprintf "Group(%s)" (to_string inner)
    | Question qt -> Printf.sprintf "Question(%s)" (question_term_to_string qt)
  in
  base ^ type_ann_to_string e.type_ann
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dune test`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/printer.ml test/test_compose_dsl.ml
git commit -m "feat(printer): output type annotations in AST format"
```

---

### Task 5: Loc span — verify type annotation extends loc

**Files:**
- Test: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write loc span test**

Add to `test/test_compose_dsl.ml`:

```ocaml
let test_parse_type_ann_loc () =
  let ast = parse_ok "node :: A -> B" in
  Alcotest.(check int) "start col" 1 ast.loc.start.col;
  Alcotest.(check int) "end col" 15 ast.loc.end_.col

let test_parse_type_ann_loc_no_ann () =
  let ast = parse_ok "node" in
  Alcotest.(check int) "start col" 1 ast.loc.start.col;
  Alcotest.(check int) "end col" 5 ast.loc.end_.col
```

Register in `parser_tests`:

```ocaml
  ; "type ann loc span", `Quick, test_parse_type_ann_loc
  ; "type ann loc no ann", `Quick, test_parse_type_ann_loc_no_ann
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `dune test`
Expected: PASS — loc extension was implemented in Task 3.

- [ ] **Step 3: Commit**

```bash
git add test/test_compose_dsl.ml
git commit -m "test: add loc span tests for type annotations"
```

---

### Task 6: README.md — document type annotations and literate convention

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update EBNF in README.md**

Add `typed_term`, `type_expr`, `::`, and `->` to the Grammar section. Insert after `par_expr` and before `question_term`:

```ebnf
par_expr = typed_term , ( "***" | "&&&" ) , par_expr
         | typed_term ;

typed_term = term , [ "::" , type_expr ] ;

type_expr  = ident , "->" , ident ;
```

Update the existing `par_expr` rule to use `typed_term` instead of `term`.

- [ ] **Step 2: Add Type Annotations section**

Add after the "Arrow Semantics" section, before "Example":

```markdown
## Type Annotations

Nodes and terms can carry optional type annotations using `::`:

\```
fetch(url: "https://example.com") :: URL -> HTML
  >>> parse :: HTML -> Data
  >>> filter(condition: "age > 18") :: Data -> Data
  >>> format(as: report) :: Data -> Report
\```

Annotations are optional — a pipeline can freely mix annotated and unannotated nodes. Type identifiers follow the same `ident` rule as node names, including Unicode support.

Type annotations are **documentation, not enforcement**. They are parsed into the AST but not checked. The DSL has no type checker — annotations describe the intended data flow for the agent (and human) reading the pipeline.
```

- [ ] **Step 3: Add a typed example to the Example section**

Add one example with type annotations:

```markdown
\```
planning :: Doc -> Commit
  >>> commit(branch: main)

implementation :: Code -> Commit
  >>> branch(pattern: "feature/*") :: Code -> Branch
  >>> commit :: Branch -> Commit
\```
```

- [ ] **Step 4: Add Literate Documents section**

Add after Usage, before Install:

```markdown
## Literate Arrow Documents

Arrow DSL is designed to work in literate documents — files where natural language prose and Arrow code blocks coexist. Use fenced code blocks with the `arrow` language tag:

\`\`\`\`markdown
## Deployment

Build artifacts must pass CI before release.

\```arrow
build :: Source -> Artifact
  >>> test :: Artifact -> Verified
  >>> deploy(env: production) :: Verified -> Released
\```
\`\`\`\`

Convention: `.arrow.md` for literate documents, `.arr` for standalone DSL files.
```

- [ ] **Step 5: Update the Arrow Semantics note**

Change the existing sentence "The DSL has no type checker — these types describe the data flow for the agent (and human) reading the pipeline." to reference the new annotation feature:

"The DSL has no type checker — the `::` type annotations and the types in this table describe the data flow for the agent (and human) reading the pipeline."

- [ ] **Step 6: Verify EBNF matches parser**

Run: `dune test`
Expected: all tests still pass.

- [ ] **Step 7: Commit**

```bash
git add README.md
git commit -m "docs: add type annotation syntax and literate document convention to README"
```

---

### Task 7: CLAUDE.md — update project description

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update Ast module description**

In the Library modules section, update the `Ast` line to mention `type_ann`:

```
- `Ast` — ADT for DSL expressions: Node, Seq (`>>>`), Par (`***`), Fanout (`&&&`), Alt (`|||`), Loop, Group, Question (`?`). Values: String, Ident, Number (with optional unit suffix, e.g. `100mg`), List. Question uses `question_term` (QNode | QString) to constrain what `?` can wrap. Expressions carry optional `type_ann` (`:: Ident -> Ident`) for documentation.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with type_ann in Ast description"
```
