---
id: RULE-009
title: Emitted workflow output never contains nondeterminism tokens
domain: emitter
severity: error
---

## Given

A valid Arrow DSL source string from the supported `--emit workflow` subset.

## When

`Wf_lower.lower` succeeds and `Wf_emit.to_string` renders the `Wf_ir.t` to a
JavaScript string.

## Then

The emitted string does **not** contain any of the following substrings:

- `Date.now`
- `Math.random`
- `new Date`

These are the primary JavaScript nondeterminism sources that would make a
workflow script non-resumable: if a script is interrupted and re-run, any
timestamps or random values would differ, causing divergent behavior and
breaking idempotency.

## Unless

N/A — this invariant is unconditional. The emitter is a pure function
(`Wf_ir.t -> string`) with no access to wall time or entropy; the constraint
documents that property explicitly.

## Examples

| Input | `Date.now` in output? | `Math.random` in output? | `new Date` in output? |
|---|---|---|---|
| `a >>> b` | no | no | no |
| `a &&& b` | no | no | no |
| `gather >>> leaf >>> check?` | no | no | no |
| `branch >>> explore >>> merge` | no | no | no |
| `a >>> check?` (adversarial verify) | no | no | no |
| any valid supported-subset input | no | no | no |

Note: the `Verify` node (`check`/`check?`) emits a `parallel(Array.from({length:
N}, …))` skeptic fan and a majority-vote expression — neither involves
`Date.now`, `Math.random`, or `new Date`. The VERDICT schema const
(`{ type: 'object', properties: { refuted: { type: 'boolean' } }, required:
['refuted'] }`) is a pure literal.

## Properties

- **Deterministic emission**: `Wf_emit.to_string` resets its fresh-variable
  counter at the start of each call, so identical IR inputs produce identical
  outputs across calls (same variable names, same structure, no timestamps
  embedded).
- **No wall-time or entropy**: the emitter constructs JS source purely from the
  IR data structures. It has no call to `Unix.gettimeofday`, `Random.bits`, or
  any OCaml entropy source during emission.
- Enforced by the QCheck property test
  `RULE-009: emitted output contains no Date.now, Math.random, new Date` in
  `test/test_properties.ml` (200 random valid-subset inputs per run), and by
  the unit test `test_no_date_random` in `test/test_wf_emit.ml`.
