---
id: RULE-003
title: Question operator requires downstream alternation
domain: checker
severity: warning
---

## Given

A reduced Arrow DSL expression containing a `?` (question) operator.

## When

The checker validates the expression structure.

## Then

- If `?` is followed by a downstream `|||` (alternation) in the same `Seq` chain, no warning is emitted.
- If `?` has no downstream `|||`, a warning is emitted indicating the question lacks a matching alternation.
- "Downstream" means in a subsequent `>>>` position — an `|||` before `?` does **not** satisfy the pairing.
- Intermediate steps between `?` and `|||` are allowed (e.g., `"ok"? >>> log >>> (yes ||| no)` is valid).
- An `|||` in a parallel branch (`***`) does **not** satisfy the pairing.
- A `?` that appears as an operand of `|||` (e.g., `c? ||| d`) produces a specific warning about being an "operand of '|||'" rather than consuming the `|||` as its match.

## Unless

N/A — this is a warning, not an error. The expression still parses and reduces successfully.

## Examples

| Input | Warnings | Pass? |
|---|---|---|
| `"ready"? >>> (go \|\|\| stop)` | 0 | yes |
| `"ready"? >>> process >>> done` | 1 (missing `\|\|\|`) | yes |
| `"ok"? >>> log >>> (yes \|\|\| no)` | 0 | yes |
| `"ready"? >>> a *** (b \|\|\| c)` | 1 (`\|\|\|` in `***` branch doesn't count) | yes |
| `(a \|\|\| b) >>> "ready"? >>> process` | 1 (upstream `\|\|\|` doesn't count) | yes |
| `c? \|\|\| d` | 1 (specific: operand of `\|\|\|`) | yes |
| `"a"? >>> (x \|\|\| y) >>> "b"? >>> (p \|\|\| q)` | 0 | yes |
| `"a"? >>> "b"? >>> (x \|\|\| y)` | 1 (first `?` unmatched) | yes |

## Properties

- **Directional**: Only downstream (rightward in `>>>` chain) `|||` satisfies the pairing.
- **Per-question**: Each `?` requires its own `|||`.
- **Non-blocking**: Warnings do not prevent successful compilation.
