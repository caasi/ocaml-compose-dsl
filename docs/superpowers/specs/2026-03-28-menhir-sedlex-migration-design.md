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

The current architecture uses a two-phase model: lexer produces a complete `token list`, then parser consumes it. Menhir uses a pull-based model: the parser calls the lexer on demand for the next token. This is an architectural change — the parser drives the lexer rather than receiving a pre-built list. Error recovery behavior may differ (the current parser can inspect remaining tokens freely; Menhir cannot look ahead beyond LR(1)).

### File Structure Changes

| Before | After | Notes |
|--------|-------|-------|
| `lib/lexer.ml` (hand-written, 213 lines) | `lib/lexer.ml` (sedlex PPX) | Declarative rules via `[%sedlex buf]` |
| `lib/parser.ml` (hand-written, 298 lines) | `lib/parser.mly` (Menhir grammar) | Grammar file ≈ EBNF; Menhir generates `parser.ml` |
| `lib/ast.ml` | `lib/ast.ml` (unchanged) | — |
| `lib/compose_dsl.ml` | `lib/compose_dsl.ml` (moderate) | Adapt to Menhir pull-based API; public interface changes |
| `bin/main.ml` | `bin/main.ml` (moderate) | Adapt error handling exception types |
| `lib/dune` | `lib/dune` | Add menhir/sedlex deps, `(menhir ...)` stanza |
| `dune-project` | `dune-project` | Add `(using menhir 2.1)` |

Token type is defined by Menhir's `%token` declarations in the `.mly` file. The sedlex lexer imports them via `open Parser`. This means `Lexer.token` becomes `Parser.token` — all code referencing `Lexer.IDENT`, `Lexer.SEQ`, etc. must be updated (including test files). The lexer module may re-export the token type for convenience.

The current `Lexer.located` type (`{ token: token; loc: loc }`) disappears. The Menhir interface uses `unit -> token * Lexing.position * Lexing.position` instead. A `tokenize_all` helper must bridge this gap for lexer tests (see Test Strategy).

### Sedlex Lexer Design

The sedlex lexer replaces `lib/lexer.ml` as a PPX-annotated `.ml` file. The sketch below shows the key rules; single-character tokens (`(`, `)`, `[`, `]`, `:`, `,`, `=`, `?`, `\`) are elided for brevity:

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
  | '('           -> LPAREN
  | ')'           -> RPAREN
  (* ... other single-char tokens ... *)
  | '"', Star (Compl '"'), '"' -> STRING (lexeme_string buf)
  | Opt '-', Plus digit, Opt ('.', Plus digit), Opt (ident_start, Star ident_char)
                  -> NUMBER (lexeme_string buf)
  | ident_start, Star ident_char -> IDENT (lexeme_string buf)
  | "--", Star (Compl '\n')     -> COMMENT (lexeme_string buf)
  | Plus white_space            -> token buf
  | eof                         -> EOF
  | _                           -> raise (Lex_error ...)
```

Key properties:

- **Unicode**: Sedlex operates on Unicode codepoints natively, replacing hand-written `String.get_utf_8_uchar` logic.
- **`->` lookahead**: Sedlex's longest-match semantics with priority ordering naturally resolves the `ident_char` vs `->` ambiguity that the hand-written lexer handles with explicit lookahead.
- **Negative numbers**: The `Opt '-'` in the NUMBER rule could conflict with `->` (arrow) or `--` (comment). Sedlex's longest-match resolves `->` and `--` because they are longer than a bare `-`. However, `- 3` (space between minus and digit) would NOT be a negative number — this matches the current lexer behavior where `-` must be immediately followed by a digit.
- **Location tracking**: Sedlex provides `Sedlexing.lexeme_start` / `lexeme_end` as codepoint offsets. A thin adapter must convert these to `Ast.loc` records. The adapter maintains a line/column counter (codepoint-based) by scanning for newlines in each lexeme. This is necessary because Menhir internally uses `Lexing.position` (byte-based), but our AST uses codepoint-based columns. The adapter function populates both: `Lexing.position` for Menhir's internal use, and a side-channel `Ast.loc` that semantic actions can reference.
- **Menhir interface**: A thin adapter function `unit -> token * Lexing.position * Lexing.position` supplies the Menhir incremental API.

### Menhir Parser Grammar

The `.mly` file is a direct 1:1 translation of the README EBNF. Key difference from a naive translation: `program` is split into `program` (top-level, consumes EOF) and `program_inner` (reusable in grouped expressions), mirroring the current parser's `parse_program` / `parse_program_inner` separation.

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
  | e=program_inner EOF  { e }
;

program_inner:
  | LET name=IDENT EQUALS value=seq_expr IN rest=program_inner
    { mk_expr $loc (Let (name, value, rest)) }
  | e=seq_expr
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
  | name=IDENT LPAREN args=loption(call_args) RPAREN QUESTION
    { mk_expr $loc (Question (mk_expr $loc (App (mk_expr ($loc(name)) (Var name), args)))) }
  | name=IDENT LPAREN args=loption(call_args) RPAREN
    { mk_expr $loc (App (mk_expr ($loc(name)) (Var name), args)) }
  | name=IDENT QUESTION
    { mk_expr $loc (Question (mk_expr ($loc(name)) (Var name))) }
  | name=IDENT
    { mk_expr ($loc(name)) (Var name) }
  | s=STRING QUESTION
    { mk_expr $loc (Question (mk_expr ($loc(s)) (StringLit s))) }
  | s=STRING
    { mk_expr ($loc(s)) (StringLit s) }
  | LOOP LPAREN body=seq_expr RPAREN
    { mk_expr $loc (Loop body) }
  | LPAREN inner=program_inner RPAREN
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

(* Inlined arg_key to avoid reduce/reduce conflict:
   Without inlining, after seeing IDENT the parser must choose between
   reducing via arg_key (Named path) or via term->Var (Positional path)
   before seeing COLON. Inlining lets Menhir see through to COLON. *)
call_arg:
  | key=IDENT COLON v=value  { Named { key; value = v } }
  | IN COLON v=value         { Named { key = "in"; value = v } }
  | e=seq_expr               { Positional e }
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
- **`program` vs `program_inner`**: `program` consumes EOF and is the entry point. `program_inner` is used inside grouped expressions `(...)` where `)` terminates instead of EOF.
- **`loption(call_args)`**: Handles empty argument lists like `noop()`. `loption` returns `[]` when `call_args` doesn't match.
- **`$loc` and `$loc(x)`**: Menhir's built-in location tracking. `$loc(name)` gives the location of just the `name` binding. Parenthesized as `($loc(name))` in OCaml expressions to avoid parsing ambiguity.
- **`separated_list`**: Menhir built-in, replaces hand-written loop for value lists.
- **Inlined `arg_key`**: The `arg_key` non-terminal is inlined into `call_arg` to avoid a reduce/reduce conflict. After seeing `IDENT`, the parser would otherwise need to choose between reducing it as `arg_key` or as `term -> Var` before seeing `COLON`. Inlining exposes the `COLON` lookahead directly.
- **Comments**: Skipped at lexer level (not passed to parser). This is a **known regression** from the current parser: comment attachment to binary operator nodes (`Seq`, `Par`, `Fanout`, `Alt`, `Group`, `Loop`) via `attach_comments_right` is lost. Comment attachment to `Var`/`App`/`Lambda`/`Let` was already a known bug. The migration accepts full comment loss as the status quo was partial and buggy. If comment preservation becomes important, it should be addressed as a separate feature (see CLAUDE.md Future Ideas).
- **Error messages**: Custom messages via Menhir's `.messages` mechanism (see Error Message Strategy below).

### Error Message Strategy

The current parser has these specific error messages that must be preserved or have acceptable alternatives:

| Current message | Preservation strategy |
|----------------|----------------------|
| `"expected ',' or ')'"` in call args | Menhir `.messages` for the relevant parser state |
| `"unexpected trailing comma in argument list"` | Menhir `.messages` — detect state after COMMA before RPAREN |
| `"expected 'in' after let binding value\nHint: let bindings now require 'in'..."` | Menhir `.messages`. **Known limitation**: the current hint interpolates the binding name (`%s`); Menhir `.messages` cannot reference semantic values, so the hint becomes generic ("let bindings require 'in'") |
| `"'in' is a reserved keyword and cannot be used as an identifier"` | Menhir `.messages` for `IN` in term position |
| `"duplicate parameter '%s' in lambda"` | **Moved to semantic action** in `lambda_params` or to a post-parse validation pass. Menhir semantic actions can accumulate a `StringSet` and raise an error, preserving the exact message |
| `"expected node, string, '(', 'loop', or '\\' (lambda)"` | Menhir `.messages` for term-position errors |
| Lexer: `"unterminated string"`, `"unexpected character"` | Preserved in sedlex lexer directly (raised as `Lex_error`) |

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

- **`test_parser.ml`** (783 lines): Input → AST tests preserved. Parser invocation changes from `Parser.parse_program (Lexer.tokenize input)` to a wrapper that creates a sedlex buffer and feeds the Menhir entry point.
- **`test_lexer.ml`** (510 lines): Input → token list tests. All `Lexer.IDENT`, `Lexer.SEQ`, etc. references must be updated to `Parser.IDENT`, `Parser.SEQ`, etc. (or the lexer re-exports tokens). Wrap sedlex in `tokenize_all : string -> token list` helper that pulls tokens until EOF, producing a list compatible with existing test assertions.
- **`Lexer.located` adaptation**: The current tests assert on `Lexer.located` records (`{ token; loc }`). The `tokenize_all` helper must produce equivalent records. Either preserve the `located` type in the new lexer module or define a test-local equivalent.
- **Error message tests**: Adapted one by one per the Error Message Strategy table above. Messages that change (e.g., `let ... in` hint losing the binding name) are updated in tests with a comment noting the regression.
- **New: group-with-let test**: Verify `(let x = a in x)` parses correctly, exercising `program_inner` inside parens (validates the `program`/`program_inner` split).
- **New: empty args test**: Verify `noop()` parses to `App(Var "noop", [])`.
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

1. **`call_arg` LR conflict**: Inlining `arg_key` into `call_arg` should resolve the reduce/reduce conflict on `IDENT`. If Menhir still reports a conflict, further restructuring or `%inline` annotations may be needed. This must be verified at build time.
2. **Location precision**: Menhir's `$loc` uses `Lexing.position` (byte-based). The sedlex adapter must maintain a separate codepoint-based column counter and populate `Ast.loc` via a side-channel. This is a known difficulty with sedlex + Menhir integration and requires careful implementation.
3. **Static linking (CI)**: Alpine/musl static builds must work with sedlex and menhir runtime. Both are pure OCaml, so this should be fine.
4. **Lambda duplicate parameter check**: Currently done in `parse_lambda` with a `StringSet`. Moves to a Menhir semantic action in `lambda_params` or a post-parse validation step.
5. **Comment attachment regression**: The current parser attaches comments to binary operator nodes. The migration drops all comment handling. This is accepted as the current behavior was partial and buggy (see CLAUDE.md Known Bugs).
6. **`let ... in` hint specificity**: The migration hint loses binding-name interpolation because Menhir `.messages` cannot reference semantic values. The message becomes generic.

### What Does NOT Change

- `lib/ast.ml` — AST definition
- `lib/reducer.ml` — desugaring and beta reduction
- `lib/checker.ml` — structural validation
- `lib/printer.ml` — AST pretty-printing
- `lib/markdown.ml` — literate mode support
- `test/test_reducer.ml`, `test/test_checker.ml`, `test/test_printer.ml`, `test/test_markdown.ml`, `test/test_integration.ml`
