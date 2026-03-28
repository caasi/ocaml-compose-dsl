# Unit Value (`()`) Design

**Date:** 2026-03-28
**Status:** Draft
**Issue:** #28

## Problem

There is no way to express "no input" or "no output" in this DSL. Triggers (no input) and sinks (no output) lack a natural representation in type annotations:

```
start_server :: ??? -> Server
log(msg: "done") :: Status -> ???
```

Additionally, `noop()` currently parses as `App(Var "noop", [])` — zero-arg application — which is a conceptually distinct form from applying a unit value. In ML tradition, all functions take at least one argument; "no-arg" functions take unit.

## Goal

Add `()` as a unit value/type, following ML convention:

- As an expression: `()` is a standalone value (leaf node in AST)
- In type annotations: `:: () -> Server`, `:: Status -> ()`
- Semantic shift: `noop()` becomes `App(Var "noop", [Positional Unit])` — zero-arg application is eliminated

## Constraints

- Minimal AST change (one new variant)
- All downstream modules (reducer, checker, printer) must handle `Unit` as a leaf node
- `type_ann` remains `{ input : string; output : string }` — `()` is represented as the string `"()"` in type annotations (no sum type change needed, since type annotations are documentation-only in this DSL)
- `()` follows the same `?` rules as other expressions — not blocked at parser level, checker warns if unmatched

## Design

### AST

Add `Unit` variant to `expr_desc` in `ast.ml`:

```ocaml
and expr_desc =
  | Unit                             (** () — unit value *)
  | Var of string
  | StringLit of string
  (* ... rest unchanged ... *)
```

`Unit` is a leaf node with no sub-expressions, same category as `Var` and `StringLit`.

### Parser

Three changes in `parser.ml`:

**1. `parse_term` — `LPAREN` branch adds lookahead:**

When the parser sees `LPAREN`, peek at the next token. If `RPAREN`, produce `Unit`. Otherwise, parse as `Group(program_inner)` as before.

```
LPAREN:
  peek next token
  if RPAREN → advance both, return Unit
  else → parse_program_inner, expect RPAREN, return Group(inner)
```

**2. `parse_call_args` — empty args become `[Positional Unit]`:**

Currently, when `parse_call_args` encounters `RPAREN` immediately, it returns `[]`. After this change, it returns `[Positional (mk_expr loc Unit)]`.

This means:
- `noop()` → `App(Var "noop", [Positional Unit])`
- `f(a, b)` → `App(Var "f", [Positional a, Positional b])` (unchanged)
- `f(a)` → `App(Var "f", [Positional a])` (unchanged)

**3. `parse_type_ann` — accept `()` as type name:**

Both input and output positions in type annotations accept `LPAREN RPAREN` as an alternative to `IDENT`, producing the string `"()"`:

```
:: () -> Server  → { input = "()"; output = "Server" }
:: Status -> ()  → { input = "Status"; output = "()" }
:: () -> ()      → { input = "()"; output = "()" }
```

### Downstream Modules

All downstream modules treat `Unit` as a leaf node. Changes are mechanical — add `Unit` to every `match e.desc with` alongside existing leaf cases:

| Module | Function | `Unit` handling |
|--------|----------|-----------------|
| `reducer.ml` | `free_vars` | `StringSet.empty` |
| `reducer.ml` | `desugar` | `e` (passthrough) |
| `reducer.ml` | `substitute` | `e` (no vars) |
| `reducer.ml` | `beta_reduce` | `e` (already a value) |
| `reducer.ml` | `verify` | `()` (valid terminal) |
| `checker.ml` | `normalize` | `e` |
| `checker.ml` | `scan_questions` | `counter` |
| `checker.ml` | `go` | `()` |
| `printer.ml` | `to_string` | `"Unit"` |

### EBNF

Updated grammar in `README.md`:

```ebnf
term = ident , [ "(" , [ call_args ] , ")" ] , [ "?" ]
     | string , [ "?" ]
     | "()"                                    (* unit value *)
     | "loop" , "(" , seq_expr , ")"
     | "(" , program , ")"
     | lambda
     ;

type_expr   = type_name , "->" , type_name ;
type_name   = ident | "()" ;
```

Note: `"()"` in `term` must be matched before `"(" , program , ")"` — the parser achieves this via lookahead (peek after `LPAREN`; if `RPAREN`, it's unit).

### Lexer

No lexer changes. `()` is tokenized as `LPAREN RPAREN` — the parser disambiguates.

## Semantic Shift

`noop()` changes from `App(Var "noop", [])` to `App(Var "noop", [Positional Unit])`. Zero-arg application no longer exists in the AST.

Consequence: `let f = \x -> x in f()` becomes valid — `f` receives `Unit` and returns `Unit`. Previously this was an arity error (expected 1 arg, got 0).

## Test Impact

**Modified tests:**
- `test_parse_node_empty_parens` — assert `App(_, [Positional {desc = Unit; _}])` instead of `App(_, [])`
- `test_parse_empty_parens_app` (integration) — same change
- `test_reduce_empty_application_arity` — expect success (returns `Unit`) instead of arity error

**New tests:**
- `test_parse_unit_standalone` — `()` → `Unit`
- `test_parse_unit_in_seq` — `() >>> a` → `Seq(Unit, Var "a")`
- `test_parse_unit_type_ann_input` — `node :: () -> Output` → `type_ann = { input = "()"; output = "Output" }`
- `test_parse_unit_type_ann_output` — `node :: Input -> ()` → `type_ann = { input = "Input"; output = "()" }`
- `test_parse_unit_type_ann_both` — `node :: () -> ()` → `type_ann = { input = "()"; output = "()" }`
- `test_print_unit` — `()` → printer outputs `"Unit"`
- `test_reduce_unit_passthrough` — `()` survives reduction unchanged
- `test_check_unit_no_warnings` — `()` produces no checker warnings

## Files Changed

| File | Action |
|------|--------|
| `lib/ast.ml` | Add `Unit` to `expr_desc` |
| `lib/parser.ml` | Modify `parse_term`, `parse_call_args`, `parse_type_ann` |
| `lib/reducer.ml` | Add `Unit` arms to 5 functions |
| `lib/checker.ml` | Add `Unit` arms to 3 functions |
| `lib/printer.ml` | Add `Unit` arm to `to_string` |
| `README.md` | Update EBNF grammar |
| `test/test_parser.ml` | Modify 1 test, add 5 new tests |
| `test/test_integration.ml` | Modify 1 test |
| `test/test_reducer.ml` | Modify 1 test, add 1 new test |
| `test/test_checker.ml` | Add 1 new test |
| `test/test_printer.ml` | Add 1 new test |
