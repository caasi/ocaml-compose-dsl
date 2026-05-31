---
id: RULE-007
title: Emitted workflow always has exactly one meta export
domain: emitter
severity: error
---

## Given

A valid Arrow DSL source string from the supported `--emit workflow` subset:
named nodes (`Var`, `App` with named args), `>>>` (`Seq`), `***` (`Par`), `&&&`
(`Fanout`), `Group`, `()` (`Unit`), and the epistemic operators `gather` /
`branch` / `leaf` / `merge` / `check` (incl. `check?`), with type annotations.

## When

The source is lowered by `Wf_lower.lower` to a `Wf_ir.t` and then rendered by
`Wf_emit.to_string`.

## Then

- The emitted string contains **exactly one** occurrence of the literal
  `export const meta`.
- The `meta` object contains a `name` field — a JS single-quoted string literal
  derived from the input filename stem (fallback: `'workflow'`).
- The `meta` object contains a `description` field — a JS single-quoted string
  literal derived from the first recovered source comment or prose line
  (fallback: `'Generated from <file>'`).
- Both `name` and `description` are **pure string literals** (not template
  literals and not computed expressions), so the `meta` block is statically
  analyzable.
- The `meta` object contains a `phases` field listing the distinct epistemic
  phase labels found in the IR in first-seen order. When no epistemic operators
  are present, `phases` is the single-element `[{ title: 'Run' }]`.

## Unless

N/A — this invariant holds for every successfully emitted workflow, regardless
of pipeline shape (single node, deep seq, nested parallel, epistemic ops, etc.).

## Examples

| Input | Expected in output |
|---|---|
| `a >>> b` | `export const meta = {\n  name: '…',\n  description: '…',\n  phases: [{ title: 'Run' }],\n}` appears exactly once |
| `a *** b *** c` | one `export const meta` with `phases: [{ title: 'Run' }]` |
| `gather >>> leaf >>> check?` | one `export const meta` with `phases: [{ title: 'Gather' }, { title: 'Leaf' }]` |
| `branch >>> explore >>> merge` | one `export const meta` with `phases: [{ title: 'Branch' }]` |
| `a` (single node) | one `export const meta` |

## Properties

- **Exactly-one**: `count_occurrences "export const meta" output = 1` for every
  valid supported-subset input. Enforced by the QCheck property test
  `RULE-007: emitted output has exactly one export const meta` in
  `test/test_properties.ml`.
- **Pure-literal meta**: `name` and `description` values are escaped via
  `js_string` (single-quoted, backslash-escaped), never via template literals.
  The `Wf_emit.to_string` counter is reset at the start of each call, making
  output deterministic for identical IR inputs.
- **Phases derived, not hardcoded**: `meta.phases` is collected by walking the
  IR (see `collect_phases` in `lib/wf_emit.ml`). The default `[{ title: 'Run' }]`
  is the fallback when the IR contains no `Agent` node with a `phase` field set.
