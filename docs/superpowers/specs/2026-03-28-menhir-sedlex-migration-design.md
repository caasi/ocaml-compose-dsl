# Menhir + Sedlex Migration Design

**Date:** 2026-03-28
**Status:** Draft

## Problem

Hand-written recursive descent parser (298 lines) and lexer (213 lines) frequently diverge from the EBNF grammar defined in README.md. This divergence is caught during code review, leading to multiple rounds of fixes per change. The development feedback loop for grammar changes is too slow.

## Goal

Replace hand-written lexer and parser with declarative equivalents (sedlex + Menhir) so that the grammar definition IS the implementation, eliminating EBNF-implementation divergence as a class of bugs.

## Constraints

- Error message quality must not regress from current hand-written parser
- AST (`lib/ast.ml`) and all downstream modules (reducer, checker, printer, markdown) remain unchanged
- Existing test suite (1293 lines across parser + lexer tests) serves as regression tests
- One or two well-maintained dependencies acceptable; gratuitous deps are not

## Design

### Architecture

Pipeline shape is preserved:

```
String → Sedlex lexer → Token stream → Menhir parser → Ast → Reducer → Checker
```

Lexer and parser go from hand-written OCaml logic to declarative specs with generated code.

### File Structure Changes

| Before | After | Notes |
|--------|-------|-------|
| `lib/lexer.ml` (hand-written, 213 lines) | `lib/lexer.ml` (sedlex PPX) | Declarative rules via `[%sedlex buf]` |
| `lib/parser.ml` (hand-written, 298 lines) | `lib/parser.mly` (Menhir grammar) | Grammar file ≈ EBNF; Menhir generates `parser.ml` |
| `lib/ast.ml` | `lib/ast.ml` (unchanged) | — |
| `lib/compose_dsl.ml` | `lib/compose_dsl.ml` (minor) | Adapt parser invocation to Menhir API |
| `bin/main.ml` | `bin/main.ml` (minor) | Adapt error handling exception types |
| `lib/dune` | `lib/dune` | Add menhir/sedlex deps, `(menhir ...)` stanza |
| `dune-project` | `dune-project` | Add `(using menhir 2.1)` |

Token type is defined by Menhir's `%token` declarations in the `.mly` file. The sedlex lexer imports them via `open Parser`.

### Sedlex Lexer Design

The sedlex lexer replaces `lib/lexer.ml` as a PPX-annotated `.ml` file:

```ocaml
let rec token buf =
  match%sedlex buf with
  | ">>>"         -> SEQ
  | "***"         -> PAR
  | "&&&"         -> FANOUT
  | "|||"         -> ALT
  | "let"         -> LET
  | "loop"        -> LOOP
  | "in"          -> IN
  | "->"          -> ARROW
  | "::"          -> DOUBLE_COLON
  | '"', Star (Compl '"'), '"' -> STRING (lexeme_string buf)
  | ident_start, Star ident_char -> IDENT (lexeme_string buf)
  | "--", Star (Compl '\n')     -> COMMENT (lexeme_string buf)
  | Plus white_space            -> token buf
  | eof                         -> EOF
  | _                           -> raise (Lex_error ...)
```

Key properties:

- **Unicode**: Sedlex operates on Unicode codepoints natively, replacing hand-written `String.get_utf_8_uchar` logic.
- **`->` lookahead**: Sedlex's longest-match semantics with priority ordering naturally resolves the `ident_char` vs `->` ambiguity that the hand-written lexer handles with explicit lookahead.
- **Location tracking**: `Sedlexing.lexeme_start` / `lexeme_end` feed into a thin wrapper producing `Ast.loc` records. Columns must remain codepoint-based (not byte offset).
- **Menhir interface**: A thin adapter function `unit -> token * Lexing.position * Lexing.position` supplies the Menhir incremental API.

### Menhir Parser Grammar

The `.mly` file is a direct 1:1 translation of the README EBNF:

```menhir
%token <string> IDENT STRING NUMBER COMMENT
%token SEQ PAR FANOUT ALT ARROW DOUBLE_COLON
%token LET IN LOOP
%token LPAREN RPAREN LBRACKET RBRACKET
%token COMMA COLON EQUALS BACKSLASH QUESTION
%token EOF

%start <Ast.expr> program

%%

program:
  | LET name=IDENT EQUALS value=seq_expr IN rest=program
    { mk_expr $loc (Let (name, value, rest)) }
  | e=seq_expr EOF
    { e }
;

seq_expr:
  | lhs=alt_expr SEQ rhs=seq_expr   { mk_expr $loc (Seq (lhs, rhs)) }
  | e=alt_expr                       { e }
;

alt_expr:
  | lhs=par_expr ALT rhs=alt_expr   { mk_expr $loc (Alt (lhs, rhs)) }
  | e=par_expr                       { e }
;

par_expr:
  | lhs=typed_term PAR rhs=par_expr     { mk_expr $loc (Par (lhs, rhs)) }
  | lhs=typed_term FANOUT rhs=par_expr  { mk_expr $loc (Fanout (lhs, rhs)) }
  | e=typed_term                         { e }
;

typed_term:
  | e=term DOUBLE_COLON input=IDENT ARROW output=IDENT
    { { e with type_ann = Some { input; output }; loc = $loc } }
  | e=term  { e }
;

term:
  | name=IDENT LPAREN args=call_args RPAREN QUESTION
    { mk_expr $loc (Question (mk_expr $loc (App (mk_expr $loc(name) (Var name), args)))) }
  | name=IDENT LPAREN args=call_args RPAREN
    { mk_expr $loc (App (mk_expr $loc(name) (Var name), args)) }
  | name=IDENT QUESTION
    { mk_expr $loc (Question (mk_expr $loc(name) (Var name))) }
  | name=IDENT
    { mk_expr $loc(name) (Var name) }
  | s=STRING QUESTION
    { mk_expr $loc (Question (mk_expr $loc(s) (StringLit s))) }
  | s=STRING
    { mk_expr $loc(s) (StringLit s) }
  | LOOP LPAREN body=seq_expr RPAREN
    { mk_expr $loc (Loop body) }
  | LPAREN inner=program RPAREN
    { mk_expr $loc (Group inner) }
  | BACKSLASH params=lambda_params ARROW body=seq_expr
    { mk_expr $loc (Lambda (params, body)) }
;

lambda_params:
  | p=IDENT COMMA rest=lambda_params  { p :: rest }
  | p=IDENT                           { [p] }
;

call_args:
  | a=call_arg COMMA rest=call_args  { a :: rest }
  | a=call_arg                       { [a] }
;

call_arg:
  | key=arg_key COLON v=value   { Named { key; value = v } }
  | e=seq_expr                  { Positional e }
;

arg_key:
  | k=IDENT  { k }
  | IN       { "in" }
;

value:
  | s=STRING                                          { String s }
  | n=NUMBER                                          { Number n }
  | i=IDENT                                           { Ident i }
  | LBRACKET vs=separated_list(COMMA, value) RBRACKET { List vs }
;
```

Design points:

- **Right-associativity**: All infix operators use right-recursion (`rhs=seq_expr`), matching the EBNF's `infixr` semantics.
- **`$loc`**: Menhir's built-in location tracking, mapped to `Ast.loc` via a helper.
- **`separated_list`**: Menhir built-in, replaces hand-written loop for value lists.
- **Comments**: Skipped at lexer level (not passed to parser). Comment attachment to AST nodes is a pre-existing known bug and is not addressed in this migration.
- **`call_arg` disambiguation**: LR(1) lookahead resolves named vs positional — seeing `IDENT COLON` shifts to the named path. Must verify no shift/reduce conflict at build time.
- **Error messages**: Custom messages via Menhir's `.messages` mechanism, including the existing `let ... in` migration hint.

### Migration Strategy

Ordered steps, each gated on existing tests passing:

```arrow
let sedlex_lexer = write_sedlex >>> adapt_token_helper >>> run_lexer_tests in
let menhir_parser = write_mly >>> wire_dune >>> run_parser_tests in
let integrate =
  update_compose_dsl >>> update_main >>> run_integration_tests in
let migrate = sedlex_lexer >>> menhir_parser >>> integrate in
```

1. **Sedlex lexer**: Write sedlex lexer, add `tokenize_all` helper for test compat, pass all `test_lexer.ml` tests.
2. **Menhir parser**: Write `.mly`, wire up dune build, pass all `test_parser.ml` tests.
3. **Integration**: Update `compose_dsl.ml` and `main.ml`, pass all integration and remaining tests.

### Test Strategy

- **`test_parser.ml`** (783 lines): Input → AST tests, kept as-is. Only adjust parser invocation if interface changes.
- **`test_lexer.ml`** (510 lines): Input → token list tests. Wrap sedlex in `tokenize_all : string -> token list` helper for backward compat.
- **Error message tests**: Exact-match assertions adapted one by one using Menhir `.messages`.
- **New: EBNF conformance check** (optional): CI script verifying `.mly` production names match README EBNF production names.

### Build System Changes

`dune-project`:
```
(using menhir 2.1)
```

`lib/dune`:
```
(library
 (name compose_dsl)
 (public_name ocaml-compose-dsl-lib)
 (libraries menhirLib sedlex)
 (preprocess (pps sedlex.ppx)))

(menhir
 (modules parser))
```

### Known Risks

1. **`call_arg` LR(1) conflict**: `IDENT` starts both named arg and positional `seq_expr`. LR(1) lookahead to `COLON` should resolve it, but if Menhir reports a conflict, may need grammar refactoring or `%inline`.
2. **Location precision**: Menhir's `$loc` uses `Lexing.position` (byte-based). Sedlex adapter must convert to codepoint-based columns to preserve current behavior.
3. **Static linking (CI)**: Alpine/musl static builds must work with sedlex and menhir runtime. Both are pure OCaml, so this should be fine.
4. **Lambda duplicate parameter check**: Currently done in `parse_lambda` with a `StringSet`. In Menhir this moves to a semantic action or a post-parse validation step (could go in reducer or a new thin validation layer between parser and reducer).

### What Does NOT Change

- `lib/ast.ml` — AST definition
- `lib/reducer.ml` — desugaring and beta reduction
- `lib/checker.ml` — structural validation
- `lib/printer.ml` — AST pretty-printing
- `lib/markdown.ml` — literate mode support
- `test/test_reducer.ml`, `test/test_checker.ml`, `test/test_printer.ml`, `test/test_markdown.ml`, `test/test_integration.ml`
