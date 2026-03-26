# String Literals as First-Class Expressions

**Date:** 2026-03-26
**Issue:** [#20](https://github.com/caasi/ocaml-compose-dsl/issues/20)
**Status:** Draft

## Problem

String literals cannot be used as positional arguments in function application because they are not valid `term` productions.

```
let greet = \name -> hello(name)
greet("alice")
```

Fails with: `parse error: bare string is not a valid term; did you mean to add '?'?`

Currently strings only appear as named arg values (`node(key: "value")`) and question terms (`"is this true"?`).

## Design

### Approach: `StringLit` as first-class `expr_desc`

Add `StringLit of string` to `expr_desc`, making string literals valid anywhere a `term` can appear. Simultaneously, remove the `question_term` type and simplify `Question` to take an `expr` directly.

### AST Changes

Remove `question_term` type entirely. Modify `expr_desc`:

```ocaml
type expr_desc =
  | Node of node
  | StringLit of string           (* NEW: string as expression *)
  | Seq of expr * expr
  | Par of expr * expr
  | Fanout of expr * expr
  | Alt of expr * expr
  | Loop of expr
  | Group of expr
  | Question of expr              (* CHANGED: was Question of question_term *)
  | Lambda of string list * expr
  | Var of string
  | App of expr * expr list
  | Let of string * expr * expr
```

**Type-widening trade-off:** `Question of expr` accepts any expression at the type level (e.g. `Question(Seq(...))`), but the parser only produces `Question(Node _)` or `Question(StringLit _)`. This is intentional — keeping the AST type simple outweighs encoding the parser restriction in the type system. Other modules (reducer, checker, printer) should handle `Question(expr)` generically rather than relying on the parser invariant.

### EBNF Changes

Factor `string` and `node` with optional `?` to make the lookahead-based disambiguation explicit:

```ebnf
term = node , [ "?" ]                              (* node, optionally question *)
     | string , [ "?" ]                            (* NEW: string literal, optionally question *)
     | "loop" , "(" , seq_expr , ")"
     | "(" , seq_expr , ")"
     | lambda
     ;
```

The old `question_term` production is removed. The `?` suffix is now shown inline on `node` and `string`. The parser uses lookahead (peek for `QUESTION` after consuming the base term) to disambiguate. AST represents both forms as `Question(expr)`.

### Parser Changes

**`parse_term` STRING branch:**

1. Consume `STRING s`, produce `StringLit s` expression
2. If followed by `QUESTION`, wrap as `Question(stringlit_expr)`
3. Otherwise, return `stringlit_expr` as-is

**`parse_term` IDENT `?` path:** `Question(QNode n)` becomes `Question(node_expr)` where `node_expr` is a `Node n` expression.

**`attach_comments_right`:** Update `Question` patterns from `Question(QNode n)` / `Question(QString _)` to handle `Question(expr)`. `StringLit` has no `comments` field, so comments trailing a `Question(StringLit _)` are dropped (same behavior as current `QString`). Add a `StringLit` case as a leaf (no comments to attach).

**Error message:** The catch-all error in `parse_term` currently says `"expected node, string with '?', '(', 'loop', or '\\' (lambda)"`. Update to include bare strings as valid: `"expected node, string, '(', 'loop', or '\\' (lambda)"`.

### Reducer Changes

`StringLit` is a leaf node containing no variables. Every function that pattern-matches `expr_desc` needs a `StringLit` arm:

| Function | Change |
|----------|--------|
| `free_vars` | `\| StringLit _ -> StringSet.empty` (same as `Node`) |
| `substitute` | `\| StringLit _ -> e` (passthrough, same as `Node`) |
| `desugar` | `\| StringLit _ -> e` (passthrough) |
| `beta_reduce` | `\| StringLit _ -> e` (passthrough) |
| `verify` | `\| StringLit _ -> ()` (no-op, same as `Node`) |

`Question` patterns in all functions: update from `Question(QNode _)` / `Question(QString _)` to `Question(inner_expr)` and recurse into `inner_expr` (for `free_vars`, `substitute`, `desugar`, `beta_reduce`) or process generically (for `verify`).

### Checker Changes

Every match site in `checker.ml` that handles `expr_desc` needs a `StringLit` arm:

| Function | Change |
|----------|--------|
| `normalize` | `\| StringLit _ -> e` (leaf, passthrough like `Node`) |
| `scan_questions` | `\| StringLit _ -> counter` (leaf, no questions inside) |
| `tail_has_question` | Currently uses catch-all `_ -> false`; works without change |
| `go` (main check) | Add `\| StringLit _ -> ()` as leaf case. Without this, `StringLit` would fall into the `Lambda \| Var \| App \| Let` error branch and be incorrectly reported as an unreduced node |

`Question` patterns: update from `question_term` matching to generic `Question(expr)` handling.

### Printer Changes

- `StringLit s` prints as `StringLit("s")`
- `Question(expr)` prints the inner expression directly: `Question(StringLit("alice"))` or `Question(Node(...))`
- Old `Question(QString("..."))` and `Question(QNode(...))` forms are replaced

## Examples

After this change, the following become valid:

```
-- string as positional arg
let greet = \name -> hello(name)
greet("alice")

-- string in pipeline position
"hello" >>> process

-- string in parallel
"left" *** "right"

-- string question (unchanged syntax, new AST representation)
"is this ok"?
```

Note: string literals in pipeline/parallel position are syntactically valid but have no built-in semantic meaning — interpretation is left to the runtime or downstream consumer of the AST.

## Modules Affected

| Module | Change |
|--------|--------|
| `ast.ml` | Add `StringLit`, remove `question_term`, change `Question` |
| `lexer.ml` | No changes |
| `parser.ml` | Modify `parse_term` STRING branch, update `attach_comments_right`, update error message |
| `reducer.ml` | Add `StringLit` case to all 5 functions (`free_vars`, `substitute`, `desugar`, `beta_reduce`, `verify`), update `Question` patterns |
| `checker.ml` | Add `StringLit` leaf case to `normalize`, `scan_questions`, `go`; update `Question` patterns |
| `printer.ml` | Add `StringLit` case, update `Question` printing |
| `README.md` | Update EBNF grammar (factor `?` into `node`/`string` alternatives) |
| `CLAUDE.md` | Update `Ast` documentation to list `StringLit` and note `Question of expr` change |
| `test/test_compose_dsl.ml` | Update existing question tests, add new string literal tests |
