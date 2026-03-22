# Remove Loop Evaluation Node Check — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the hardcoded English-only loop evaluation node check from the checker, closing issue #12.

**Architecture:** Delete the `has_eval` scanning logic from `checker.ml`'s `Loop body ->` branch, remove 11 tests that exist solely to exercise that logic, and verify the remaining `?`/`|||` warning tests still pass.

**Tech Stack:** OCaml, Alcotest, dune

**Spec:** `docs/superpowers/specs/2026-03-22-remove-loop-eval-check-design.md`

---

### Task 1: Add regression test — unicode loop now passes

Before removing anything, add a test that demonstrates the bug (issue #12). This test will fail on the current code and pass after the fix.

**Files:**
- Modify: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write the failing test**

Add this test function after `test_check_loop_eval_inside_question` (after line 753):

```ocaml
let test_check_loop_unicode_no_error () =
  let result = Checker.check (parse_ok "loop (掃描 >>> 檢查)") in
  Alcotest.(check int) "no errors" 0 (List.length result.Checker.errors)
```

Register it in `checker_tests` as the first entry (before `"loop no eval"`, line 1108):

```ocaml
  [ "loop with unicode nodes", `Quick, test_check_loop_unicode_no_error
  ; "loop no eval", `Quick, test_check_loop_no_eval
```

(This becomes the first entry in the list after Task 3 removes the eval-related tests.)

- [ ] **Step 2: Run test to verify it fails**

Run: `dune exec test/test_compose_dsl.exe -- test Checker 0`
Expected: FAIL — the current checker rejects the loop because `掃描` and `檢查` don't match the hardcoded English names.

- [ ] **Step 3: Commit the failing test**

```bash
git add test/test_compose_dsl.ml
git commit -m "test: add failing test for unicode loop nodes (issue #12)"
```

---

### Task 2: Remove eval check from checker

**Files:**
- Modify: `lib/checker.ml:59-82`

- [ ] **Step 1: Replace the Loop branch**

Replace lines 59–82 of `lib/checker.ml`:

```ocaml
    | Loop body ->
      let has_eval = ref false in
      let rec scan (e : expr) =
        match e.desc with
        | Node n ->
          if String.length n.name >= 4 &&
             (let s = String.lowercase_ascii n.name in
              let len = String.length s in
              s = "evaluate" || s = "eval" || s = "check" || s = "test"
              || s = "judge" || s = "verify" || s = "validate"
              || (len >= 4 && String.sub s 0 4 = "eval")
              || (len >= 5 && String.sub s 0 5 = "check")) then
            has_eval := true
        | Seq (a, b) | Par (a, b) | Fanout (a, b) | Alt (a, b) -> scan a; scan b
        | Loop inner -> scan inner
        | Group inner -> scan inner
        | Question (QNode n) -> scan { loc = e.loc; desc = Node n }
        | Question (QString _) -> ()
      in
      scan body;
      if not !has_eval then
        add_error e.loc "loop has no evaluation/termination node (expected a node like 'evaluate', 'check', 'verify', etc.)";
      check_question_balance body;
      go body
```

With:

```ocaml
    | Loop body ->
      check_question_balance body;
      go body
```

- [ ] **Step 2: Run the regression test to verify it passes**

Run: `dune exec test/test_compose_dsl.exe -- test Checker 0`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add lib/checker.ml
git commit -m "fix: remove loop evaluation node check (closes #12)

The checker no longer rejects loops that lack English-named
evaluation nodes. This is a semantic concern, not structural.
The ? + ||| warning mechanism remains as a structural hint."
```

---

### Task 3: Remove obsolete tests

**Files:**
- Modify: `test/test_compose_dsl.ml`

- [ ] **Step 1: Remove test functions**

Delete these 11 test functions (and their bodies):

1. `test_check_loop_no_eval` (line 654–658)
2. `test_check_loop_with_evaluate` (line 660–662)
3. `test_check_loop_with_verify` (line 664–666)
4. `test_check_loop_with_check` (line 668–670)
5. `test_check_nested_loop_both_need_eval` (line 672–674)
6. `test_check_loop_with_fanout_and_eval` (line 676–678)
7. `test_check_loop_with_test` (line 680–682)
8. `test_check_loop_with_checking` (line 684–686)
9. `test_check_loop_eval_inside_question` (line 748–753)
10. `test_check_loop_no_eval_loc` (line 890–894)
11. `test_check_multiline_loc` (line 902–906)

- [ ] **Step 2: Remove test registrations**

Delete these entries from the `checker_tests` list:

```ocaml
  ; "loop no eval", `Quick, test_check_loop_no_eval
  ; "loop with evaluate", `Quick, test_check_loop_with_evaluate
  ; "loop with verify", `Quick, test_check_loop_with_verify
  ; "loop with check", `Quick, test_check_loop_with_check
  ; "nested loops both need eval", `Quick, test_check_nested_loop_both_need_eval
  ; "loop with fanout and eval", `Quick, test_check_loop_with_fanout_and_eval
  ; "loop with test (4-char name)", `Quick, test_check_loop_with_test
  ; "loop with checking (check prefix)", `Quick, test_check_loop_with_checking
  ; "loop eval inside question", `Quick, test_check_loop_eval_inside_question
  ; "loop no eval loc", `Quick, test_check_loop_no_eval_loc
  ; "multiline error loc", `Quick, test_check_multiline_loc
```

The `checker_tests` list's first entry should now be `"loop with unicode nodes"` (added in Task 1), followed by `"question with alt"`.

**Do NOT remove:**
- `"question in loop"` — tests `?`/`|||` warning, not eval detection
- `"question in loop no alt"` — tests `?` warning, not eval detection

- [ ] **Step 3: Run full test suite**

Run: `dune test`
Expected: All tests pass. No compilation errors from removed references.

- [ ] **Step 4: Commit**

```bash
git add test/test_compose_dsl.ml
git commit -m "test: remove obsolete loop eval check tests"
```

---

### Task 4: Verify and finalize

- [ ] **Step 1: Run full test suite one more time**

Run: `dune test`
Expected: All tests pass.

- [ ] **Step 2: Check EBNF/README consistency**

Read `README.md` and verify no prose describes the loop evaluation check. The `evaluate` node in the example pipeline (line 95) is just an example node name, not documentation of the check — no change needed.

- [ ] **Step 3: Verify checker still catches other errors**

Quick sanity — run these through the CLI and confirm behavior:

```bash
echo 'loop (a >>> b)' | dune exec ocaml-compose-dsl
# Expected: exits 0 (no error — the eval check is gone)

echo 'loop (掃描 >>> 檢查)' | dune exec ocaml-compose-dsl
# Expected: exits 0 (unicode loop passes)

echo 'loop ("ready"? >>> process)' | dune exec ocaml-compose-dsl
# Expected: exits 0 with warning on stderr (? without |||)
```

- [ ] **Step 4: Final commit if any adjustments were needed**

Only if previous steps revealed issues that needed fixing.
