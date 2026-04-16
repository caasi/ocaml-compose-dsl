---
id: RULE-005
title: Let/lambda desugaring and beta reduction correctness
domain: reducer
severity: must
---

## Given

A parsed Arrow DSL expression containing `let` bindings and/or lambda expressions.

## When

The reducer processes the expression.

## Then

- `let f = expr in body` is desugared to `(\f -> body)(expr)` and beta-reduced.
- Lambda application substitutes arguments into the lambda body: `(\x -> x >>> a)(b)` reduces to `Seq(b, a)`.
- Free variables (not bound by any `let` or lambda) survive reduction as `Var`.
- Application of a free variable (e.g., `f(b)` where `f` is free) survives as `App(Var("f"), [Positional(Var("b"))])`.
- Arity mismatch (e.g., 2-param lambda called with 1 arg) raises `Reduce_error`.
- Named args on a lambda raises `Reduce_error`.
- Applying a string literal (e.g., `let s = "hello" in s("world")`) raises `Reduce_error`.
- `f()` (empty call) applies `Unit` as the argument.
- Substitution is capture-avoiding (alpha-renaming prevents variable capture).
- Multi-statement programs have independent scopes — `let x = a in x; let x = b in x` reduces to `[Var("a"); Var("b")]`.

## Unless

N/A — reduction errors are fatal and halt the pipeline.

## Examples

| Input | Expected Output | Pass? |
|---|---|---|
| `a >>> b` | `Seq(Var("a"), Var("b"))` | yes |
| `let f = a >>> b in f` | `Seq(Var("a"), Var("b"))` | yes |
| `let f = \x -> x >>> a in f(b)` | `Seq(Var("b"), Var("a"))` | yes |
| `let f = \x, y -> x >>> y in f(a, b)` | `Seq(Var("a"), Var("b"))` | yes |
| `let a = x in let b = a in b` | `Var("x")` | yes |
| `let f = \x -> y in f(a)` | `Var("y")` (free var) | yes |
| `let f = a in f(b)` | `App(Var("a"), [Positional(Var("b"))])` (free var apply) | yes |
| `let f = \x, y -> x in f(a)` | `Reduce_error` (arity mismatch) | yes |
| `let f = \x -> x in f(key: val)` | `Reduce_error` (named on lambda) | yes |
| `let s = "hello" in s("world")` | `Reduce_error` (string lit apply) | yes |
| `let f = \x -> x in f()` | `Unit` | yes |

## Properties

- **Deterministic**: Same input always produces same reduced output.
- **Capture-avoiding**: Alpha-renaming ensures no variable capture during substitution.
- **Scope isolation**: Multi-statement programs have independent scopes.
- **Idempotent**: Reducing an already-reduced expression yields the same result.
