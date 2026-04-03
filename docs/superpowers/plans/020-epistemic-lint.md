# Epistemic Operator Lint Rules — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add checker lint rules that warn on `branch` without `merge` and suggest `check` after `leaf`, recognizing five epistemic operator names by convention.

**Architecture:** Add `collect_ident_names` helper and `check_epistemic` function to `checker.ml`. Integrate into `check` function's return value so both single-statement and multi-statement paths get epistemic warnings. No AST, parser, or lexer changes. Update README.md and CLAUDE.md documentation.

**Tech Stack:** OCaml 5.1, Dune, Alcotest

**Spec:** `docs/superpowers/specs/2026-04-04-epistemic-lint-design.md`

---

### Task 0: Create feature branch

- [ ] **Step 1: Create and switch to feature branch**

```bash
git checkout -b feat/epistemic-lint
```

---

### Task 1: Add failing tests for `branch`/`merge` pairing

**Files:**
- Modify: `test/test_checker.ml`

- [ ] **Step 1: Add test — `branch` with `merge` (no warning)**

```ocaml
let test_check_branch_with_merge () =
  let warnings = check_ok_with_warnings {|branch >>> explore >>> merge|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)
```

- [ ] **Step 2: Add test — `branch` with `merge` using args (no warning)**

```ocaml
let test_check_branch_merge_with_args () =
  let warnings = check_ok_with_warnings {|branch(k: 3) >>> merge(strategy: "best")|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)
```

- [ ] **Step 3: Add test — `branch` without `merge` (warning)**

```ocaml
let test_check_branch_without_merge () =
  let warnings = check_ok_with_warnings {|branch >>> explore|} in
  Alcotest.(check int) "one warning" 1 (List.length warnings);
  Alcotest.(check bool) "warning message" true
    (has_warning_containing "branch" warnings);
  Alcotest.(check bool) "mentions merge" true
    (has_warning_containing "merge" warnings)
```

- [ ] **Step 4: Add test — `merge` without `branch` (no warning)**

```ocaml
let test_check_merge_without_branch () =
  let warnings = check_ok_with_warnings {|merge >>> done|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)
```

- [ ] **Step 5: Add test — all five epistemic operators together (no warning)**

```ocaml
let test_check_all_epistemic_no_warning () =
  let warnings = check_ok_with_warnings {|gather >>> branch >>> leaf >>> merge >>> check|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)
```

- [ ] **Step 6: Register tests in `tests` list**

Add to the `tests` list at the bottom of `test_checker.ml`:

```ocaml
  ; "branch with merge", `Quick, test_check_branch_with_merge
  ; "branch merge with args", `Quick, test_check_branch_merge_with_args
  ; "branch without merge", `Quick, test_check_branch_without_merge
  ; "merge without branch", `Quick, test_check_merge_without_branch
  ; "all epistemic no warning", `Quick, test_check_all_epistemic_no_warning
```

- [ ] **Step 7: Run tests to verify they fail**

```bash
dune test
```

Expected: 1 failure — `test_check_branch_without_merge` expects 1 warning but gets 0. The other tests expect 0 warnings and should pass (no warnings is the default).

Note: Only `test_check_branch_without_merge` will actually fail, because the others assert "0 warnings" which is already the behavior. This is fine — the failing test proves the feature is missing.

- [ ] **Step 8: Commit failing tests**

```bash
git add test/test_checker.ml
git commit -m "test: add failing tests for branch/merge epistemic pairing"
```

---

### Task 2: Add failing tests for `leaf`/`check` suggestion

**Files:**
- Modify: `test/test_checker.ml`

- [ ] **Step 1: Add test — `leaf` with `check` (no warning)**

```ocaml
let test_check_leaf_with_check () =
  let warnings = check_ok_with_warnings {|leaf >>> check? >>> (pass ||| fix)|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)
```

- [ ] **Step 2: Add test — `leaf` without `check` (suggestion)**

```ocaml
let test_check_leaf_without_check () =
  let warnings = check_ok_with_warnings {|leaf(goal: "diagnose") >>> done|} in
  Alcotest.(check int) "one warning" 1 (List.length warnings);
  Alcotest.(check bool) "warning message" true
    (has_warning_containing "leaf" warnings);
  Alcotest.(check bool) "mentions check" true
    (has_warning_containing "check" warnings)
```

- [ ] **Step 3: Add test — `check` alone (no warning)**

```ocaml
let test_check_check_alone () =
  let warnings = check_ok_with_warnings {|check? >>> (ok ||| retry)|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)
```

- [ ] **Step 4: Add test — `gather >>> leaf >>> check` (no warning)**

```ocaml
let test_check_gather_leaf_check () =
  let warnings = check_ok_with_warnings {|gather >>> leaf >>> check|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)
```

- [ ] **Step 5: Register tests in `tests` list**

```ocaml
  ; "leaf with check", `Quick, test_check_leaf_with_check
  ; "leaf without check", `Quick, test_check_leaf_without_check
  ; "check alone", `Quick, test_check_check_alone
  ; "gather leaf check", `Quick, test_check_gather_leaf_check
```

- [ ] **Step 6: Run tests to verify failure**

```bash
dune test
```

Expected: `test_check_leaf_without_check` fails (expects 1 warning, gets 0).

- [ ] **Step 7: Commit failing tests**

```bash
git add test/test_checker.ml
git commit -m "test: add failing tests for leaf/check epistemic suggestion"
```

---

### Task 3: Add failing test for multi-statement boundary

**Files:**
- Modify: `test/test_checker.ml`
- Modify: `test/helpers.ml` (if needed — check if `check_program`-level helper exists)

- [ ] **Step 1: Add test — `branch` and `merge` in separate statements**

The existing `test_check_program_merges_warnings` shows the pattern for multi-statement tests. Follow the same approach — use `parse_program_ok`, `reduce_program`, then `check_program`:

```ocaml
let test_check_epistemic_multi_statement () =
  let prog = Helpers.parse_program_ok "branch >>> explore; merge >>> done" in
  let reduced = Reducer.reduce_program prog in
  let result = Checker.check_program reduced in
  Alcotest.(check int) "one warning on first stmt" 1
    (List.length result.Checker.warnings);
  Alcotest.(check bool) "warning mentions branch" true
    (has_warning_containing "branch" result.Checker.warnings)
```

- [ ] **Step 2: Register test**

```ocaml
  ; "epistemic multi-statement boundary", `Quick, test_check_epistemic_multi_statement
```

- [ ] **Step 3: Run tests to verify failure**

```bash
dune test
```

Expected: fails (expects 1 warning, gets 0).

- [ ] **Step 4: Commit failing test**

```bash
git add test/test_checker.ml
git commit -m "test: add failing test for epistemic multi-statement boundary"
```

---

### Task 4: Implement `collect_ident_names` and `check_epistemic`

**Files:**
- Modify: `lib/checker.ml`

- [ ] **Step 1: Add epistemic role lists**

Add after the `type result` definition (line 4), before `normalize`:

```ocaml
let epistemic_pairs = [("branch", "merge")]
let epistemic_suggestions = [("leaf", "check")]
```

- [ ] **Step 2: Add `collect_ident_names` helper**

Add after the role lists, before `normalize`:

```ocaml
let rec collect_ident_names (e : expr) : string list =
  match e.desc with
  | Var name -> [name]
  | App (callee, args) ->
    collect_ident_names callee
    @ List.concat_map (fun arg ->
        match arg with
        | Positional e -> collect_ident_names e
        | Named _ -> []) args
  | Seq (a, b) | Par (a, b) | Fanout (a, b) | Alt (a, b) ->
    collect_ident_names a @ collect_ident_names b
  | Loop body | Question body -> collect_ident_names body
  | Unit | StringLit _ -> []
  | Lambda _ | Let _ | Group _ -> []
```

- [ ] **Step 3: Add `check_epistemic` function**

Add after `collect_ident_names`:

```ocaml
let check_epistemic (e : expr) : warning list =
  let names = collect_ident_names e in
  let has name = List.mem name names in
  let warnings = ref [] in
  List.iter (fun (a, b) ->
    if has a && not (has b) then
      warnings :=
        { loc = e.loc;
          message =
            Printf.sprintf "'%s' without matching '%s' in the same statement" a b
        }
        :: !warnings)
    epistemic_pairs;
  List.iter (fun (a, b) ->
    if has a && not (has b) then
      warnings :=
        { loc = e.loc;
          message =
            Printf.sprintf
              "'%s' without '%s' \u{2014} consider adding verification" a b
        }
        :: !warnings)
    epistemic_suggestions;
  List.rev !warnings
```

Note: Use `\u{2014}` (em dash) in the suggestion message to match the spec. Verify the OCaml version supports this Unicode escape — OCaml 4.06+ supports `\u{XXXX}` in strings.

- [ ] **Step 4: Integrate `check_epistemic` into `check`**

In the `check` function, append epistemic warnings to the existing warnings. Change the return expression at the end of `check` (currently line 104):

From:
```ocaml
  { warnings = List.rev !warnings }
```

To:
```ocaml
  { warnings = List.rev !warnings @ check_epistemic expr }
```

This ensures both `check` (used by single-statement tests via `check_ok_with_warnings`) and `check_program` (which calls `check` per statement) get epistemic warnings. No change to `check_program` needed.

- [ ] **Step 5: Run tests**

```bash
dune test
```

Expected: all tests pass, including the new epistemic tests.

- [ ] **Step 6: Commit implementation**

```bash
git add lib/checker.ml
git commit -m "feat: add epistemic operator lint rules (branch/merge, leaf/check)"
```

---

### Task 5: Add test for no interference with existing behavior

**Files:**
- Modify: `test/test_checker.ml`

- [ ] **Step 1: Add test — existing `?`/`|||` behavior unchanged**

```ocaml
let test_check_epistemic_no_interference () =
  let warnings = check_ok_with_warnings {|"ready"? >>> (go ||| stop)|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)
```

This duplicates `test_check_question_with_alt` but explicitly documents the non-interference guarantee.

- [ ] **Step 2: Register test**

```ocaml
  ; "epistemic no interference", `Quick, test_check_epistemic_no_interference
```

- [ ] **Step 3: Run tests**

```bash
dune test
```

Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add test/test_checker.ml
git commit -m "test: add epistemic no-interference check"
```

---

### Task 6: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Rename `branch(pattern: "feature/*")` to `git_branch(pattern: "feature/*")`**

On line 176:

```
  >>> branch(pattern: "feature/*") :: Code -> Branch
```

Change to:

```
  >>> git_branch(pattern: "feature/*") :: Code -> Branch
```

- [ ] **Step 2: Add Epistemic Conventions section**

Add before the `## Usage` section (before line 205). Insert after the paragraph ending "Error positions report codepoint-level columns, not byte offsets." (line 203):

```markdown

## Epistemic Conventions

Five identifier names are recognized by the checker as **epistemic operators** —
cognitive role markers for human-LLM shared reasoning scaffolds. They are ordinary
identifiers (not reserved words) with conventional meaning, inspired by
[λ-RLM](https://github.com/lambda-calculus-LLM/lambda-RLM)'s approach of
constraining neural reasoning to bounded leaf sub-problems while keeping
control flow structural and verifiable.

| Name | Intent | Common Pattern |
|------|--------|----------------|
| `gather` | Collect evidence needs / sub-questions before reasoning | `gather >>> leaf` |
| `branch` | Explore multiple candidate paths | `branch >>> ... >>> merge` |
| `merge` | Converge candidates into a single auditable artifact | `... >>> merge >>> check?` |
| `leaf` | High-cost reasoning zone — bounded sub-problem | `leaf >>> check?` |
| `check` | Verifiable validation step — not just "checked" | `check? >>> (pass \|\|\| fix)` |

The checker emits warnings when structural conventions are violated:

- `branch` without `merge` in the same statement
- `leaf` without `check` in the same statement (suggestion)

These operators are not keywords — they can be shadowed by `let` bindings or
used as regular nodes. The checker matches them by name only.
```

- [ ] **Step 3: Validate literate arrow blocks still pass**

```bash
dune exec ocaml-compose-dsl -- --literate README.md
```

Expected: exits 0 (the new section has no arrow blocks).

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: add Epistemic Conventions section and rename branch example"
```

---

### Task 7: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update Checker module description**

On line 47, change:

```
- `Checker` — structural validation and well-formedness warnings. Returns `{ warnings }`. Warnings: e.g. `?` without matching `|||`. Uses `normalize` (graph reduction) to strip `Group` wrappers before balance checking. Independently checks each Positional arg sub-expression in `App`.
```

To:

```
- `Checker` — structural validation and well-formedness warnings. Returns `{ warnings }`. Warnings: `?` without matching `|||`; epistemic pairing: `branch` without `merge`, `leaf` without `check` (suggestion). Uses `normalize` (graph reduction) to strip `Group` wrappers before balance checking. Independently checks each Positional arg sub-expression in `App`.
```

- [ ] **Step 2: Validate literate arrow blocks**

```bash
dune exec ocaml-compose-dsl -- --literate CLAUDE.md
```

Expected: exits 0.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update Checker description with epistemic lint rules"
```

---

### Task 8: Final verification

- [ ] **Step 1: Run full test suite**

```bash
dune test
```

Expected: all tests pass.

- [ ] **Step 2: Run checker on README and CLAUDE.md**

```bash
dune exec ocaml-compose-dsl -- --literate README.md && dune exec ocaml-compose-dsl -- --literate CLAUDE.md
```

Expected: both exit 0.

- [ ] **Step 3: Verify warning output manually**

```bash
echo 'branch >>> explore' | dune exec ocaml-compose-dsl 2>&1 >/dev/null
echo 'leaf >>> done' | dune exec ocaml-compose-dsl 2>&1 >/dev/null
echo 'branch >>> merge' | dune exec ocaml-compose-dsl 2>&1 >/dev/null
```

Expected:
- First: warning about `branch` without `merge`
- Second: suggestion about `leaf` without `check`
- Third: no warning

- [ ] **Step 4: Review all changes**

```bash
git log --oneline feat/epistemic-lint ^main
```

Expected: 7 commits (failing tests × 3, implementation, no-interference test, README, CLAUDE.md).
