# AST Location Information (expr level)

## Goal

Add source location (line/column span) to every `expr` node so that Checker diagnostics (errors and warnings) include precise positional information.

## Non-Goals

- Adding location to `value`, `arg`, or `node` types (future work, easy to extend)
- Changing Printer output format (loc is not printed)
- Changing parse/check logic behavior

## Type Changes (Ast module)

`pos` and `loc` are defined in `Ast` so downstream consumers don't depend on `Lexer`:

```ocaml
type pos = { line: int; col: int }
type loc = { start: pos; end_: pos }
```

`expr` is split into a wrapper and a descriptor:

```ocaml
type expr = { loc: loc; desc: expr_desc }
and expr_desc =
  | Node of node
  | Seq of expr * expr
  | Par of expr * expr
  | Fanout of expr * expr
  | Alt of expr * expr
  | Loop of expr
  | Group of expr
  | Question of question_term
```

`value`, `arg`, `node`, and `question_term` are unchanged.

## Lexer Changes

`Lexer.pos` is replaced by `Ast.pos` (same structure, single source of truth):

```ocaml
open Ast

(* type pos removed — now uses Ast.pos *)
type located = { token: token; pos: pos }
exception Lex_error of pos * string
```

Lexer behavior is unchanged. All existing `pos` references now resolve to `Ast.pos`.

## Parser Changes

### State

Add `last_pos` to track the position of the most recently consumed token:

```ocaml
type state = {
  mutable tokens: located list;
  mutable last_pos: pos;
}
```

`advance` updates `last_pos` before dropping the token.

### Expression construction

A helper builds `expr` from start/end positions:

```ocaml
let mk_expr start end_ desc : expr =
  { loc = { start; end_ }; desc }
```

### Position capture strategy

- **start**: captured from `(current st).pos` at the beginning of each parse function
- **end\_**: taken from `st.last_pos` after the last token of the expression is consumed

### Affected functions

- `parse_term`: each branch (`IDENT`, `STRING`, `LOOP`, `LPAREN`) records start at entry, uses `st.last_pos` as end after consuming closing tokens
- `parse_seq_expr` / `parse_alt_expr` / `parse_par_expr`: binary operators use `lhs.loc.start` as start, `st.last_pos` (after parsing rhs) as end
- `attach_comments_right`: signature changes to destructure `{ loc; desc }` and rewrap — `loc` is preserved unchanged

### Return type

`parse : located list -> expr` — returned `expr` is now `{ loc; desc }`.

## Checker Changes

### Diagnostic types

```ocaml
type error = { loc: Ast.loc; message: string }
type warning = { loc: Ast.loc; message: string }
type result = { errors: error list; warnings: warning list }
```

### Affected logic

- `add_error` / `add_warning` take an additional `loc` parameter
- `go` extracts `loc` from `expr.loc` for each diagnostic:
  - Loop without eval node → error with the `Loop` expr's loc
  - Question/alt balance warning → loc of the enclosing scope expr
- `normalize` operates on `expr` (preserving loc through structural transformations, stripping `Group` wrappers)
- `scan_questions` matches on `expr.desc`

Check logic itself is unchanged — only the plumbing of positional information is added.

## Printer Changes

`to_string` destructures `expr.desc` instead of matching `expr` directly. Location is **not printed** — Printer output remains identical to current behavior:

```ocaml
let rec to_string (e : expr) =
  match e.desc with
  | Node n -> node_to_string n
  | Seq (a, b) -> Printf.sprintf "Seq(%s, %s)" (to_string a) (to_string b)
  (* ... same for all variants ... *)
```

## Test Changes

### No changes needed

- All "parse → print → compare string" round-trip tests remain valid since Printer output is unchanged

### Mechanical changes

- Tests that pattern-match on `Ast.Node`, `Ast.Seq`, etc. must destructure `.desc`:
  ```ocaml
  (* before *)
  | Ast.Seq (Ast.Node _, Ast.Node _) -> ()
  (* after *)
  match (parse_ok "a >>> b").desc with
  | Seq ({ desc = Node _; _ }, { desc = Node _; _ }) -> ()
  ```
- Add a test helper to reduce verbosity:
  ```ocaml
  let desc_of input = (parse_ok input).desc
  ```

### New tests

- Checker error/warning tests that verify `loc` values are correct (line, column, span)

## CLI Changes (bin/main.ml)

Checker diagnostic output includes position, matching the existing lex/parse error format:

```ocaml
(* warnings *)
Printf.eprintf "warning at %d:%d: %s\n" w.loc.start.line w.loc.start.col w.message

(* errors *)
Printf.eprintf "check error at %d:%d: %s\n" e.loc.start.line e.loc.start.col e.message
```

## Future Extensibility

The wrapper pattern (`{ loc; desc }`) can be applied to `value`, `arg`, and `node` independently when needed, without architectural changes.
