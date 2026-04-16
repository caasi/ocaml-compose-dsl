---
id: RULE-004
title: Epistemic operator pairing (branch/merge, leaf/check)
domain: checker
severity: suggestion
---

## Given

A reduced Arrow DSL expression containing epistemic operator names (`branch`, `merge`, `leaf`, `check`).

## When

The checker validates epistemic conventions per statement.

## Then

- `branch` without a corresponding `merge` in the same statement produces a warning (suggestion).
- `leaf` without a corresponding `check` in the same statement produces a warning (suggestion).
- `merge` without `branch` does **not** produce a warning (merge can be standalone).
- `check` without `leaf` does **not** produce a warning (check can be standalone).
- The check is per-statement in multi-statement programs — `branch` in statement 1 is not satisfied by `merge` in statement 2.
- Epistemic warnings do not interfere with `?`/`|||` pairing checks.
- Grouping (`()`) does not prevent detection — `(branch >>> explore)` still warns if there's no `merge`.

## Unless

N/A — these are suggestions, not errors.

## Examples

| Input | Warnings | Pass? |
|---|---|---|
| `branch >>> explore >>> merge` | 0 | yes |
| `branch(k: 3) >>> merge(strategy: "best")` | 0 | yes |
| `branch >>> explore` | 1 (`branch` without `merge`) | yes |
| `merge >>> done` | 0 | yes |
| `leaf >>> check` | 0 | yes |
| `leaf(goal: "diagnose") >>> done` | 1 (`leaf` without `check`) | yes |
| `check? >>> (ok \|\|\| retry)` | 0 | yes |
| `gather >>> branch >>> leaf >>> merge >>> check` | 0 | yes |
| `(branch >>> explore)` | 1 (`branch` without `merge`) | yes |
| `branch >>> explore; merge >>> done` (multi-stmt) | 1 (cross-statement doesn't count) | yes |

## Properties

- **Per-statement**: Pairing is scoped to individual statements.
- **Asymmetric**: Only the "opener" (`branch`, `leaf`) requires its "closer" (`merge`, `check`), not vice versa.
- **Non-blocking**: Suggestions do not prevent successful compilation.
