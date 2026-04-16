---
id: RULE-001
title: Operator precedence and associativity
domain: parser
severity: must
---

## Given

A valid Arrow DSL expression containing multiple binary operators.

## When

The parser processes an expression with mixed operators without explicit grouping (parentheses).

## Then

Operators bind with the following precedence (highest to lowest):

1. `***` (parallel) and `&&&` (fanout) — same precedence level
2. `|||` (alternation)
3. `>>>` (sequential composition) — lowest precedence

All binary operators are **right-associative**: `a >>> b >>> c` parses as `Seq(a, Seq(b, c))`.

Parenthesized groups override precedence: `(a >>> b) &&& c` parses as `Fanout(Group(Seq(a, b)), c)`.

## Unless

The expression uses explicit parentheses to override natural precedence.

## Examples

| Input | Expected AST | Pass? |
|---|---|---|
| `a >>> b *** c \|\|\| d` | `Seq(a, Alt(Par(b, c), d))` | yes |
| `a \|\|\| b *** c` | `Alt(a, Par(b, c))` | yes |
| `a *** b &&& c` | `Par(a, Fanout(b, c))` | yes |
| `a >>> b >>> c` | `Seq(a, Seq(b, c))` | yes |
| `a >>> b \|\|\| c &&& d *** e` | `Seq(a, Alt(b, Fanout(c, Par(d, e))))` | yes |
| `(a >>> b) &&& c` | `Fanout(Group(Seq(a, b)), c)` | yes |

## Properties

- **Deterministic**: The same input always produces the same AST structure.
- **Idempotent**: Parsing the same expression twice yields identical results.
- **Composable**: Precedence rules hold regardless of subexpression complexity.
