# Improve Warning for `?` as `|||` Operand — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a specific warning when `?` appears as a direct operand of `|||` instead of upstream via `>>>`, with a message suggesting the correct `? >>> (left ||| right)` pattern.

**Architecture:** Add `tail_has_question` helper to detect `?` at the tail of `>>>` chains. Modify `go`'s `Alt` arm to emit specific warnings and adjust generic warning count to avoid double-warning. No changes to `scan_questions`, AST, lexer, or parser.

**Tech Stack:** OCaml 5.1, Dune, Alcotest

**Spec:** `docs/superpowers/specs/2026-03-24-question-alt-operand-warning-design.md`

---

### Task 0: Create feature branch

- [ ] **Step 1: Create and switch to feature branch**

```bash
git checkout -b fix/question-alt-operand-warning
```

---

### Task 1: Add tests for the new specific warning

**Files:**
- Modify: `test/test_compose_dsl.ml`

- [ ] **Step 1: Add helper to check warning messages**

Add after the existing `check_ok_with_warnings` helper (around line 25):

```ocaml
let has_warning_containing substr warnings =
  List.exists (fun (w : Checker.warning) ->
    let len = String.length substr in
    let rec check i =
      if i + len > String.length w.message then false
      else if String.sub w.message i len = substr then true
      else check (i + 1)
    in
    check 0
  ) warnings
```

- [ ] **Step 2: Add test for `?` at tail of `>>>` chain as `|||` operand**

```ocaml
let test_check_question_tail_as_alt_operand () =
  let warnings = check_ok_with_warnings {|(a >>> b >>> c?) ||| d|} in
  Alcotest.(check int) "one warning" 1 (List.length warnings);
  Alcotest.(check bool) "specific message" true
    (has_warning_containing "operand of '|||'" warnings)
```

- [ ] **Step 3: Add test for `?` directly as `|||` operand**

```ocaml
let test_check_question_direct_alt_operand () =
  let warnings = check_ok_with_warnings {|c? ||| d|} in
  Alcotest.(check int) "one warning" 1 (List.length warnings);
  Alcotest.(check bool) "specific message" true
    (has_warning_containing "operand of '|||'" warnings)
```

- [ ] **Step 4: Add test for multiple `?` with tail as `|||` operand**

```ocaml
let test_check_question_multiple_with_tail_alt_operand () =
  let warnings = check_ok_with_warnings {|("a"? >>> "b"?) ||| c|} in
  Alcotest.(check int) "two warnings" 2 (List.length warnings);
  Alcotest.(check bool) "has specific" true
    (has_warning_containing "operand of '|||'" warnings);
  Alcotest.(check bool) "has generic" true
    (has_warning_containing "without matching" warnings)
```

- [ ] **Step 5: Add test for `?` not at tail (existing behavior unchanged)**

```ocaml
let test_check_question_not_at_tail_alt_operand () =
  let warnings = check_ok_with_warnings {|("ready"? >>> process) ||| fallback|} in
  Alcotest.(check int) "one warning" 1 (List.length warnings);
  Alcotest.(check bool) "generic message" true
    (has_warning_containing "without matching" warnings);
  Alcotest.(check bool) "not specific message" false
    (has_warning_containing "operand of '|||'" warnings)
```

- [ ] **Step 6: Register tests in `checker_tests`**

Add to `checker_tests` list:

```ocaml
  ; "question tail as alt operand", `Quick, test_check_question_tail_as_alt_operand
  ; "question direct alt operand", `Quick, test_check_question_direct_alt_operand
  ; "question multiple with tail alt operand", `Quick, test_check_question_multiple_with_tail_alt_operand
  ; "question not at tail alt operand", `Quick, test_check_question_not_at_tail_alt_operand
```

- [ ] **Step 7: Run tests to verify they fail**

Run: `dune test`
Expected: FAIL — new tests expect specific warning message containing `"operand of '|||'"` but checker only emits `"'?' without matching '|||' in scope"`.

Note: `test_check_question_tail_as_alt_operand` and `test_check_question_direct_alt_operand` will fail on the message check. `test_check_question_not_at_tail_alt_operand` will PASS (it asserts generic message, which is current behavior). `test_check_question_multiple_with_tail_alt_operand` will fail because it expects 2 warnings with different messages.

- [ ] **Step 8: Commit**

```bash
git add test/test_compose_dsl.ml
git commit -m "test: add tests for ? as ||| operand specific warning"
```

---

### Task 2: Implement `tail_has_question` and modify `go`'s `Alt` arm

**Files:**
- Modify: `lib/checker.ml`

- [ ] **Step 1: Add `tail_has_question` helper**

Add inside the `check` function, after `check_question_balance` and before `go`:

```ocaml
  let rec tail_has_question (e : expr) : bool =
    match e.desc with
    | Question _ -> true
    | Seq (_, b) -> tail_has_question b
    | Group inner -> tail_has_question inner
    | _ -> false
  in
```

- [ ] **Step 2: Modify `go`'s `Alt` arm**

Replace the existing `Alt (a, b)` arm:

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
      let check_balance_adj has_tail_q (e : expr) =
        let unmatched = scan_questions 0 (normalize e) in
        let adj = if has_tail_q then unmatched - 1 else unmatched in
        for _ = 1 to adj do
          add_warning e.loc "'?' without matching '|||' in scope"
        done
      in
      check_balance_adj left_tail_q a;
      check_balance_adj right_tail_q b;
      go a; go b
```

- [ ] **Step 3: Run tests to verify they pass**

Run: `dune test`
Expected: all tests pass, including the 4 new ones and all existing checker tests.

- [ ] **Step 4: Verify existing test `test_check_question_inside_alt_branch` still passes**

Run: `dune exec test/test_compose_dsl.exe -- test Checker 14`
Expected: PASS — input `("ready"? >>> process) ||| fallback` has tail `process` (not `?`), so no specific warning fires. Generic warning count unchanged at 1.

- [ ] **Step 5: Commit**

```bash
git add lib/checker.ml
git commit -m "fix(checker): add specific warning for ? as ||| operand (#16)"
```

---

### Task 3: Update issue #16

- [ ] **Step 1: Comment on issue with explanation**

```bash
gh issue comment 16 --repo caasi/ocaml-compose-dsl --body "$(cat <<'BODY'
The warning is correct — \`c?\` as a direct operand of \`|||\` is not consumed by the \`|||\`. In Arrow semantics, \`?\` produces Either as **output**, while \`|||\` routes based on Either **input**. They don't match when \`?\` is an operand rather than upstream via \`>>>\`.

The correct pattern is:

\`\`\`
question? >>> (left ||| right)
\`\`\`

The original example should be restructured, e.g. using a \`loop\` for retry logic:

\`\`\`
loop(
  Cursor(任務: 修正生成結果) >>> "品質通過"?
  >>> (完成 ||| Cursor(任務: 再次修正))
)
\`\`\`

The warning message has been improved to explain this — it now says:

> \`'?' as operand of '|||' does not match; use 'question? >>> (left ||| right)' pattern\`

instead of the generic \`'?' without matching '|||' in scope\`.
BODY
)"
```

- [ ] **Step 2: Close the issue**

```bash
gh issue close 16 --repo caasi/ocaml-compose-dsl --reason "not planned" --comment "Closing as not-a-bug. Warning is correct; message improved for clarity."
```

- [ ] **Step 3: Commit plan**

Plan is already committed. No action needed.
