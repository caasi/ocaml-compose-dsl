---
id: RULE-008
title: Unsupported constructs always raise Emit_error and never produce output
domain: emitter
severity: error
---

## Given

An Arrow DSL source string that contains one or more constructs that are
**not supported** by `--emit workflow` in v1:

- `|||` alternation (`Alt`)
- `loop` (`Loop`)
- `?` applied to any node other than `check` (non-`check` `Question`)
- Higher-order positional application — `App` whose arg list contains a
  `Positional` sub-expression (e.g. `map(check)`)
- A `***` or `&&&` branch whose subtree **anywhere** contains `check` or
  `merge` (e.g. `a &&& check?`, `(a >>> check?) &&& b`)
- `check` or `merge` in **root position** — no upstream `prev` to verify or
  fuse (standalone `merge`, standalone `check?`, or either as the first node of
  the top-level pipeline)
- An **empty program** — a root `()` (Unit), a `Seq` that collapses to nothing
  after dropping all Units, or an empty source string
- A **multi-statement program** — source with two or more `;`-separated
  statements

## When

`Wf_lower.lower` is called on the reduced program.

## Then

- `Wf_ir.Emit_error (pos, msg)` is raised **before** any JS is written.
- The error message contains a substring identifying the rejected construct
  (see examples below).
- No partial JS output is produced — `wf_lower` fully validates first; only
  on success does `wf_emit` run.
- The CLI exits with code `1` and prints the error to stderr.

## Unless

N/A — rejection is unconditional; there is no mode or flag that suppresses it.

## Examples

| Input | Raised? | Message substring |
|---|---|---|
| `a \|\|\| b` | yes | `not supported` |
| `loop(a)` | yes | `not supported` |
| `x?` (x ≠ check) | yes | `only supported on 'check'` |
| `map(check)` (positional sub-expr) | yes | `positional` |
| `a &&& check?` | yes | `parallel` |
| `(a >>> check?) &&& b` | yes | `parallel` |
| `check?` (root position) | yes | `needs an upstream` |
| `merge` (root position) | yes | `needs an upstream` |
| `check` (root position, no `?`) | yes | `needs an upstream` |
| `()` (root Unit / empty) | yes | `empty pipeline` |
| `() >>> ()` (all-Unit seq) | yes | `empty pipeline` |
| `a >>> b; c >>> d` (multi-stmt) | yes | `multi-statement` |

## Properties

- **Two-phase, never partial**: lowering either raises `Emit_error` or returns a
  fully valid `Wf_ir.t`; `Wf_emit.to_string` is never called on a partially
  valid IR.
- **Fail-loud, not silent**: every unsupported construct produces a named error
  with a source position. No unsupported node is silently dropped or ignored.
- Enforced by the rejection tests in `test/test_wf_lower.ml`:
  `test_alt_rejected`, `test_loop_rejected`, `test_question_noncheck_rejected`,
  `test_higher_order_rejected`, `test_check_in_branch_rejected`,
  `test_check_in_branch_subtree_rejected`, `test_root_check_rejected`,
  `test_root_merge_rejected`, `test_root_bare_check_rejected`,
  `test_empty_program`, `test_all_unit_seq_rejected`.
