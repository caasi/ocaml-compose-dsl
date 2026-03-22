# AST Location Information Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add source location spans to every `expr` AST node so Checker diagnostics include line/column positions.

**Architecture:** Split `expr` into `expr = { loc; desc }` wrapper + `expr_desc` variants. Define `pos`/`loc` in `Ast`, reuse in `Lexer.located`. Parser captures half-open `[start, end_)` spans. Checker attaches loc to all errors/warnings.

**Tech Stack:** OCaml, Dune, Alcotest

**Spec:** `docs/superpowers/specs/2026-03-22-ast-loc-design.md`

---

### Task 1: Update Ast types

**Files:**
- Modify: `lib/ast.ml`

- [ ] **Step 1: Add `pos`, `loc`, and split `expr`**

Replace the entire `lib/ast.ml` with:

```ocaml
type pos = { line : int; col : int }
type loc = { start : pos; end_ : pos }

type value =
  | String of string
  | Ident of string
  | Number of string
  | List of value list

type arg = { key : string; value : value }

type node = { name : string; args : arg list; comments : string list }

type question_term =
  | QNode of node
  | QString of string

type expr = { loc : loc; desc : expr_desc }
and expr_desc =
  | Node of node
  | Seq of expr * expr (** [>>>] *)
  | Par of expr * expr (** [***] *)
  | Fanout of expr * expr (** [&&&] *)
  | Alt of expr * expr (** [|||] *)
  | Loop of expr
  | Group of expr
  | Question of question_term
```

- [ ] **Step 2: Commit**

```bash
git add lib/ast.ml
git commit -m "feat(ast): add pos/loc types and split expr into expr + expr_desc"
```

Note: the project will NOT compile after this task. That's expected — all modules must be updated together.

---

### Task 2: Update Lexer to use Ast.pos and Ast.loc

**Files:**
- Modify: `lib/lexer.ml`

- [ ] **Step 1: Replace `pos` type and `located` type**

Remove the local `pos` type definition and update `located`:

```ocaml
(* Replace these lines: *)
type pos = { line : int; col : int }
type located = { token : token; pos : pos }
exception Lex_error of pos * string

(* With: *)
open Ast
type located = { token : token; loc : loc }
exception Lex_error of pos * string
```

- [ ] **Step 2: Update `tokenize` to produce `loc` for each token**

Each token emission site currently does `{ token = ...; pos = p }`. Change every site to capture both start and end positions. The pattern is:

For single-char tokens (LPAREN, RPAREN, etc.):
```ocaml
(* Before: *)
| '(' -> tokens := { token = LPAREN; pos = p } :: !tokens; advance ()
(* After: *)
| '(' -> advance (); tokens := { token = LPAREN; loc = { start = p; end_ = pos () } } :: !tokens
```
Note: `advance ()` must happen before `pos ()` so `end_` captures the position after the character.

For multi-char tokens (operators `>>>`, `***`, `|||`, `&&&`):
```ocaml
(* Before: *)
tokens := { token = SEQ; pos = p } :: !tokens;
advance (); advance (); advance ()
(* After: *)
advance (); advance (); advance ();
tokens := { token = SEQ; loc = { start = p; end_ = pos () } } :: !tokens
```

For `read_string`, `read_ident`, `read_number`, `read_comment`:
Each of these already captures `p = pos ()` at the start. Change the return to:
```ocaml
(* e.g. read_string, after the closing quote advance: *)
{ token = STRING s; loc = { start = p; end_ = pos () } }
```

For `QUESTION`:
```ocaml
| '?' -> advance (); tokens := { token = QUESTION; loc = { start = p; end_ = pos () } } :: !tokens
```

For `EOF`:
```ocaml
(* Before: *)
let p = pos () in
List.rev ({ token = EOF; pos = p } :: !tokens)
(* After: *)
let p = pos () in
List.rev ({ token = EOF; loc = { start = p; end_ = p } } :: !tokens)
```

- [ ] **Step 3: Commit**

```bash
git add lib/lexer.ml
git commit -m "feat(lexer): use Ast.pos/loc, emit loc spans on all tokens"
```

---

### Task 3: Update Parser to capture locs on expr

**Files:**
- Modify: `lib/parser.ml`

- [ ] **Step 1: Update state type, helpers, and Parse_error**

```ocaml
open Ast

exception Parse_error of pos * string

type state = {
  mutable tokens : Lexer.located list;
  mutable last_loc : loc;
}

let dummy_loc = { start = { line = 1; col = 1 }; end_ = { line = 1; col = 1 } }

let make tokens = { tokens; last_loc = dummy_loc }

let mk_expr loc desc : expr = { loc; desc }

let current st =
  match st.tokens with
  | [] -> failwith "unexpected end of token stream"
  | t :: _ -> t

let advance st =
  match st.tokens with
  | [] -> failwith "unexpected end of token stream"
  | t :: rest ->
    st.last_loc <- t.loc;
    st.tokens <- rest

let expect st tok_match msg =
  let t = current st in
  if tok_match t.token then advance st
  else raise (Parse_error (t.loc.start, msg))
```

- [ ] **Step 2: Update `eat_comments`**

No structural change — `eat_comments` calls `advance` which now updates `last_loc`. The function remains the same.

- [ ] **Step 3: Update `parse_value` and `parse_args`**

These return `value` and `arg list` (not `expr`), so they don't need loc. Only change `t.pos` references to `t.loc.start` in error messages:

```ocaml
(* In parse_value, every Parse_error site: *)
raise (Parse_error (t.loc.start, "expected value"))
(* etc. for all Parse_error calls in parse_value and parse_args *)
```

- [ ] **Step 4: Update `attach_comments_right`**

Use `{ e with desc = ... }` pattern to preserve loc:

```ocaml
let rec attach_comments_right (e : expr) comments =
  if comments = [] then e
  else match e.desc with
    | Node n -> { e with desc = Node { n with comments = n.comments @ comments } }
    | Seq (a, b) -> { e with desc = Seq (a, attach_comments_right b comments) }
    | Par (a, b) -> { e with desc = Par (a, attach_comments_right b comments) }
    | Fanout (a, b) -> { e with desc = Fanout (a, attach_comments_right b comments) }
    | Alt (a, b) -> { e with desc = Alt (a, attach_comments_right b comments) }
    | Group inner -> { e with desc = Group (attach_comments_right inner comments) }
    | Loop inner -> { e with desc = Loop (attach_comments_right inner comments) }
    | Question (QNode n) -> { e with desc = Question (QNode { n with comments = n.comments @ comments }) }
    | Question (QString _) -> e
```

- [ ] **Step 5: Update `parse_term`**

Each branch captures start loc and builds `mk_expr`:

```ocaml
and parse_term st =
  let _ = eat_comments st in
  let t = current st in
  match t.token with
  | Lexer.STRING s ->
    advance st;
    let _ = eat_comments st in
    let t2 = current st in
    (match t2.token with
     | Lexer.QUESTION ->
       advance st;
       mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (Question (QString s))
     | _ -> raise (Parse_error (t.loc.start, "bare string is not a valid term; did you mean to add '?'?")))
  | Lexer.IDENT name ->
    advance st;
    let t_next = current st in
    (match t_next.token with
     | Lexer.LPAREN ->
       advance st;
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
     | _ ->
       let ident_end = st.last_loc.end_ in
       let comments = eat_comments st in
       let n = { name; args = []; comments } in
       let t2 = current st in
       (match t2.token with
        | Lexer.QUESTION ->
          advance st;
          mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (Question (QNode n))
        | _ ->
          mk_expr { start = t.loc.start; end_ = ident_end } (Node n)))
  | Lexer.LOOP ->
    advance st;
    expect st (fun tok -> tok = Lexer.LPAREN) "expected '(' after 'loop'";
    let body = parse_seq_expr st in
    expect st (fun tok -> tok = Lexer.RPAREN) "expected ')' to close 'loop'";
    mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (Loop body)
  | Lexer.LPAREN ->
    advance st;
    let inner = parse_seq_expr st in
    expect st (fun tok -> tok = Lexer.RPAREN) "expected ')'";
    mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (Group inner)
  | _ -> raise (Parse_error (t.loc.start, "expected node, string with '?', '(' or 'loop'"))
```

- [ ] **Step 6: Update `parse_seq_expr`, `parse_alt_expr`, `parse_par_expr`**

Binary operators use sub-expression locs:

```ocaml
let rec parse_seq_expr st =
  let lhs = parse_alt_expr st in
  let comments = eat_comments st in
  let lhs = attach_comments_right lhs comments in
  let t = current st in
  match t.token with
  | Lexer.SEQ -> advance st; let rhs = parse_seq_expr st in
    mk_expr { start = lhs.loc.start; end_ = rhs.loc.end_ } (Seq (lhs, rhs))
  | _ -> lhs

and parse_alt_expr st =
  let lhs = parse_par_expr st in
  let comments = eat_comments st in
  let lhs = attach_comments_right lhs comments in
  let t = current st in
  match t.token with
  | Lexer.ALT -> advance st; let rhs = parse_alt_expr st in
    mk_expr { start = lhs.loc.start; end_ = rhs.loc.end_ } (Alt (lhs, rhs))
  | _ -> lhs

and parse_par_expr st =
  let lhs = parse_term st in
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

- [ ] **Step 7: Update `parse` entry point**

```ocaml
let parse tokens =
  let st = make tokens in
  let expr = parse_seq_expr st in
  let t = current st in
  (match t.token with
   | Lexer.EOF -> ()
   | _ -> raise (Parse_error (t.loc.start, "expected end of input")));
  expr
```

- [ ] **Step 8: Commit**

```bash
git add lib/parser.ml
git commit -m "feat(parser): capture loc spans on all expr nodes"
```

---

### Task 4: Update Printer to match on expr.desc

**Files:**
- Modify: `lib/printer.ml`

- [ ] **Step 1: Update `to_string`**

```ocaml
let rec to_string (e : expr) =
  match e.desc with
  | Node n -> node_to_string n
  | Seq (a, b) -> Printf.sprintf "Seq(%s, %s)" (to_string a) (to_string b)
  | Par (a, b) -> Printf.sprintf "Par(%s, %s)" (to_string a) (to_string b)
  | Fanout (a, b) -> Printf.sprintf "Fanout(%s, %s)" (to_string a) (to_string b)
  | Alt (a, b) -> Printf.sprintf "Alt(%s, %s)" (to_string a) (to_string b)
  | Loop body -> Printf.sprintf "Loop(%s)" (to_string body)
  | Group inner -> Printf.sprintf "Group(%s)" (to_string inner)
  | Question qt -> Printf.sprintf "Question(%s)" (question_term_to_string qt)
```

- [ ] **Step 2: Commit**

```bash
git add lib/printer.ml
git commit -m "refactor(printer): match on expr.desc, output unchanged"
```

---

### Task 5: Update Checker to include loc in diagnostics

**Files:**
- Modify: `lib/checker.ml`

- [ ] **Step 1: Update types and helpers**

```ocaml
open Ast

type error = { loc : loc; message : string }
type warning = { loc : loc; message : string }
type result = { errors : error list; warnings : warning list }
```

- [ ] **Step 2: Update `normalize`**

```ocaml
let rec normalize (e : expr) : expr =
  match e.desc with
  | Group inner -> normalize inner
  | Seq (a, b) -> { e with desc = Seq (normalize a, normalize b) }
  | Par (a, b) -> { e with desc = Par (normalize a, normalize b) }
  | Fanout (a, b) -> { e with desc = Fanout (normalize a, normalize b) }
  | Alt (a, b) -> { e with desc = Alt (normalize a, normalize b) }
  | Loop body -> { e with desc = Loop (normalize body) }
  | Node _ | Question _ -> e
```

- [ ] **Step 3: Update `check` function**

```ocaml
let check (expr : expr) =
  let errors = ref [] in
  let warnings = ref [] in
  let add_error loc msg = errors := ({ loc; message = msg } : error) :: !errors in
  let add_warning loc msg = warnings := ({ loc; message = msg } : warning) :: !warnings in
  let rec scan_questions counter (e : expr) =
    match e.desc with
    | Question _ -> counter + 1
    | Alt _ -> max 0 (counter - 1)
    | Node _ -> counter
    | Seq (a, b) ->
      let counter' = scan_questions counter a in
      scan_questions counter' b
    | Group _ -> counter
    | Par _ | Fanout _ | Loop _ -> counter
  in
  let check_question_balance (e : expr) =
    let unmatched = scan_questions 0 (normalize e) in
    for _ = 1 to unmatched do
      add_warning e.loc "'?' without matching '|||' in scope"
    done
  in
  let rec go (e : expr) =
    match e.desc with
    | Node n ->
      if n.name = "" && n.comments = [] then
        add_error e.loc "node has no purpose (no name and no comments)"
    | Seq (a, b) -> go a; go b
    | Par (a, b) ->
      check_question_balance a;
      check_question_balance b;
      go a; go b
    | Fanout (a, b) ->
      check_question_balance a;
      check_question_balance b;
      go a; go b
    | Alt (a, b) ->
      check_question_balance a;
      check_question_balance b;
      go a; go b
    | Loop body ->
      let has_eval = ref false in
      let rec scan (e : expr) =
        match e.desc with
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
        | Question (QNode n) -> scan { loc = e.loc; desc = Node n }
        | Question (QString _) -> ()
      in
      scan body;
      if not !has_eval then
        add_error e.loc "loop has no evaluation/termination node (expected a node like 'evaluate', 'check', 'verify', etc.)";
      check_question_balance body;
      go body
    | Group inner ->
      go inner
    | Question _ -> ()
  in
  check_question_balance expr;
  go expr;
  { errors = List.rev !errors; warnings = List.rev !warnings }
```

- [ ] **Step 4: Commit**

```bash
git add lib/checker.ml
git commit -m "feat(checker): attach loc to all errors and warnings"
```

---

### Task 6: Update CLI diagnostic output

**Files:**
- Modify: `bin/main.ml`

- [ ] **Step 1: Update Checker diagnostic formatting**

Change the warning and error output lines:

```ocaml
(* Before: *)
Printf.eprintf "warning: %s\n" w.message
(* After: *)
Printf.eprintf "warning at %d:%d: %s\n" w.loc.start.line w.loc.start.col w.message

(* Before: *)
Printf.eprintf "check error: %s\n" e.message
(* After: *)
Printf.eprintf "check error at %d:%d: %s\n" e.loc.start.line e.loc.start.col e.message
```

Also update `Lexer.Lex_error` and `Parser.Parse_error` handler references — `pos.line`/`pos.col` remain the same field names since `Ast.pos` has the same structure as the old `Lexer.pos`. No change needed for those lines.

- [ ] **Step 2: Build and verify compilation**

```bash
dune build
```

Expected: compiles successfully (all modules updated).

- [ ] **Step 3: Commit**

```bash
git add bin/main.ml
git commit -m "feat(cli): show line:col in checker diagnostic output"
```

---

### Task 7: Update Lexer tests for `located.loc`

**Files:**
- Modify: `test/test_compose_dsl.ml`

- [ ] **Step 1: Update lexer test `pos` references**

Tests that access `tok.pos` must change to `tok.loc.start`. Affected tests:

- `test_lex_unicode_ident_col` (lines 245–261): `tok0.pos.col` → `tok0.loc.start.col`, etc.
- `test_lex_mixed_unicode_col` (lines 263–275): same pattern
- `test_lex_unicode_string_col` (lines 277–293): same pattern
- `test_lex_multiline_unicode_col` (lines 295–303): `tok0.pos.line` → `tok0.loc.start.line`, etc.
- `test_lex_error_col_after_unicode` (lines 311–315): `pos.col` → stays as-is (this catches `Lex_error (pos, _)` which is already `Ast.pos`)

- [ ] **Step 2: Run lexer tests**

```bash
dune exec test/test_compose_dsl.exe -- test Lexer
```

Expected: all Lexer tests pass.

- [ ] **Step 3: Commit**

```bash
git add test/test_compose_dsl.ml
git commit -m "test(lexer): update pos references to loc.start"
```

---

### Task 8: Update Parser tests for expr.desc

**Files:**
- Modify: `test/test_compose_dsl.ml`

- [ ] **Step 1: Add test helpers**

At the top of the file, after the existing helpers, add:

```ocaml
let desc_of input = (parse_ok input).desc
```

- [ ] **Step 2: Update parser tests that pattern-match on Ast variants**

Every test that does `match ast with | Ast.Seq ...` must change to `match ast.desc with | Seq ...` (inside `let open Ast in` or using qualified names). Here is the complete list of tests to update and their new bodies:

```ocaml
let test_parse_node_with_args () =
  match desc_of "read(source: \"data.csv\")" with
  | Ast.Node n ->
    Alcotest.(check string) "name" "read" n.name;
    Alcotest.(check int) "1 arg" 1 (List.length n.args);
    Alcotest.(check string) "arg key" "source" (List.hd n.args).key
  | _ -> Alcotest.fail "expected Node"

let test_parse_node_no_parens () =
  match desc_of "count" with
  | Ast.Node n ->
    Alcotest.(check string) "name" "count" n.name;
    Alcotest.(check int) "0 args" 0 (List.length n.args)
  | _ -> Alcotest.fail "expected Node"

let test_parse_node_empty_parens () =
  match desc_of "noop()" with
  | Ast.Node n ->
    Alcotest.(check string) "name" "noop" n.name;
    Alcotest.(check int) "0 args" 0 (List.length n.args)
  | _ -> Alcotest.fail "expected Node"

let test_parse_multiple_args () =
  match desc_of "load(from: cache, key: k, ttl: \"60\")" with
  | Ast.Node n ->
    Alcotest.(check int) "3 args" 3 (List.length n.args);
    Alcotest.(check string) "arg1" "from" (List.nth n.args 0).key;
    Alcotest.(check string) "arg2" "key" (List.nth n.args 1).key;
    Alcotest.(check string) "arg3" "ttl" (List.nth n.args 2).key
  | _ -> Alcotest.fail "expected Node"

let test_parse_string_value () =
  match desc_of "a(x: \"hello\")" with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.String "hello" -> ()
     | _ -> Alcotest.fail "expected String value")
  | _ -> Alcotest.fail "expected Node"

let test_parse_ident_value () =
  match desc_of "a(x: csv)" with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.Ident "csv" -> ()
     | _ -> Alcotest.fail "expected Ident value")
  | _ -> Alcotest.fail "expected Node"

let test_parse_list_value () =
  match desc_of "collect(fields: [name, email, age])" with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.List vs -> Alcotest.(check int) "3 items" 3 (List.length vs)
     | _ -> Alcotest.fail "expected List value")
  | _ -> Alcotest.fail "expected Node"

let test_parse_empty_list () =
  match desc_of "a(x: [])" with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.List vs -> Alcotest.(check int) "0 items" 0 (List.length vs)
     | _ -> Alcotest.fail "expected List value")
  | _ -> Alcotest.fail "expected Node"

let test_parse_single_item_list () =
  match desc_of "a(x: [one])" with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.List [ Ast.Ident "one" ] -> ()
     | _ -> Alcotest.fail "expected single-item List")
  | _ -> Alcotest.fail "expected Node"

let test_parse_number_value () =
  match desc_of "resize(width: 1920)" with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.Number "1920" -> ()
     | _ -> Alcotest.fail "expected Number value")
  | _ -> Alcotest.fail "expected Node"

let test_parse_float_value () =
  match desc_of "delay(seconds: 3.5)" with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.Number "3.5" -> ()
     | _ -> Alcotest.fail "expected Number value")
  | _ -> Alcotest.fail "expected Node"

let test_parse_negative_value () =
  match desc_of "adjust(offset: -10)" with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.Number "-10" -> ()
     | _ -> Alcotest.fail "expected Number value")
  | _ -> Alcotest.fail "expected Node"

let test_parse_number_in_list () =
  match desc_of "a(dims: [1920, 1080])" with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.List [Ast.Number "1920"; Ast.Number "1080"] -> ()
     | _ -> Alcotest.fail "expected List of Numbers")
  | _ -> Alcotest.fail "expected Node"

let test_parse_number_with_unit () =
  match desc_of "dose(amount: 100mg)" with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.Number "100mg" -> ()
     | _ -> Alcotest.fail "expected Number with unit")
  | _ -> Alcotest.fail "expected Node"

let test_parse_seq () =
  match desc_of "a >>> b >>> c" with
  | Ast.Seq ({ desc = Ast.Node _; _ }, { desc = Ast.Seq ({ desc = Ast.Node _; _ }, { desc = Ast.Node _; _ }); _ }) -> ()
  | _ -> Alcotest.fail "expected right-associative Seq"

let test_parse_par () =
  match desc_of "a *** b" with
  | Ast.Par ({ desc = Ast.Node _; _ }, { desc = Ast.Node _; _ }) -> ()
  | _ -> Alcotest.fail "expected Par"

let test_parse_alt () =
  match desc_of "a ||| b" with
  | Ast.Alt ({ desc = Ast.Node _; _ }, { desc = Ast.Node _; _ }) -> ()
  | _ -> Alcotest.fail "expected Alt"

let test_parse_mixed_operators () =
  match desc_of "a >>> b *** c ||| d" with
  | Ast.Seq ({ desc = Ast.Node _; _ }, { desc = Ast.Alt ({ desc = Ast.Par ({ desc = Ast.Node _; _ }, { desc = Ast.Node _; _ }); _ }, { desc = Ast.Node _; _ }); _ }) -> ()
  | _ -> Alcotest.fail "expected precedence: >>> < ||| < ***"

let test_parse_group () =
  match desc_of "(a >>> b) *** c" with
  | Ast.Par ({ desc = Ast.Group { desc = Ast.Seq _; _ }; _ }, { desc = Ast.Node _; _ }) -> ()
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
  | Ast.Loop { desc = Ast.Seq ({ desc = Ast.Node _; _ }, { desc = Ast.Seq ({ desc = Ast.Loop _; _ }, { desc = Ast.Node _; _ }); _ }); _ } -> ()
  | _ -> Alcotest.fail "expected nested Loop"

let test_parse_comments_attach_to_node () =
  let ast =
    parse_ok
      {|read(source: "data.csv") -- read the source
  >>> write(dest: "out.csv") -- write output|}
  in
  match ast.desc with
  | Ast.Seq ({ desc = Ast.Node r; _ }, { desc = Ast.Node w; _ }) ->
    Alcotest.(check int) "read comments" 1 (List.length r.comments);
    Alcotest.(check int) "write comments" 1 (List.length w.comments)
  | _ -> Alcotest.fail "expected Seq"

let test_parse_multiline_comments () =
  let ast =
    parse_ok
      {|read(source: "data.csv") -- read the source
                               -- ref: Read, cat|}
  in
  match ast.desc with
  | Ast.Node n ->
    Alcotest.(check int) "2 comments" 2 (List.length n.comments)
  | _ -> Alcotest.fail "expected Node"

let test_parse_comment_on_group () =
  let ast =
    parse_ok {|(a >>> b) -- comment on group
  >>> c|}
  in
  match ast.desc with
  | Ast.Seq ({ desc = Ast.Group { desc = Ast.Seq ({ desc = Ast.Node _; _ }, { desc = Ast.Node b; _ }); _ }; _ }, { desc = Ast.Node _; _ }) ->
    Alcotest.(check int) "comment attached to rightmost node in group" 1 (List.length b.comments);
    Alcotest.(check string) "comment text" "comment on group" (List.hd b.comments)
  | _ -> Alcotest.fail "expected Seq(Group(Seq(a,b)),c)"

let test_parse_comment_on_loop () =
  let ast =
    parse_ok {|loop (a >>> evaluate(x: y)) -- loop comment
  >>> done|}
  in
  match ast.desc with
  | Ast.Seq ({ desc = Ast.Loop { desc = Ast.Seq ({ desc = Ast.Node _; _ }, { desc = Ast.Node e; _ }); _ }; _ }, { desc = Ast.Node _; _ }) ->
    Alcotest.(check int) "comment attached to rightmost node in loop" 1 (List.length e.comments);
    Alcotest.(check string) "comment text" "loop comment" (List.hd e.comments)
  | _ -> Alcotest.fail "expected Seq(Loop(...), done)"

let test_parse_fanout () =
  match desc_of "a &&& b" with
  | Ast.Fanout ({ desc = Ast.Node _; _ }, { desc = Ast.Node _; _ }) -> ()
  | _ -> Alcotest.fail "expected Fanout"

let test_parse_precedence_seq_fanout () =
  match desc_of "a >>> b &&& c >>> d" with
  | Ast.Seq ({ desc = Ast.Node _; _ }, { desc = Ast.Seq ({ desc = Ast.Fanout ({ desc = Ast.Node _; _ }, { desc = Ast.Node _; _ }); _ }, { desc = Ast.Node _; _ }); _ }) -> ()
  | _ -> Alcotest.fail "expected Seq(a, Seq(Fanout(b,c), d))"

let test_parse_precedence_alt_par () =
  match desc_of "a ||| b *** c" with
  | Ast.Alt ({ desc = Ast.Node _; _ }, { desc = Ast.Par ({ desc = Ast.Node _; _ }, { desc = Ast.Node _; _ }); _ }) -> ()
  | _ -> Alcotest.fail "expected Alt(a, Par(b,c))"

let test_parse_par_fanout_same_prec () =
  match desc_of "a *** b &&& c" with
  | Ast.Par ({ desc = Ast.Node _; _ }, { desc = Ast.Fanout ({ desc = Ast.Node _; _ }, { desc = Ast.Node _; _ }); _ }) -> ()
  | _ -> Alcotest.fail "expected Par(a, Fanout(b,c))"

let test_parse_mixed_all_precedence () =
  match desc_of "a >>> b ||| c &&& d *** e" with
  | Ast.Seq ({ desc = Ast.Node _; _ },
      { desc = Ast.Alt ({ desc = Ast.Node _; _ },
        { desc = Ast.Fanout ({ desc = Ast.Node _; _ },
          { desc = Ast.Par ({ desc = Ast.Node _; _ }, { desc = Ast.Node _; _ }); _ }); _ }); _ }) -> ()
  | _ -> Alcotest.fail "expected Seq(a, Alt(b, Fanout(c, Par(d, e))))"

let test_parse_group_overrides_precedence () =
  match desc_of "(a >>> b) &&& c" with
  | Ast.Fanout ({ desc = Ast.Group { desc = Ast.Seq ({ desc = Ast.Node _; _ }, { desc = Ast.Node _; _ }); _ }; _ }, { desc = Ast.Node _; _ }) -> ()
  | _ -> Alcotest.fail "expected Fanout(Group(Seq(a,b)), c)"

let test_parse_unicode_node_with_args () =
  match desc_of {|翻譯(來源: "日文")|} with
  | Ast.Node n ->
    Alcotest.(check string) "name" "翻譯" n.name;
    Alcotest.(check int) "1 arg" 1 (List.length n.args);
    Alcotest.(check string) "arg key" "來源" (List.hd n.args).key;
    (match (List.hd n.args).value with
     | Ast.String "日文" -> ()
     | _ -> Alcotest.fail "expected String value")
  | _ -> Alcotest.fail "expected Node"

let test_parse_unicode_seq () =
  match desc_of "café >>> naïve" with
  | Ast.Seq ({ desc = Ast.Node a; _ }, { desc = Ast.Node b; _ }) ->
    Alcotest.(check string) "lhs" "café" a.name;
    Alcotest.(check string) "rhs" "naïve" b.name
  | _ -> Alcotest.fail "expected Seq"

let test_parse_greek_seq () =
  match desc_of "α >>> β" with
  | Ast.Seq ({ desc = Ast.Node a; _ }, { desc = Ast.Node b; _ }) ->
    Alcotest.(check string) "lhs" "α" a.name;
    Alcotest.(check string) "rhs" "β" b.name
  | _ -> Alcotest.fail "expected Seq"

let test_parse_unicode_unit_value () =
  match desc_of "wait(duration: 500ミリ秒)" with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.Number "500ミリ秒" -> ()
     | _ -> Alcotest.fail "expected Number with unicode unit")
  | _ -> Alcotest.fail "expected Node"
```

For the question operator parser tests:

```ocaml
let test_parse_comment_on_node_question () =
  let ast = parse_ok "validate -- important\n? >>> (a ||| b)" in
  match ast.desc with
  | Ast.Seq ({ desc = Ast.Question (Ast.QNode { name = "validate"; comments = ["important"]; _ }); _ }, _) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "unexpected AST: %s" (Printer.to_string ast))

let test_parse_comment_on_string_question () =
  let ast = parse_ok {|"hello" -- note
? >>> (a ||| b)|} in
  match ast.desc with
  | Ast.Seq ({ desc = Ast.Question (Ast.QString "hello"); _ }, _) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "unexpected AST: %s" (Printer.to_string ast))

let test_parse_string_question () =
  let ast = parse_ok {|"earth is not flat"? >>> (believe ||| doubt)|} in
  match ast.desc with
  | Ast.Seq ({ desc = Ast.Question (Ast.QString "earth is not flat"); _ }, { desc = Ast.Group { desc = Ast.Alt ({ desc = Ast.Node _; _ }, { desc = Ast.Node _; _ }); _ }; _ }) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "unexpected AST: %s" (Printer.to_string ast))

let test_parse_node_question () =
  let ast = parse_ok "validate(method: test_suite)? >>> (deploy ||| rollback)" in
  match ast.desc with
  | Ast.Seq ({ desc = Ast.Question (Ast.QNode { name = "validate"; _ }); _ }, { desc = Ast.Group { desc = Ast.Alt _; _ }; _ }) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "unexpected AST: %s" (Printer.to_string ast))

let test_parse_bare_node_question () =
  match desc_of "check? >>> (yes ||| no)" with
  | Ast.Seq ({ desc = Ast.Question (Ast.QNode { name = "check"; args = []; _ }); _ }, _) -> ()
  | _ -> Alcotest.fail "expected Question(QNode check)"

let test_parse_question_with_space () =
  let ast = parse_ok {|"hello" ? >>> (a ||| b)|} in
  match ast.desc with
  | Ast.Seq ({ desc = Ast.Question (Ast.QString "hello"); _ }, _) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "unexpected AST: %s" (Printer.to_string ast))

let test_parse_question_in_loop () =
  let ast = parse_ok {|loop(generate >>> "all pass"? >>> (exit ||| continue))|} in
  match ast.desc with
  | Ast.Loop { desc = Ast.Seq (_, { desc = Ast.Seq ({ desc = Ast.Question (Ast.QString "all pass"); _ }, { desc = Ast.Group { desc = Ast.Alt _; _ }; _ }); _ }); _ } -> ()
  | _ -> Alcotest.fail (Printf.sprintf "unexpected AST: %s" (Printer.to_string ast))

let test_parse_question_in_group () =
  let ast = parse_ok {|("is valid"?) >>> (accept ||| reject)|} in
  match ast.desc with
  | Ast.Seq ({ desc = Ast.Group { desc = Ast.Question (Ast.QString "is valid"); _ }; _ }, _) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "unexpected AST: %s" (Printer.to_string ast))
```

- [ ] **Step 3: Run parser tests**

```bash
dune exec test/test_compose_dsl.exe -- test Parser
```

Expected: all Parser tests pass.

- [ ] **Step 4: Commit**

```bash
git add test/test_compose_dsl.ml
git commit -m "test(parser): update pattern matches for expr.desc wrapper"
```

---

### Task 9: Update Checker tests and add loc verification

**Files:**
- Modify: `test/test_compose_dsl.ml`

- [ ] **Step 1: Update existing checker test helpers**

The `check_fails` and `check_ok_with_warnings` helpers return `Checker.error list` / `Checker.warning list` which now include `loc`. Existing tests that only check `.message` still work — no change needed for those.

- [ ] **Step 2: Add new loc verification tests**

Add after the existing checker tests:

```ocaml
let test_check_loop_no_eval_loc () =
  let errors = check_fails "loop (a >>> b)" in
  let e = List.hd errors in
  Alcotest.(check int) "error start line" 1 e.loc.start.line;
  Alcotest.(check int) "error start col" 1 e.loc.start.col

let test_check_question_warning_loc () =
  let warnings = check_ok_with_warnings {|"ready"? >>> process >>> done|} in
  let w = List.hd warnings in
  Alcotest.(check int) "warning start line" 1 w.loc.start.line;
  Alcotest.(check int) "warning start col" 1 w.loc.start.col

let test_check_multiline_loc () =
  let errors = check_fails "a >>>\nloop (b >>> c)" in
  let e = List.hd errors in
  (* loop starts on line 2, col 1 *)
  Alcotest.(check int) "error start line" 2 e.loc.start.line;
  Alcotest.(check int) "error start col" 1 e.loc.start.col
```

- [ ] **Step 3: Register new tests in `checker_tests`**

```ocaml
(* Add to checker_tests list: *)
  ; "loop no eval loc", `Quick, test_check_loop_no_eval_loc
  ; "question warning loc", `Quick, test_check_question_warning_loc
  ; "multiline error loc", `Quick, test_check_multiline_loc
```

- [ ] **Step 4: Run all tests**

```bash
dune test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add test/test_compose_dsl.ml
git commit -m "test(checker): add loc verification tests for diagnostics"
```

---

### Task 10: Add Parser expr loc span tests

**Files:**
- Modify: `test/test_compose_dsl.ml`

- [ ] **Step 1: Add parser loc span tests**

These verify that parser-produced `expr.loc` spans are correct:

```ocaml
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
```

- [ ] **Step 2: Register in `parser_tests`**

```ocaml
(* Add to parser_tests list: *)
  ; "node loc span", `Quick, test_parse_node_loc
  ; "seq loc span", `Quick, test_parse_seq_loc
  ; "group loc span", `Quick, test_parse_group_loc
  ; "loop loc span", `Quick, test_parse_loop_loc
  ; "multiline loc span", `Quick, test_parse_multiline_loc
  ; "question loc span", `Quick, test_parse_question_loc
  ; "node with args loc span", `Quick, test_parse_node_with_args_loc
  ; "unicode node loc span", `Quick, test_parse_unicode_node_loc
```

- [ ] **Step 3: Run parser tests**

```bash
dune exec test/test_compose_dsl.exe -- test Parser
```

Expected: all Parser tests pass.

- [ ] **Step 4: Commit**

```bash
git add test/test_compose_dsl.ml
git commit -m "test(parser): add expr loc span tests"
```

---

### Task 11: Add Lexer loc span tests

**Files:**
- Modify: `test/test_compose_dsl.ml`

- [ ] **Step 1: Add lexer loc span tests**

These verify the half-open interval semantics:

```ocaml
let test_lex_ident_loc_span () =
  let tokens = Lexer.tokenize "abc" in
  let t = List.hd tokens in
  Alcotest.(check int) "start col" 1 t.loc.start.col;
  Alcotest.(check int) "end col" 4 t.loc.end_.col

let test_lex_operator_loc_span () =
  let tokens = Lexer.tokenize "a >>> b" in
  let seq_tok = List.nth tokens 1 in
  Alcotest.(check int) ">>> start col" 3 seq_tok.loc.start.col;
  Alcotest.(check int) ">>> end col" 6 seq_tok.loc.end_.col

let test_lex_string_loc_span () =
  let tokens = Lexer.tokenize {|"hello"|} in
  let t = List.hd tokens in
  Alcotest.(check int) "start col" 1 t.loc.start.col;
  Alcotest.(check int) "end col" 8 t.loc.end_.col

let test_lex_question_loc_span () =
  let tokens = Lexer.tokenize "a?" in
  let q_tok = List.nth tokens 1 in
  Alcotest.(check int) "? start col" 2 q_tok.loc.start.col;
  Alcotest.(check int) "? end col" 3 q_tok.loc.end_.col

let test_lex_eof_loc_span () =
  let tokens = Lexer.tokenize "a" in
  let eof_tok = List.nth tokens 1 in
  (match eof_tok.token with
   | Lexer.EOF ->
     Alcotest.(check int) "eof start = end" eof_tok.loc.start.col eof_tok.loc.end_.col
   | _ -> Alcotest.fail "expected EOF")

let test_lex_unicode_ident_loc_span () =
  let tokens = Lexer.tokenize "翻譯" in
  let t = List.hd tokens in
  Alcotest.(check int) "start col" 1 t.loc.start.col;
  Alcotest.(check int) "end col (codepoints)" 3 t.loc.end_.col
```

- [ ] **Step 2: Register in `lexer_tests`**

```ocaml
(* Add to lexer_tests list: *)
  ; "ident loc span", `Quick, test_lex_ident_loc_span
  ; "operator loc span", `Quick, test_lex_operator_loc_span
  ; "string loc span", `Quick, test_lex_string_loc_span
  ; "question loc span", `Quick, test_lex_question_loc_span
  ; "eof loc span", `Quick, test_lex_eof_loc_span
  ; "unicode ident loc span", `Quick, test_lex_unicode_ident_loc_span
```

- [ ] **Step 3: Run all tests**

```bash
dune test
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add test/test_compose_dsl.ml
git commit -m "test(lexer): add loc span tests for half-open interval semantics"
```

---

### Task 12: Final verification and cleanup

- [ ] **Step 1: Run full test suite**

```bash
dune test
```

Expected: all tests pass.

- [ ] **Step 2: Manual smoke test**

```bash
echo 'a >>> b' | dune exec ocaml-compose-dsl
echo 'loop (a >>> b)' | dune exec ocaml-compose-dsl 2>&1
echo '"ready"? >>> process' | dune exec ocaml-compose-dsl 2>&1
```

Expected:
- First: prints AST, exit 0
- Second: `check error at 1:1: loop has no evaluation...`, exit 1
- Third: `warning at 1:1: '?' without matching '|||'...` + AST, exit 0

- [ ] **Step 3: Verify README EBNF still matches**

The EBNF in `README.md` describes the grammar, not AST types. Since we changed no grammar, only internal representation, the EBNF should still be accurate. Quick visual check is sufficient.

- [ ] **Step 4: Commit any fixups if needed**

```bash
dune test && echo "All good"
```
