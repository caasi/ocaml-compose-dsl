# Epistemic Operator Lint Rules

**Date:** 2026-04-04
**Status:** Draft

## Problem

The DSL is a planning language for human-LLM shared workflows. When tasks involve evidence gathering, multi-path exploration, or verification, pipeline authors reach for names like `gather`, `branch`, `merge`, `leaf`, and `check` — but there is no structural feedback when these are used incorrectly (e.g., `branch` without a corresponding `merge`).

Inspired by [λ-RLM](https://github.com/lambda-calculus-LLM/lambda-RLM)'s approach of constraining neural reasoning to bounded leaf sub-problems while keeping control flow structural and verifiable, these five names can serve as cognitive role markers — but only if the checker can catch common structural mistakes.

## Decision

Add two lint rules to the checker that recognize five **epistemic operator** names by convention. These are ordinary identifiers (not reserved words) — the checker matches them by name in the post-reduce AST. In practice, these names are used as free identifiers (not `let`-bound), so they survive reduction unchanged.

### Epistemic Operators

| Name | Intent | Common Pattern |
|------|--------|----------------|
| `gather` | Collect evidence needs / sub-questions before reasoning | `gather >>> leaf` |
| `branch` | Explore multiple candidate paths | `branch >>> ... >>> merge` |
| `merge` | Converge candidates into a single auditable artifact | `... >>> merge >>> check?` |
| `leaf` | High-cost reasoning zone — bounded sub-problem | `leaf >>> check?` |
| `check` | Verifiable validation step — not just "checked" | `check? >>> (pass \|\|\| fix)` |

### Lint Rules

**Rule 1 — `branch` without `merge` (warning):**
Scan all `Var` and `App` callee names in a statement. If `branch` appears but `merge` does not, emit:

```
'branch' without matching 'merge' in the same statement
```

The reverse (merge without branch) does not warn — `merge` has legitimate standalone uses.

**Rule 2 — `leaf` without `check` (suggestion):**
Same scan. If `leaf` appears but `check` does not, emit:

```
'leaf' without 'check' — consider adding verification
```

This is a softer suggestion, not a structural error.

### What Is Not Linted

- **`gather`**: no clear structural pairing — it can precede `leaf`, `branch`, or arbitrary nodes
- **`check?` without `|||`**: already covered by the existing `?`/`|||` balance warning
- **Scope-aware pairing**: no tracking across nested sub-expressions — the entire statement is scanned flat, matching how LLMs read the DSL

## Design

### Implementation

In `checker.ml`, add:

```ocaml
let epistemic_pairs = [("branch", "merge")]
let epistemic_suggestions = [("leaf", "check")]
```

Add a helper that collects all `Var` and `App` callee names from a post-reduce expression. Since `Lambda`, `Let`, and `Group` are eliminated by the reducer, they are not handled:

```ocaml
let rec collect_ident_names (e : expr) : string list =
  match e.desc with
  | Var name -> [name]
  | App (callee, args) ->
    collect_ident_names callee
    @ List.concat_map (fun arg ->
        match arg with
        | Positional e -> collect_ident_names e
        | Named _ -> []
      ) args
  | Seq (a, b) | Par (a, b) | Fanout (a, b) | Alt (a, b) ->
    collect_ident_names a @ collect_ident_names b
  | Loop body | Question body -> collect_ident_names body
  | Unit | StringLit _ -> []
  | Lambda _ | Let _ | Group _ -> []
```

The `Lambda`, `Let`, and `Group` branches return `[]` as defensive catch-alls — the reducer eliminates these before the checker runs.

Add a function that checks epistemic pairing for a single statement:

```ocaml
let check_epistemic (e : expr) : warning list =
  let names = collect_ident_names e in
  let has name = List.mem name names in
  let warnings = ref [] in
  List.iter (fun (a, b) ->
    if has a && not (has b) then
      warnings := { loc = e.loc; message =
        Printf.sprintf "'%s' without matching '%s' in the same statement" a b
      } :: !warnings
  ) epistemic_pairs;
  List.iter (fun (a, b) ->
    if has a && not (has b) then
      warnings := { loc = e.loc; message =
        Printf.sprintf "'%s' without '%s' — consider adding verification" a b
      } :: !warnings
  ) epistemic_suggestions;
  List.rev !warnings
```

Integrate into `check_program` alongside the existing per-statement `check` call:

```ocaml
let check_program (prog : Ast.program) : result =
  let warnings =
    List.concat_map (fun e ->
      (check e).warnings @ check_epistemic e
    ) prog
  in
  { warnings }
```

### Warning Location

Epistemic warnings use the statement's top-level `loc` (not the specific `branch` or `leaf` node's loc). This keeps the implementation simple — we collect names without tracking individual positions.

Future refinement: if dogfooding shows that statement-level loc is too imprecise, add position tracking to `collect_ident_names`.

## Test Cases

### `branch`/`merge` pairing

| Input | Expected |
|---|---|
| `branch >>> explore >>> merge` | no warning |
| `branch(k: 3) >>> merge(strategy: "best")` | no warning |
| `branch >>> explore` | warning: `branch` without `merge` |
| `merge >>> done` | no warning |
| `gather >>> branch >>> leaf >>> merge >>> check` | no warning |

### `leaf`/`check` suggestion

| Input | Expected |
|---|---|
| `leaf >>> check? >>> (pass \|\|\| fix)` | no warning |
| `leaf(goal: "diagnose") >>> done` | suggestion: `leaf` without `check` |
| `check? >>> (ok \|\|\| retry)` | no warning |
| `gather >>> leaf >>> check` | no warning |

### Multi-statement boundary

| Input | Expected |
|---|---|
| `branch >>> explore; merge >>> done` | warning on first stmt (`branch` without `merge`); no warning on second |

### No interference with existing behavior

| Input | Expected |
|---|---|
| `"ready"? >>> (go \|\|\| stop)` | no warning (existing behavior unchanged) |

## Other File Changes

### README.md

Add an **Epistemic Conventions** section documenting the five operators, their intent, common patterns, and checker warnings. Include attribution to λ-RLM.

Rename existing example `branch(pattern: "feature/*")` to `git_branch(pattern: "feature/*")` to avoid false positive from the new lint.

### CLAUDE.md

Update the `Checker` module description to mention epistemic pairing warnings alongside the existing `?`/`|||` warning.

## What This Spec Does Not Cover

- **Version bump**: v0.11.0 bump follows the CLAUDE.md Version Bumps workflow after implementation
- **Compose skill update**: the `/compose` skill lives in a separate repo and will be updated after the checker binary is released
- **AST changes**: no new AST nodes, fields, or annotations
- **Parser/lexer changes**: no new keywords or grammar productions
- **Trace schema / runtime logging**: deferred to future work
- **Evaluation experiments**: deferred — dogfooding comes first
