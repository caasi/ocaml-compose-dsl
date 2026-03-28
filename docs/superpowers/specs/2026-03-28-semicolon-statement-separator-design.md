# Semicolon Statement Separator

**Date:** 2026-03-28
**Issue:** [#27](https://github.com/caasi/ocaml-compose-dsl/issues/27)
**Status:** Design

## Problem

A program can only contain one final expression after all `let` bindings. In literate Arrow documents, multiple code blocks are concatenated into a single program — an expression block followed by a `let` block triggers a parse error. The workaround is to convert every intermediate expression into an artificial `let` binding (see 7322bfa).

## Design

Add `;` as a statement separator, allowing multiple independent pipelines in a single program:

```
a >>> b;
let x = c >>> d in x;
e >>> f
```

### AST

New top-level type in `ast.ml`:

```ocaml
type program = expr list
```

No new `expr_desc` variant — `;` is purely syntactic, consumed by the parser.

### Lexer

Add `SEMICOLON` token:

1. Single-character rule in `main_token` / `read_token`:
   ```ocaml
   | ';' -> SEMICOLON
   ```
2. Add `| SEMICOLON` to the `token` type re-export (lines 4–26 of `lexer.ml` re-export every `Parser.token` constructor explicitly).

Not a reserved keyword. `;` is already in `special_ascii`, so it's excluded from identifiers.

### Parser

Grammar change in `parser.mly`:

```menhir
%token SEMICOLON

program:
  | s=stmts EOF { s }
;

stmts:
  | s=stmt { [s] }
  | s=stmt SEMICOLON rest=stmts { s :: rest }
  | s=stmt SEMICOLON { [s] }   (* trailing semicolon *)
;

stmt:
  | LET name=IDENT EQUALS value=seq_expr IN rest=stmt
    { mk_expr $loc (Let(name, value, rest)) }
  | e=seq_expr
    { e }
;
```

**LALR(1) conflict-free:** After `stmt SEMICOLON`, lookahead determines the action:
- `EOF` → reduce (trailing semicolon)
- stmt-start tokens (`LET`, `IDENT`, `STRING`, `LPAREN`, `LOOP`, `BACKSLASH`) → shift into `rest=stmts`

These sets are disjoint.

**Parenthesized expressions:** The `term` rule changes from `program_inner` to `stmt`:

```menhir
(* in term rule *)
| LPAREN inner=stmt RPAREN ...
```

This preserves `(let x = a in x)` but does NOT allow semicolons inside parens — `(a; b)` is a parse error, since `term` uses `stmt` (single statement), not `stmts`.

Return type of `Parser.Incremental.program` changes from `expr` to `program` (i.e. `expr list`).

### Parse_errors

`parse` return type changes to `Ast.program`. The `parser.messages` file must be regenerated after adding `SEMICOLON` to handle new error states. Workflow:

1. `menhir --list-errors parser.mly > parser.messages.new`
2. `menhir --compare-errors parser.messages.new --compare-errors parser.messages parser.mly` to find missing states
3. `menhir --update-errors parser.messages parser.mly > parser.messages.updated` to merge
4. Add messages for new states (e.g. `; a` at program start, `;;` empty statement, `;` in unexpected positions)

### Reducer

New function:

```ocaml
let reduce_program (prog : program) : program =
  List.map reduce prog
```

Each statement is reduced independently — `let` bindings do not leak across `;`.

### Checker

New function:

```ocaml
let check_program (prog : program) : result =
  let warnings = List.concat_map (fun e -> (check e).warnings) prog in
  { warnings }
```

### Printer

New function:

```ocaml
let program_to_string (prog : program) : string =
  String.concat ";\n" (List.map to_string prog)
```

Example output:

```
$ echo 'a >>> b; c >>> d' | dune exec ocaml-compose-dsl
Seq(Var("a"), Var("b"));
Seq(Var("c"), Var("d"))
```

### Markdown.combine

Change the inter-block separator from `'\n'` to `";\n"`:

```ocaml
(* was: Buffer.add_char buf '\n' *)
if current_line > 1 then Buffer.add_string buf ";\n";
```

Line offset table calculation is unchanged — `;\n` contains one `\n`, so line counting stays the same. No trailing `;` after the last block.

### CLI (`bin/main.ml`)

Call chain changes:

```
parse → reduce_program → check_program → program_to_string
```

Error handling remains the same — `List.map reduce` in `reduce_program` raises on the first error. Warnings from all statements are merged and printed to stderr.

### EBNF (`README.md`)

```ebnf
program   = stmt , { ";" , stmt } , [ ";" ] ;
stmt      = let_expr | pipeline ;
let_expr  = "let" , ident , "=" , seq_expr , "in" , stmt ;
pipeline  = seq_expr ;
```

### CLAUDE.md

Update the pipeline description to reflect `parse :: String -> Program` (was `String -> Ast`).

## Amendment: Tolerant Semicolons (2026-03-29)

**Problem:** The original grammar (`stmts = stmt { ";" stmt } [";"]`) rejects consecutive semicolons (`a;;b`) and leading semicolons (`;a`). This causes a practical issue in literate mode: `Markdown.combine` inserts `";\n"` between extracted arrow blocks, so an empty arrow block (empty fenced code block) produces a leading `;` that triggers a parse error. More broadly, a strict separator grammar is unnecessarily fragile — users shouldn't have to worry about accidental double semicolons.

**Alternatives considered:**

1. **`Noop` AST node** — add a new `expr_desc` variant for empty statements, so `";"` parses as `[Noop; Noop]` (separator semantics) or `[Noop]` (terminator semantics). Rejected because: (a) separator semantics makes `";"` produce two nodes, which is unintuitive; (b) terminator semantics would require `a` alone to be invalid (missing terminator) unless we make the terminator optional, which brings us back to the same grammar complexity; (c) every downstream pass (Reducer, Checker, Printer) must handle the new variant; (d) `Noop` nodes have no semantic value — they represent the absence of a statement, not a meaningful operation.

2. **Filter empty blocks in `Markdown.combine`** — skip empty/whitespace-only blocks before joining with `";\n"`. Rejected because it only fixes the literate-mode symptom, not the underlying grammar rigidity. Users writing Arrow files directly would still hit `a;;b` errors.

3. **Lexer-level semicolon collapsing** — collapse consecutive `SEMICOLON` tokens into one in the lexer. Rejected because it loses source fidelity (position information) and moves a grammatical concern into the wrong layer.

**Chosen approach: parser-level tolerant grammar.** Replace `stmts` with two mutually recursive rules that consume any number of semicolons between, before, and after statements:

```menhir
semi_sep_stmts:
  | /* empty */                { [] }
  | SEMICOLON semi_sep_stmts   { $2 }
  | stmt semi_tail             { $1 :: $2 }

semi_tail:
  | /* empty */                { [] }
  | SEMICOLON semi_sep_stmts   { $2 }
```

**LALR(1) conflict-free:** In `semi_sep_stmts`, the lookahead token uniquely determines the production — `SEMICOLON` shifts, stmt-start tokens shift into `stmt`, everything else (e.g. `EOF`) reduces to empty. No ambiguity.

**Semantics:** Extra semicolons are silently consumed by the parser. No new AST node is needed. `a;;;;;;b` produces `[a; b]`. `;;;` and empty input produce `[]` (empty program). `(a; b)` remains a parse error — parenthesized groups use `stmt`, not `semi_sep_stmts`.

## Edge Cases

- **Empty program** (empty string / whitespace-only): valid, produces `[]`
- **`;;`** (consecutive semicolons): valid, produces `[]` — semicolons are silently consumed
- **`;a`** (leading semicolon): valid, produces `[a]`
- **`a;;;;;;b`** (redundant semicolons): valid, produces `[a; b]`
- **Single statement**: parses as `[expr]` — backwards compatible
- **Literate mode, single block**: `combine` emits no separator (guarded by `current_line > 1`) — no `;` injected
- **Literate mode, empty block**: empty block produces empty content, `";\n"` separator is consumed as redundant semicolons — no parse error

## Backwards Compatibility

- Single-statement programs behave identically (a one-element list)
- No changes to `expr` type — all existing AST consumers work unchanged
- Parenthesized expressions don't support `;` — same behavior as before

## Affected Modules

| Module | Change |
|--------|--------|
| `ast.ml` | Add `type program = expr list` |
| `lexer.ml` | Add `SEMICOLON` token + re-export |
| `parser.mly` | Return `program`; add `stmts`, `stmt` rules |
| `parse_errors.ml` | Return type → `program`; regenerate messages |
| `reducer.ml` | Add `reduce_program` |
| `checker.ml` | Add `check_program` |
| `printer.ml` | Add `program_to_string` |
| `markdown.ml` | Separator `'\n'` → `";\n"` |
| `bin/main.ml` | Use `_program` functions |
| `README.md` | Update EBNF |
| `CLAUDE.md` | Update pipeline description |
