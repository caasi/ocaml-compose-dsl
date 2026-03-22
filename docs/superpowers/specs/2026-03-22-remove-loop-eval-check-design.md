# Remove Loop Evaluation Node Check

**Date:** 2026-03-22
**Issue:** [#12](https://github.com/caasi/ocaml-compose-dsl/issues/12)
**Status:** Draft

## Problem

The checker hardcodes English node names (`evaluate`, `eval`, `check`, `test`, `judge`, `verify`, `validate`, plus `eval`/`check` prefix matching) to validate that a `loop` contains an evaluation/termination node. Unicode identifiers like `檢查` are rejected, breaking non-English workflows introduced in v0.4.0.

## Decision

Remove the loop evaluation node check entirely (issue option 3).

### Rationale

1. **Design consistency** — The checker's role is structural validation (well-formed AST, balanced operators). Whether a loop contains a termination condition is a semantic concern that belongs to the expanding agent, not the DSL checker.

2. **`?` operator subsumes the intent** — The `?` + `|||` warning mechanism already provides a structural hint about conditional branching in loops. This is language-agnostic and doesn't rely on name matching.

3. **Unmaintainable heuristic** — Even in English, names like `should_continue`, `is_done`, or `termination_gate` aren't recognized. Expanding the name set is an endless game of whack-a-mole. Annotation markers (e.g., `-- @terminates`) would add syntax complexity for a check that shouldn't exist.

## Changes

### `lib/checker.ml`

Remove the `has_eval` scanning logic from the `Loop body ->` branch (lines 60–80). The branch should retain:
- `check_question_balance body` (question/alt balance warnings)
- `go body` (recursive structural checking)

After the change, `Loop body ->` becomes:

```ocaml
| Loop body ->
  check_question_balance body;
  go body
```

### `test/test_compose_dsl.ml`

**Remove** these test functions and their registrations:

| Function | Line | Reason |
|----------|------|--------|
| `test_check_loop_no_eval` | 654 | Tests the removed error |
| `test_check_loop_with_evaluate` | 660 | Tests eval name recognition |
| `test_check_loop_with_verify` | 664 | Tests eval name recognition |
| `test_check_loop_with_check` | 668 | Tests eval name recognition |
| `test_check_nested_loop_both_need_eval` | 672 | Tests nested loop eval error |
| `test_check_loop_with_fanout_and_eval` | 676 | Tests eval name recognition |
| `test_check_loop_with_test` | 680 | Tests eval name recognition |
| `test_check_loop_with_checking` | 684 | Tests eval name recognition |
| `test_check_loop_eval_inside_question` | 748 | Tests eval recognition through `?` |
| `test_check_loop_no_eval_loc` | 890 | Tests error loc for removed error |
| `test_check_multiline_loc` | 902 | Tests error loc for removed error |

**Retain unchanged:**
- `test_check_question_in_loop` (line 706) — tests `?`/`|||` warning in loop context, uses `eval` as a regular node name
- `test_check_question_in_loop_no_alt` (line 710) — tests `?` without `|||` warning in loop context

### `README.md`

If the EBNF or prose mentions the loop evaluation check, update to reflect its removal.

### Error message removed

```
loop has no evaluation/termination node (expected a node like 'evaluate', 'check', 'verify', etc.)
```

This error will no longer be emitted. Loops without obvious termination nodes will pass the checker silently. The `?` without `|||` warning remains as a lighter structural hint.

## Non-changes

- No new syntax or AST changes
- No changes to lexer or parser
- `?` + `|||` warning mechanism unaffected
- All other checker validations unaffected
