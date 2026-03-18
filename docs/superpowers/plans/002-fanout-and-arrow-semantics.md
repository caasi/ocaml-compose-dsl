# Fanout Operator & Arrow Semantics Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `&&&` (fanout) operator, implement operator precedence with right-associativity, and document Arrow semantics.

**Architecture:** Extend the existing Lexer → Parser → Checker pipeline. Lexer gets one new token (`FANOUT`). Parser is restructured from a single-level `parse_expr`/`parse_binop` into three precedence levels with right-associative recursion. AST gets one new variant (`Fanout`). Checker adds `Fanout` to pattern matches. README gets updated EBNF and a new Arrow Semantics section.

**Tech Stack:** OCaml 5.1, Dune 3.0, Alcotest

**Spec:** `docs/superpowers/specs/2026-03-19-fanout-and-arrow-semantics-design.md`

---

## Chunk 1: Lexer + AST changes

### Task 1: Add `Fanout` to AST

**Files:**
- Modify: `lib/ast.ml:10-16`

- [ ] **Step 1: Add `Fanout` variant to `expr` type**

```ocaml
type expr =
  | Node of node
  | Seq of expr * expr (** [>>>] *)
  | Par of expr * expr (** [***] *)
  | Fanout of expr * expr (** [&&&] *)
  | Alt of expr * expr (** [|||] *)
  | Loop of expr
  | Group of expr
```

- [ ] **Step 2: Verify it compiles**

Run: `dune build`
Expected: Warnings about non-exhaustive pattern matches in `parser.ml` and `checker.ml` (expected — we haven't updated them yet). No errors.

- [ ] **Step 3: Commit**

```bash
git add lib/ast.ml
git commit -m "feat(ast): add Fanout variant for &&& operator"
```

### Task 2: Add `FANOUT` token to Lexer

**Files:**
- Modify: `lib/lexer.ml:1-15` (token type)
- Modify: `lib/lexer.ml:81-119` (tokenize match)
- Test: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write failing tests for `&&&` lexing**

Add to `test/test_compose_dsl.ml` after `test_lex_unexpected_char`:

```ocaml
let test_lex_fanout_operator () =
  let tokens = Lexer.tokenize "a &&& b" in
  let toks = List.map (fun (t : Lexer.located) -> t.token) tokens in
  Alcotest.(check int) "token count" 4 (List.length toks);
  Alcotest.(check bool) "has FANOUT" true (List.nth toks 1 = Lexer.FANOUT)

let test_lex_partial_ampersand () =
  match Lexer.tokenize "a & b" with
  | _ -> Alcotest.fail "expected lex error"
  | exception Lexer.Lex_error (_, msg) ->
    Alcotest.(check string) "error msg" "unexpected character '&'" msg

let test_lex_double_ampersand () =
  match Lexer.tokenize "a && b" with
  | _ -> Alcotest.fail "expected lex error"
  | exception Lexer.Lex_error (_, msg) ->
    Alcotest.(check string) "error msg" "unexpected character '&'" msg
```

Add these to `lexer_tests` list:

```ocaml
  ; "fanout operator", `Quick, test_lex_fanout_operator
  ; "partial ampersand", `Quick, test_lex_partial_ampersand
  ; "double ampersand", `Quick, test_lex_double_ampersand
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dune test`
Expected: Compilation error — `Lexer.FANOUT` does not exist yet.

- [ ] **Step 3: Add `FANOUT` token type**

In `lib/lexer.ml`, add `FANOUT` after `ALT` in the token type:

```ocaml
type token =
  | IDENT of string
  | STRING of string
  | LPAREN
  | RPAREN
  | LBRACKET
  | RBRACKET
  | COLON
  | COMMA
  | SEQ (** [>>>] *)
  | PAR (** [***] *)
  | ALT (** [|||] *)
  | FANOUT (** [&&&] *)
  | LOOP
  | COMMENT of string
  | EOF
```

- [ ] **Step 4: Add `&&&` tokenization logic**

In `lib/lexer.ml`, add a new match arm after the `'|'` case (before the `'-'` case):

```ocaml
      | '&' ->
        if peek2 () = Some '&' && !i + 2 < len && input.[!i + 2] = '&' then begin
          tokens := { token = FANOUT; pos = p } :: !tokens;
          advance (); advance (); advance ()
        end else
          raise (Lex_error (p, Printf.sprintf "unexpected character '%c'" c))
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `dune test`
Expected: New lexer tests pass. Parser/checker tests still pass (FANOUT token unused by parser yet).

- [ ] **Step 6: Commit**

```bash
git add lib/lexer.ml test/test_compose_dsl.ml
git commit -m "feat(lexer): add FANOUT token for &&& operator"
```

## Chunk 2: Parser restructure (precedence + right-associativity)

### Task 3: Write failing parser tests for new behavior

**Files:**
- Test: `test/test_compose_dsl.ml`

- [ ] **Step 1: Add new parser tests**

Add after `test_parse_mixed_operators`:

```ocaml
let test_parse_fanout () =
  let ast = parse_ok "a &&& b" in
  match ast with
  | Ast.Fanout (Ast.Node _, Ast.Node _) -> ()
  | _ -> Alcotest.fail "expected Fanout"

let test_parse_precedence_seq_fanout () =
  (* a >>> b &&& c >>> d  =  a >>> ((b &&& c) >>> d)  right-assoc *)
  let ast = parse_ok "a >>> b &&& c >>> d" in
  match ast with
  | Ast.Seq (Ast.Node _, Ast.Seq (Ast.Fanout (Ast.Node _, Ast.Node _), Ast.Node _)) -> ()
  | _ -> Alcotest.fail "expected Seq(a, Seq(Fanout(b,c), d))"

let test_parse_precedence_alt_par () =
  (* a ||| b *** c  =  a ||| (b *** c)  precedence *)
  let ast = parse_ok "a ||| b *** c" in
  match ast with
  | Ast.Alt (Ast.Node _, Ast.Par (Ast.Node _, Ast.Node _)) -> ()
  | _ -> Alcotest.fail "expected Alt(a, Par(b,c))"

let test_parse_par_fanout_same_prec () =
  (* a *** b &&& c  =  a *** (b &&& c)  right-assoc, same precedence *)
  let ast = parse_ok "a *** b &&& c" in
  match ast with
  | Ast.Par (Ast.Node _, Ast.Fanout (Ast.Node _, Ast.Node _)) -> ()
  | _ -> Alcotest.fail "expected Par(a, Fanout(b,c))"

let test_parse_mixed_all_precedence () =
  (* a >>> b ||| c &&& d *** e
     = a >>> (b ||| ((c &&& d) *** e))    precedence + right-assoc
     but &&& and *** are same level, right-assoc:
       c &&& d *** e = c &&& (d *** e) = Fanout(c, Par(d, e))
     wait — *** and &&& same precedence, right-assoc:
       c &&& d *** e — first see c, then &&&, then recursively parse d *** e
       d *** e = Par(d, e)
       so: Fanout(c, Par(d, e))
     then: b ||| Fanout(c, Par(d, e)) = Alt(b, Fanout(c, Par(d, e)))
     then: a >>> Alt(...) = Seq(a, Alt(b, Fanout(c, Par(d, e))))
  *)
  let ast = parse_ok "a >>> b ||| c &&& d *** e" in
  match ast with
  | Ast.Seq (Ast.Node _,
      Ast.Alt (Ast.Node _,
        Ast.Fanout (Ast.Node _,
          Ast.Par (Ast.Node _, Ast.Node _)))) -> ()
  | _ -> Alcotest.fail "expected Seq(a, Alt(b, Fanout(c, Par(d, e))))"

let test_parse_group_overrides_precedence () =
  let ast = parse_ok "(a >>> b) &&& c" in
  match ast with
  | Ast.Fanout (Ast.Group (Ast.Seq (Ast.Node _, Ast.Node _)), Ast.Node _) -> ()
  | _ -> Alcotest.fail "expected Fanout(Group(Seq(a,b)), c)"

let test_parse_right_assoc_seq () =
  (* a >>> b >>> c  =  a >>> (b >>> c)  right-assoc *)
  let ast = parse_ok "a >>> b >>> c" in
  match ast with
  | Ast.Seq (Ast.Node _, Ast.Seq (Ast.Node _, Ast.Node _)) -> ()
  | _ -> Alcotest.fail "expected right-associative Seq"
```

Add these to `parser_tests` list (after `"mixed operators"` entry):

```ocaml
  ; "fanout", `Quick, test_parse_fanout
  ; "precedence: seq vs fanout", `Quick, test_parse_precedence_seq_fanout
  ; "precedence: alt vs par", `Quick, test_parse_precedence_alt_par
  ; "par and fanout same prec", `Quick, test_parse_par_fanout_same_prec
  ; "mixed all precedence", `Quick, test_parse_mixed_all_precedence
  ; "group overrides precedence", `Quick, test_parse_group_overrides_precedence
  ; "right-assoc seq", `Quick, test_parse_right_assoc_seq
```

- [ ] **Step 2: Run tests to verify new tests fail**

Run: `dune test`
Expected: `test_parse_fanout` fails (Fanout not parsed). Several precedence tests fail (wrong grouping).

- [ ] **Step 3: Commit failing tests**

```bash
git add test/test_compose_dsl.ml
git commit -m "test(parser): add failing tests for fanout, precedence, right-assoc"
```

### Task 4: Restructure parser for precedence and right-associativity

**Files:**
- Modify: `lib/parser.ml:86-102`

- [ ] **Step 1: Replace `parse_expr` and `parse_binop` with three precedence levels**

Replace lines 86–102 of `lib/parser.ml` (the `parse_expr` and `parse_binop` functions) with:

```ocaml
let rec parse_seq_expr st =
  let lhs = parse_alt_expr st in
  let comments = eat_comments st in
  let lhs =
    match lhs with
    | Node n -> Node { n with comments = n.comments @ comments }
    | _ -> lhs
  in
  let t = current st in
  match t.token with
  | Lexer.SEQ -> advance st; Seq (lhs, parse_seq_expr st)
  | _ -> lhs

and parse_alt_expr st =
  let lhs = parse_par_expr st in
  let comments = eat_comments st in
  let lhs =
    match lhs with
    | Node n -> Node { n with comments = n.comments @ comments }
    | _ -> lhs
  in
  let t = current st in
  match t.token with
  | Lexer.ALT -> advance st; Alt (lhs, parse_alt_expr st)
  | _ -> lhs

and parse_par_expr st =
  let lhs = parse_term st in
  let comments = eat_comments st in
  let lhs =
    match lhs with
    | Node n -> Node { n with comments = n.comments @ comments }
    | _ -> lhs
  in
  let t = current st in
  match t.token with
  | Lexer.PAR -> advance st; Par (lhs, parse_par_expr st)
  | Lexer.FANOUT -> advance st; Fanout (lhs, parse_par_expr st)
  | _ -> lhs
```

Right-associativity is achieved by recursing into the same function for the RHS (e.g., `parse_seq_expr` calls `parse_seq_expr` for RHS), instead of the old while-loop pattern.

- [ ] **Step 2: Update `parse_term` to call `parse_seq_expr` for group/loop bodies**

In `parse_term`, the recursive calls to `parse_expr` must become `parse_seq_expr`:

Replace line 124 (`let body = parse_expr st in`) with:
```ocaml
    let body = parse_seq_expr st in
```

Replace line 129 (`let inner = parse_expr st in`) with:
```ocaml
    let inner = parse_seq_expr st in
```

- [ ] **Step 3: Update `parse` entry point**

Replace line 136 (`let expr = parse_expr st in`) with:
```ocaml
  let expr = parse_seq_expr st in
```

- [ ] **Step 4: Remove old `parse_expr` and `parse_binop`**

Delete the old `parse_expr` and `parse_binop` functions (they are now replaced by the three `parse_*_expr` functions). The `and` chain should be: `parse_seq_expr` — `parse_alt_expr` — `parse_par_expr` — `parse_term`.

- [ ] **Step 5: Run tests**

Run: `dune test`
Expected: New precedence/fanout tests pass. Some OLD tests will fail — that's expected, handled in Task 5.

### Task 5: Update existing tests for new associativity and precedence

**Files:**
- Modify: `test/test_compose_dsl.ml`

- [ ] **Step 1: Update `test_parse_seq` for right-associativity**

Change:
```ocaml
let test_parse_seq () =
  let ast = parse_ok "a >>> b >>> c" in
  match ast with
  | Ast.Seq (Ast.Seq (Ast.Node _, Ast.Node _), Ast.Node _) -> ()
  | _ -> Alcotest.fail "expected left-associative Seq"
```

To:
```ocaml
let test_parse_seq () =
  let ast = parse_ok "a >>> b >>> c" in
  match ast with
  | Ast.Seq (Ast.Node _, Ast.Seq (Ast.Node _, Ast.Node _)) -> ()
  | _ -> Alcotest.fail "expected right-associative Seq"
```

- [ ] **Step 2: Update `test_parse_mixed_operators` for new precedence**

Change:
```ocaml
let test_parse_mixed_operators () =
  let ast = parse_ok "a >>> b *** c ||| d" in
  match ast with
  | Ast.Alt (Ast.Par (Ast.Seq (Ast.Node _, Ast.Node _), Ast.Node _), Ast.Node _) -> ()
  | _ -> Alcotest.fail "expected left-associative mixed ops"
```

To:
```ocaml
let test_parse_mixed_operators () =
  (* a >>> b *** c ||| d = a >>> ((b *** c) ||| d) *)
  let ast = parse_ok "a >>> b *** c ||| d" in
  match ast with
  | Ast.Seq (Ast.Node _, Ast.Alt (Ast.Par (Ast.Node _, Ast.Node _), Ast.Node _)) -> ()
  | _ -> Alcotest.fail "expected precedence: >>> < ||| < ***"
```

- [ ] **Step 3: Update `test_parse_nested_loop` for right-associativity**

Change:
```ocaml
let test_parse_nested_loop () =
  let ast = parse_ok "loop (a >>> loop (b >>> check(x: y)) >>> evaluate(r: done))" in
  match ast with
  | Ast.Loop (Ast.Seq (Ast.Seq (Ast.Node _, Ast.Loop _), Ast.Node _)) -> ()
  | _ -> Alcotest.fail "expected nested Loop"
```

To:
```ocaml
let test_parse_nested_loop () =
  let ast = parse_ok "loop (a >>> loop (b >>> check(x: y)) >>> evaluate(r: done))" in
  match ast with
  | Ast.Loop (Ast.Seq (Ast.Node _, Ast.Seq (Ast.Loop _, Ast.Node _))) -> ()
  | _ -> Alcotest.fail "expected nested Loop"
```

- [ ] **Step 4: Run all tests**

Run: `dune test`
Expected: ALL tests pass (40 existing + 3 lexer + 7 parser = 50 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/parser.ml test/test_compose_dsl.ml
git commit -m "feat(parser): implement precedence levels and right-associativity

Operators now follow Haskell Arrow fixity:
  infixr 1 >>>
  infixr 2 |||
  infixr 3 ***, &&&

BREAKING: associativity changed from left to right.
a >>> b >>> c now parses as a >>> (b >>> c)."
```

## Chunk 3: Checker + README + examples

### Task 6: Add `Fanout` to checker pattern matches

**Files:**
- Modify: `lib/checker.ml:12-13,25`

- [ ] **Step 1: Write failing test for fanout inside loop**

Add to `test/test_compose_dsl.ml` after `test_check_nested_loop_both_need_eval`:

```ocaml
let test_check_loop_with_fanout_and_eval () =
  let _ = check_ok "loop (a &&& evaluate(criteria: done))" in
  ()
```

Add to `checker_tests`:

```ocaml
  ; "loop with fanout and eval", `Quick, test_check_loop_with_fanout_and_eval
```

- [ ] **Step 2: Run tests to verify it fails**

Run: `dune test`
Expected: Compiler warning about non-exhaustive match in `checker.ml`, or runtime match failure.

- [ ] **Step 3: Add `Fanout` to both pattern matches in checker**

In `lib/checker.ml`, line 13, change:

```ocaml
    | Seq (a, b) -> go a; go b
    | Par (a, b) -> go a; go b
    | Alt (a, b) -> go a; go b
```

To:

```ocaml
    | Seq (a, b) -> go a; go b
    | Par (a, b) -> go a; go b
    | Fanout (a, b) -> go a; go b
    | Alt (a, b) -> go a; go b
```

In `lib/checker.ml`, line 25, change:

```ocaml
        | Seq (a, b) | Par (a, b) | Alt (a, b) -> scan a; scan b
```

To:

```ocaml
        | Seq (a, b) | Par (a, b) | Fanout (a, b) | Alt (a, b) -> scan a; scan b
```

- [ ] **Step 4: Run all tests**

Run: `dune test`
Expected: All 44 tests pass. No compiler warnings.

- [ ] **Step 5: Commit**

```bash
git add lib/checker.ml test/test_compose_dsl.ml
git commit -m "feat(checker): add Fanout to pattern matches"
```

### Task 7: Update README with new EBNF and Arrow Semantics

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace EBNF section**

Replace the Grammar (EBNF) content in `README.md` (lines 15–46) with:

````markdown
```ebnf
pipeline = seq_expr ;

seq_expr = alt_expr , { ">>>" , alt_expr } ;       (* sequential — infixr 1 *)
alt_expr = par_expr , { "|||" , par_expr } ;       (* branch — infixr 2 *)
par_expr = term , { ( "***" | "&&&" ) , term } ;   (* parallel / fanout — infixr 3 *)

term     = node
         | "loop" , "(" , seq_expr , ")"            (* feedback loop *)
         | "(" , seq_expr , ")"                    (* grouping *)
         ;

node     = ident , [ "(" , [ args ] , ")" ] ;

args     = arg , { "," , arg } ;

arg      = ident , ":" , value ;

value    = string
         | ident
         | "[" , [ value , { "," , value } ] , "]"
         ;

ident    = ( letter | "_" ) , { letter | digit | "-" | "_" } ;

string   = '"' , { any char - '"' } , '"' ;

comment  = "--" , { any char - newline } ;
```

All operators are right-associative (matching Haskell Arrow fixity). Comments can appear after any term and are attached to the preceding node as purpose descriptions or reference tool annotations.
````

- [ ] **Step 2: Add Arrow Semantics section after Grammar, before Example**

Insert:

```markdown
## Arrow Semantics

The operators follow Arrow combinator semantics. The DSL has no type checker —
these types describe the data flow for the agent (and human) reading the pipeline.

| Operator | Name           | Type                                          |
|----------|----------------|-----------------------------------------------|
| `>>>`    | compose        | `Arrow a b → Arrow b c → Arrow a c`           |
| `***`    | product        | `Arrow a b → Arrow c d → Arrow (a,c) (b,d)`   |
| `&&&`    | fanout         | `Arrow a b → Arrow a c → Arrow a (b,c)`       |
| `\|\|\|` | fanin / branch | `Arrow a c → Arrow b c → Arrow (Either a b) c` |
| `loop`   | feedback       | `Arrow (a,s) (b,s) → Arrow a b`               |

`***` is right-associative: `a *** b *** c` types as `(A, (B, C))`.
Comments can annotate the concrete types when the structure isn't obvious from node names.
```

- [ ] **Step 3: Add a `&&&` example to the Example section**

Add after the existing examples:

```markdown
```
(lint &&& test)
  >>> gate(require: [pass, pass])
  >>> (build_linux(profile: static) *** build_macos(profile: release))
  >>> upload(tag: "v0.1.0")
```
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: update EBNF, add Arrow semantics and fanout example"
```

### Task 8: Add example `.arr` files

**Files:**
- Create: `examples/brainstorming.arr`
- Create: `examples/tdd-loop.arr`
- Create: `examples/release.arr`

- [ ] **Step 1: Create `examples/brainstorming.arr`**

```
-- explore_context : () → (SourceCode, (History, Docs))
-- summarize       : (SourceCode, (History, Docs)) → Context
-- ask_questions   : Context → Requirements
-- propose         : Requirements → Design

(read_files(glob: "lib/**/*.ml") *** git_log(n: "20") *** read_docs(path: "CLAUDE.md"))
  >>> summarize
  >>> ask_questions(style: one_at_a_time)
  >>> propose(count: "3")
  >>> present_design
  >>> write_spec
```

- [ ] **Step 2: Create `examples/tdd-loop.arr`**

```
-- write_test : Feature → (Code, TestSuite)
-- implement  : (Code, ErrorContext) → (Code, ErrorContext)
-- run_tests  : Code → Either PassResult FailResult
-- evaluate   : Either PassResult FailResult → (Result, ErrorContext)

write_test(for: feature)
  >>> loop(
    implement
      >>> run_tests
      >>> evaluate(criteria: all_pass)
  )
  >>> commit
```

- [ ] **Step 3: Create `examples/release.arr`**

```
-- lint      : Code → LintReport
-- test      : Code → TestReport
-- gate      : (LintReport, TestReport) → (Code, Code)
-- build_*   : Code → Binary
-- upload    : (Binary, Binary) → Release

(lint &&& test)
  >>> gate(require: [pass, pass])
  >>> (build_linux(profile: static) *** build_macos(profile: release))
  >>> upload_release(tag: "v0.1.0")
```

- [ ] **Step 4: Validate all examples parse and check OK**

Run:
```bash
dune exec ocaml-compose-dsl -- examples/brainstorming.arr
dune exec ocaml-compose-dsl -- examples/tdd-loop.arr
dune exec ocaml-compose-dsl -- examples/release.arr
```
Expected: All three print `OK` and exit 0.

- [ ] **Step 5: Commit**

```bash
git add examples/
git commit -m "docs: add example .arr files for subagent workflows"
```

### Task 9: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update AST module description**

Change the `Ast` line from:
```
- `Ast` — ADT for DSL expressions: Node, Seq (`>>>`), Par (`***`), Alt (`|||`), Loop, Group
```
To:
```
- `Ast` — ADT for DSL expressions: Node, Seq (`>>>`), Par (`***`), Fanout (`&&&`), Alt (`|||`), Loop, Group
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for fanout operator"
```
