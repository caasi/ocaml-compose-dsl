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

### EBNF Changes

Add `string` as a `term` alternative. Add comment to `question_term` noting it no longer has a dedicated AST type:

```ebnf
term = node
     | string                                    (* NEW *)
     | "loop" , "(" , seq_expr , ")"
     | "(" , seq_expr , ")"
     | question_term
     | lambda
     ;

question_term = string , "?"                     (* parser-level restriction only; *)
              | node , "?"                        (* AST represents as Question(expr) *)
              ;
```

### Parser Changes

`parse_term` STRING branch:

1. Consume `STRING s`, produce `StringLit s`
2. If followed by `QUESTION`, wrap as `Question(StringLit_expr)`
3. Otherwise, return `StringLit_expr` as-is

Node `?` path: `Question(QNode n)` becomes `Question(node_expr)` where `node_expr` is a `Node n` expression.

### Reducer Changes

`StringLit` is a leaf node containing no variables. `reduce` and `substitute` pass it through unchanged, same as `Node`.

### Checker Changes

`StringLit` is a leaf in structural checking. `normalize` passes it through. `Question`'s inner expr is already constrained by the parser to `Node` or `StringLit`, so no additional validation needed in Checker.

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

## Modules Affected

| Module | Change |
|--------|--------|
| `ast.ml` | Add `StringLit`, remove `question_term`, change `Question` |
| `lexer.ml` | No changes |
| `parser.ml` | Modify `parse_term` STRING branch |
| `reducer.ml` | Add `StringLit` passthrough case |
| `checker.ml` | Update `Question` pattern matches, add `StringLit` leaf handling |
| `printer.ml` | Add `StringLit` case, update `Question` printing |
| `README.md` | Update EBNF grammar |
| `test/test_compose_dsl.ml` | Update existing question tests, add new string literal tests |
