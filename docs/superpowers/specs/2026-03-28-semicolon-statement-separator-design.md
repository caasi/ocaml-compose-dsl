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

## Edge Cases

- **Empty program** (empty string / whitespace-only): remains a parse error — `stmts` requires at least one `stmt`
- **`;;`** (empty statement): parse error — `SEMICOLON` is not a valid `stmt`-start token
- **Single statement**: parses as `[expr]` — backwards compatible
- **Literate mode, single block**: `combine` emits no separator (guarded by `current_line > 1`) — no `;` injected

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
