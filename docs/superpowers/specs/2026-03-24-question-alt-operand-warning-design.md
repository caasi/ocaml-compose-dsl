# Improve Warning for `?` as Direct `|||` Operand

**Date:** 2026-03-24
**Issue:** [#16](https://github.com/caasi/ocaml-compose-dsl/issues/16)
**Status:** Draft

## Problem

The checker correctly warns when `?` appears inside an `|||` operand without a downstream `|||` via `>>>`. However, the warning message `'?' without matching '|||' in scope` is confusing when `|||` is visually adjacent — users mistake it for a false positive.

Example triggering confusion:

```
(a >>> b >>> c?) ||| d
```

The user sees `|||` right next to `c?` and thinks the warning is wrong. But `c?` is an operand of `|||`, not upstream of it in a `>>>` chain. The `?` produces Either as output, while `|||` routes based on Either *input* — they don't match.

The correct pattern is `? >>> (left ||| right)`, as in:

```
loop(
  question? >>> (pass ||| retry)
)
```

## Decision

Add a specific warning when `?` appears at the tail of a `>>>` chain (or directly) as an operand of `|||`. Keep the existing generic warning for other cases. This is a **message improvement**, not a behavior change — the checker already warns correctly.

## Analysis

The warning triggers through this path in `go`:

1. `go` reaches `Alt(a, b)`
2. Calls `check_question_balance a` and `check_question_balance b`
3. `scan_questions 0` on the left child (e.g., `Seq(a, Seq(b, Question(c)))`) returns 1
4. Generic warning fires

The fix: before calling `check_question_balance`, detect if `?` sits at the tail of the `|||` operand and emit a more helpful message instead.

## Design

### New helper: `tail_has_question`

Checks if an expression ends with `?` at the tail of a `>>>` chain:

```ocaml
let rec tail_has_question (e : expr) : bool =
  match e.desc with
  | Question _ -> true
  | Seq (_, b) -> tail_has_question b
  | Group inner -> tail_has_question inner
  | _ -> false
```

This detects patterns like:
- `c?` (direct Question)
- `a >>> b >>> c?` (Question at Seq tail)
- `(a >>> c?)` (Question at Seq tail inside Group)

### Modified `go` Alt arm

```ocaml
| Alt (a, b) ->
  let na = normalize a in
  let nb = normalize b in
  if tail_has_question na then
    add_warning a.loc
      "'?' as operand of '|||' does not match; \
       use 'question? >>> (left ||| right)' pattern";
  if tail_has_question nb then
    add_warning b.loc
      "'?' as operand of '|||' does not match; \
       use 'question? >>> (left ||| right)' pattern";
  check_question_balance a;
  check_question_balance b;
  go a; go b
```

This emits the specific warning **in addition to** the generic `'?' without matching '|||' in scope` from `check_question_balance`. Two warnings for the same `?` is acceptable here — the specific one explains *why*, the generic one is the structural diagnosis. If this feels noisy, we can suppress the generic warning when the specific one fires (see Alternatives below).

### Warning message

```
'?' as operand of '|||' does not match; use 'question? >>> (left ||| right)' pattern
```

This tells the user:
1. What's wrong: `?` is an operand of `|||`, not upstream
2. How to fix: use the `? >>> (left ||| right)` pattern

### Alternative: suppress generic warning when specific fires

To avoid double-warning, `go`'s Alt arm could skip `check_question_balance` for the child that triggered `tail_has_question`, since the specific warning is strictly more informative:

```ocaml
| Alt (a, b) ->
  let na = normalize a in
  let nb = normalize b in
  let left_tail_q = tail_has_question na in
  let right_tail_q = tail_has_question nb in
  if left_tail_q then
    add_warning a.loc
      "'?' as operand of '|||' does not match; \
       use 'question? >>> (left ||| right)' pattern";
  if right_tail_q then
    add_warning b.loc
      "'?' as operand of '|||' does not match; \
       use 'question? >>> (left ||| right)' pattern";
  if not left_tail_q then check_question_balance a;
  if not right_tail_q then check_question_balance b;
  go a; go b
```

**Recommendation:** Use the suppression variant. One clear warning per issue is better than two overlapping ones.

**Edge case:** `("a"? >>> "b"? >>> process) ||| fallback` — tail is NOT a question (tail is `process`), so `tail_has_question` returns false. `check_question_balance` fires for the 2 unmatched `?`s. Correct.

**Edge case:** `("a"? >>> "b"?) ||| fallback` — tail IS a question. `tail_has_question` returns true. Specific warning fires for `b?`. `check_question_balance` is suppressed. But `a?` is ALSO unmatched — it won't be warned about. Fix: only suppress the **tail** question's generic warning, not the entire `check_question_balance`.

Revised approach: always run `check_question_balance`, but subtract 1 from its count when `tail_has_question` is true (since that `?` already got a specific warning):

```ocaml
| Alt (a, b) ->
  let na = normalize a in
  let nb = normalize b in
  if tail_has_question na then
    add_warning a.loc
      "'?' as operand of '|||' does not match; \
       use 'question? >>> (left ||| right)' pattern";
  if tail_has_question nb then
    add_warning b.loc
      "'?' as operand of '|||' does not match; \
       use 'question? >>> (left ||| right)' pattern";
  (* Subtract 1 from unmatched count when tail ? already got specific warning *)
  let check_balance_adj has_tail_q (e : expr) =
    let unmatched = scan_questions 0 (normalize e) in
    let adj = if has_tail_q then unmatched - 1 else unmatched in
    for _ = 1 to adj do
      add_warning e.loc "'?' without matching '|||' in scope"
    done
  in
  check_balance_adj (tail_has_question na) a;
  check_balance_adj (tail_has_question nb) b;
  go a; go b
```

This way: `("a"? >>> "b"?) ||| fallback` produces:
- Specific warning for `b?` (tail of `>>>`)
- Generic warning for `a?` (1 unmatched - 1 tail = 0? No...)

Wait — `scan_questions 0 (Seq(Question(a), Question(b)))` = 2. `adj = 2 - 1 = 1`. So 1 generic warning for `a?`. Total: 1 specific + 1 generic. Correct.

And `(c?) ||| d` produces:
- `scan_questions 0 (Question(c))` = 1. `adj = 1 - 1 = 0`. No generic.
- 1 specific warning. Correct.

And `("a"? >>> process) ||| fallback` (existing test):
- `tail_has_question (Seq(Question(a), Node(process)))` = false (tail is Node)
- No specific warning
- `check_question_balance`: `scan_questions 0` = 1. 1 generic warning. Correct. ✓

**Final recommendation:** Use the adjusted approach above.

## Changes

### `lib/checker.ml`

1. Add `tail_has_question` helper (before `check` function or inside it)
2. Modify `go`'s `Alt (a, b)` arm as described above
3. `scan_questions` is made accessible to the adjusted balance check (it's already in scope as a local function inside `check`)

### `test/test_compose_dsl.ml`

Add tests. Tests must assert on **warning message content** (not just count) to distinguish specific vs generic warnings. Use substring matching on the message field:

- Specific: contains `"operand of '|||'"`
- Generic: contains `"without matching '|||'"`

| Test | Input | Expected warnings (count + message type) |
|------|-------|------------------------------------------|
| `?` at tail of `>>>` as `|||` operand | `(a >>> b >>> c?) \|\|\| d` | 1 specific |
| `?` directly as `|||` operand | `c? \|\|\| d` | 1 specific |
| Multiple `?` with tail as `|||` operand | `("a"? >>> "b"?) \|\|\| c` | 2 total: 1 specific (for `"b"?`) + 1 generic (for `"a"?`) |
| `?` not at tail (existing behavior) | `("ready"? >>> process) \|\|\| fallback` | 1 generic (unchanged) |
| Correct `?` >>> `|||` pattern | `"ready"? >>> (go \|\|\| stop)` | 0 warnings (unchanged) |

### Issue #16

Comment with explanation and close as "not a bug — warning is correct, message improved."

## Non-changes

- `scan_questions` logic unchanged
- All existing correct-pattern tests remain passing
- No new AST types or tokens
- `check_question_balance` function signature unchanged
