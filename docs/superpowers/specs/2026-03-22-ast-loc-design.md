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

**Semantics**: `loc` is a half-open interval `[start, end_)`. `end_` points to the codepoint position immediately after the last character of the span. This means `end_.col - start.col` gives the length for single-line spans.

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

`Lexer.pos` is replaced by `Ast.pos`. `Lexer.located` now carries a full `loc` (start + end) instead of just a start `pos`:

```ocaml
open Ast

(* type pos removed — now uses Ast.pos *)
type located = { token: token; loc: loc }
exception Lex_error of pos * string
```

Each token's `loc.start` is captured before consuming, and `loc.end_` is the `pos()` value immediately after consuming the last character of the token (half-open interval). The lexer already tracks a cursor position that advances past each token — `pos()` after consuming naturally gives the correct `end_`.

The `EOF` token gets a zero-width span: `{ start = final_pos; end_ = final_pos }`.

Lexer behavior is unchanged. All existing `pos` references now resolve to `Ast.pos`.

## Parser Changes

### Exception type

`Parse_error` changes from `Lexer.pos` to `Ast.pos`:

```ocaml
exception Parse_error of pos * string
```

This is the same structure — only the module path changes.

### State

Add `last_loc` to track the loc of the most recently consumed token:

```ocaml
type state = {
  mutable tokens: located list;
  mutable last_loc: loc;
}
```

Initial value of `last_loc`: `{ start = { line = 1; col = 1 }; end_ = { line = 1; col = 1 } }`. This is only used if no token has been consumed yet, which cannot happen for valid parse paths (the first call to `parse_term` always consumes at least one token before `last_loc` is read).

`advance` updates `last_loc` to the current token's `loc` before dropping it.

### Expression construction

A helper builds `expr` from a combined loc:

```ocaml
let mk_expr loc desc : expr = { loc; desc }
```

### Position capture strategy

- **start**: captured from `(current st).loc.start` at the beginning of each parse function
- **end\_**: taken from `st.last_loc.end_` after the last token of the expression is consumed

For single-token expressions (e.g., a bare `Node`), the token's own `loc` can be used directly.

### Affected functions

- `parse_term`: each branch (`IDENT`, `STRING`, `LOOP`, `LPAREN`) records start at entry, uses `st.last_loc.end_` as end after consuming closing tokens. For single-token nodes, use the token's `loc` directly.
- `parse_seq_expr` / `parse_alt_expr` / `parse_par_expr`: binary operators build loc as `{ start = lhs.loc.start; end_ = rhs.loc.end_ }` where `rhs` is the recursively parsed right-hand side. Note: `eat_comments` between lhs and the operator will advance `last_loc` as a side effect, but this is harmless because binary operators use sub-expression locs (`lhs.loc.start`, `rhs.loc.end_`) rather than raw `last_loc`.
- `attach_comments_right`: uses `{ e with desc = ... }` pattern to preserve loc while updating the descriptor. The `Question (QString _)` branch returns `e` unchanged (comments are dropped for bare strings — existing behavior). This is preferred over explicit destructuring for conciseness and correctness.

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
- `normalize` operates on `expr`, preserving loc through structural transformations. For `Group` stripping: the Group's loc is discarded and the inner expr's loc is kept (i.e., `{ desc = Group inner; _ } -> normalize inner`). For all other variants, loc is preserved via `{ e with desc = ... }` reconstruction.
- `scan_questions` matches on `expr.desc`
- The inner `scan` function inside the `Loop` branch also matches on `expr.desc`. The existing `Question (QNode n) -> scan (Node n)` line must construct a full `expr` record: `scan { loc = e.loc; desc = Node n }` (reusing the parent's loc, since `scan` only inspects node names and never reads loc).

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

~60 lines in `test_compose_dsl.ml` directly pattern-match on `Ast.Node`, `Ast.Seq`, etc. These must destructure `.desc`:

```ocaml
(* before *)
| Ast.Seq (Ast.Node _, Ast.Node _) -> ()
(* after *)
match (parse_ok "a >>> b").desc with
| Seq ({ desc = Node _; _ }, { desc = Node _; _ }) -> ()
```

Mitigation strategies for verbosity:
- Add a test helper: `let desc_of input = (parse_ok input).desc`
- Use `let open Ast in` to drop module prefixes
- Where possible, convert structural pattern-match tests to round-trip tests (parse → print → compare string), since Printer output is unchanged. This reduces the number of tests that need mechanical rewriting.

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

Lex error and parse error handling: `Lexer.Lex_error` and `Parser.Parse_error` both carry `Ast.pos` now (previously `Lexer.pos`). The fields are identical, so `main.ml` pattern matches work unchanged — only the qualified type path differs.

## Implementation Order

1. **Ast**: add `pos`, `loc`, split `expr` → `expr` + `expr_desc`
2. **Lexer**: remove local `pos`, use `Ast.pos`/`Ast.loc`, change `located` to `{ token; loc }`
3. **Parser**: update state, capture locs, produce `{ loc; desc }` exprs (depends on 1 + 2)
4. **Printer**: match on `.desc` (depends on 1)
5. **Checker**: add loc to diagnostics, match on `.desc` (depends on 1)
6. **CLI**: update diagnostic format strings (depends on 5)
7. **Tests**: mechanical rewrites + new loc tests (depends on all above)

Steps 3–5 can proceed in parallel after 1–2. Note: the codebase will not compile in intermediate states — all modules must be updated together for a successful build.

## Future Extensibility

The wrapper pattern (`{ loc; desc }`) can be applied to `value`, `arg`, and `node` independently when needed, without architectural changes.
