# Add `let ... in` Syntax for Explicit Let Scope

**Issue:** [#26 — Add `let ... in` syntax for explicit let scope](https://github.com/caasi/ocaml-compose-dsl/issues/26)

**Status:** Design approved

## Problem

`let` bindings currently scope over "the rest of the program" implicitly. The parser's `read_lets` recursively consumes all remaining tokens after the binding as the body — there is no delimiter marking where the scope ends:

```
let x = a >>> b
x >>> c
```

The reducer desugars `let x = e1` into `(\x -> rest)(e1)`, but `rest` is "everything after" — there is no explicit delimiter. This makes the substitution boundary invisible and blocks the introduction of a `;` statement separator (#27).

## Solution: Require `in` Keyword

Add `in` as a keyword that explicitly delimits the scope of a `let` binding:

```
let x = a >>> b in x >>> c
```

This is a **breaking change** — the old syntax without `in` is no longer valid. The parser will produce a helpful migration hint when it encounters the old form.

## Design Decisions

1. **`in` is mandatory** — no backward compatibility with the old implicit-scope syntax.
2. **Body recurses into `program`** — `let x = a in let y = b in x >>> y` nests naturally without parentheses, matching OCaml/Haskell semantics.
3. **Value is `seq_expr`** — the `in` token terminates the value. To nest `let ... in` inside a value, use parentheses: `let x = (let y = a in y) in x`.

## Grammar Change

### Before

```ebnf
program     = { let_binding } , pipeline ;
let_binding = "let" , ident , "=" , seq_expr ;
```

### After

```ebnf
program     = let_expr | pipeline ;
let_expr    = "let" , ident , "=" , seq_expr , "in" , program ;
reserved    = "let" | "loop" | "in" ;
```

`let_expr` is right-recursive through `program`, allowing natural nesting. The value part (`seq_expr`) stops at `in`, so the parser always knows where the value ends and the body begins.

## Implementation

### Lexer (`lib/lexer.ml`)

Add `IN` token as a keyword, same treatment as `LET` and `LOOP`:

- `read_ident` maps the string `"in"` to `IN` token (not `IDENT`)
- Must ensure `in` as a substring of other identifiers (e.g., `input`, `inline`) is not affected — this is already handled by the existing `read_ident` logic which reads the full identifier before checking for keywords

### Parser (`lib/parser.ml`)

**`parse_program` / `read_lets`:**

1. Parse `let IDENT = seq_expr` as before
2. `expect` an `IN` token after the value's `seq_expr`
3. Recursively call `read_lets` to parse the body (which is `program` — either another `let_expr` or a `pipeline`)
4. Return `Let(name, value, body)` — same AST shape as before

**`parse_term` grouping — support `let ... in` inside parentheses:**

Currently `parse_term`'s `LPAREN` branch calls `parse_seq_expr`. This must change to call the `program`-level parser (i.e., `read_lets` or equivalent) so that `(let y = a in y)` is valid. Without this change, the parenthesized nested let test case would fail.

This means `( ... )` grouping now accepts the full `program` grammar, not just `seq_expr`. The `Group` wrapper behavior is unchanged — it wraps whatever expression the inner parser returns (which may now be a `Let` node).

**Lambda body — remains `seq_expr`:**

`parse_lambda` continues to call `parse_seq_expr` for the body. `let ... in` inside a lambda body requires parentheses: `\x -> (let y = x in y)`. Writing `\x -> let y = x in y` is a parse error. This keeps the grammar unambiguous — `let f = \x -> x >>> a in f(b)` parses as `let f = (\x -> x >>> a) in f(b)` because `in` terminates the let's value `seq_expr`, not the lambda body.

**Positional arguments — remain `seq_expr`:**

`parse_call_arg` calls `parse_seq_expr` for positional arguments. `let ... in` inside a positional argument requires parentheses: `f((let x = a in x))`. Writing `f(let x = a in x)` is a parse error.

**Migration hint on error:** When `expect IN` fails, detect if the next token could be the start of an expression (i.e., the old implicit-scope pattern). If so, produce a descriptive error:

```
Parse error at line 2, col 1: expected 'in' after let binding value
Hint: let bindings now require 'in'. Change:
  let x = expr
  body
to:
  let x = expr in body
```

### Reducer (`lib/reducer.ml`)

No changes. The `Let(name, value, body)` AST node is structurally identical — only the parser's method of determining `body` changes.

### Checker (`lib/checker.ml`)

No changes.

### Printer (`lib/printer.ml`)

No changes. The printer outputs constructor-style format (`Let("x", ..., ...)`) which is unaffected.

### AST (`lib/ast.ml`)

No changes. The `Let` variant remains `Let of string * expr * expr`.

## Test Plan

### Lexer Tests

| Test | Input | Expected |
|------|-------|----------|
| `in` keyword | `"in"` | `IN` token |
| `in` inside identifier | `"input"` | `IDENT "input"` |
| `in` after identifier | `"x in"` | `IDENT "x"`, `IN` |
| `in` as prefix of ident | `"input"` | `IDENT "input"` (not `IN` + `IDENT "put"`) |

### Parser Tests — Positive

| Test | Input | Expected AST |
|------|-------|-------------|
| Simple let-in | `let x = a in x` | `Let("x", Var("a"), Var("x"))` |
| Nested let-in | `let x = a in let y = b in x >>> y` | `Let("x", Var("a"), Let("y", Var("b"), Seq(Var("x"), Var("y"))))` |
| Parenthesized value | `let x = (let y = a in y) in x` | `Let("x", Let("y", Var("a"), Var("y")), Var("x"))` |
| Let with complex value | `let f = a >>> b in f >>> c` | `Let("f", Seq(Var("a"), Var("b")), Seq(Var("f"), Var("c")))` |
| Let with lambda value | `let f = \x -> x >>> a in f(b)` | `Let("f", Lambda(["x"], Seq(Var("x"), Var("a"))), App(Var("f"), [Positional(Var("b"))]))` |
| Ident starting with `in` | `let x = in_progress in x` | `Let("x", Var("in_progress"), Var("x"))` |

### Parser Tests — Error

| Test | Input | Expected Error |
|------|-------|---------------|
| Old syntax (no `in`) | `let x = a\nx` | Parse error with migration hint mentioning `in` |
| Missing `in` at EOF | `let x = a` | Parse error expecting `in` |
| Let in lambda body (no parens) | `\x -> let y = x in y` | Parse error (let not valid in `seq_expr`) |
| Let in positional arg (no parens) | `f(let x = a in x)` | Parse error (let not valid in `seq_expr`) |

### Reducer Tests

Existing reducer tests updated to use `in` syntax — behavior unchanged:

| Test | Input | Expected |
|------|-------|----------|
| Simple substitution | `let f = a >>> b in f` | `Seq(Var("a"), Var("b"))` |
| Chain | `let a = x in let b = a in b` | `Var("x")` |
| Lambda apply | `let f = \x -> x >>> a in f(b)` | `Seq(Var("b"), Var("a"))` |

### Integration Tests

Full pipeline (parse → reduce → check) with new syntax.

### Literate Mode Tests

`arrow` blocks containing `let ... in` syntax pass through Markdown extraction correctly.

## Documentation Updates

- **README.md** — update EBNF grammar, all `let` examples
- **CLAUDE.md** — update `arrow` code block examples, project structure description
- **CHANGELOG.md** — document breaking change under new version (0.9.0)

## Version

This is a breaking syntax change. Bump to **0.9.0**.

## Related

- Prerequisite for #27 (`;` statement separator)
- CLAUDE.md Future Ideas: "`in` keyword for let scope"
- CLAUDE.md Future Ideas: "`let ... in` as expression form" (deferred)
