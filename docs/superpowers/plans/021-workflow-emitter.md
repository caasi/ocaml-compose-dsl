# Workflow Script Emitter (`--emit workflow`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in `--emit workflow` backend pass that transpiles a checked Arrow pipeline into a Claude Code dynamic-workflow JavaScript script.

**Architecture:** A new pipeline stage `parse >>> reduce >>> check >>> emit`, implemented as three library modules — `Wf_ir` (the IR type), `Wf_lower` (`Ast.program -> Wf_ir.t`, raising `Emit_error` on unsupported constructs), and `Wf_emit` (`Wf_ir.t -> string`, a PPrint-based JS pretty-printer). The CLI gains `--emit`/`-o` flags and runs the pass only after a clean check. OCaml never executes the script.

**Tech Stack:** OCaml 5.1, dune, alcotest + qcheck for tests, **PPrint** (new dependency) for JS pretty-printing. Spec: `docs/superpowers/specs/021-workflow-emitter-design.md`.

**Conventions (verified against the repo):**
- Modules have no `.mli` — they expose everything. Match existing style.
- `Ast.expr = { loc; desc; type_ann }`; `loc = { start : pos; end_ : pos }`; `pos = { line; col }`.
- `Ast.expr_desc`: `Unit | Var | StringLit | Seq | Par | Fanout | Alt | Loop | Group | Question | Lambda | App of expr * call_arg list | Let`. `call_arg = Named of arg | Positional of expr`. `arg = { key; value }`. `value = String | Ident | Number | List`.
- Epistemic operators are **plain idents** matched by name (see `lib/checker.ml`).
- `Reducer.reduce_program : Ast.program -> Ast.program` eliminates `Lambda`/`Let` but **preserves `Group`** (verified: `(a >>> b)` reduces to `Group(Seq(…))`). So the emitter's `Group` handling is **load-bearing**, not defensive. Note: `| Group inner -> lower_expr inner` ignores `e.type_ann`, so a type annotation on a parenthesized group (e.g. `(a *** b) :: () -> Sources` in `brainstorming.arr`) is dropped — acceptable per spec (a `Parallel` carries no `out_hint`), but the golden output must be *generated and read*, not hand-predicted.
- `Lexer.tokenize : string -> Lexer.located list` where `type located = { token : token; loc : Ast.loc }` returns **all** tokens including `Lexer.COMMENT of string` — and the comment text is **already `--`/whitespace-stripped at lex time** (`strip_comment_prefix`). This is the channel for comment recovery.
- `Markdown.extract`, `Markdown.combine : block list -> string * offset_table`, `Markdown.translate_line`.
- Tests live in `test/test_*.ml`, registered in `test/main.ml`; shared helpers in `test/helpers.ml`. Run a suite with `dune exec test/main.exe -- test <Suite> <N>` or all with `dune test`.
- **`lib/compose_dsl.ml` is a MANUAL wrapper** — it explicitly aliases `Ast`, `Lexer`, `Parser`, `Checker`, `Printer`, `Reducer`, `Markdown`, `Parse_errors`. A library module is reachable as `Compose_dsl.X` **only if aliased there**. Every new module (`Wf_ir`, `Wf_lower`, `Wf_emit`, `Wf_context`) MUST get a `module Wf_X = Wf_X` line added when created, or tests/`bin` won't compile. Each module task below includes this step.
- **Value shapes:** only `Parallel` produces an `Array` (the `.filter(Boolean)`-ed result). `Agent`, `Synthesize`, and `Verify` all produce a `Scalar` — `Verify` threads forward a boolean (`passed`), not the verdict array. So `is_array_prev` is set by `Parallel` alone.

---

## Task 1: Add the PPrint dependency

**Files:**
- Modify: `dune-project` (add `pprint` to the `ocaml-compose-dsl-lib` `depends` stanza)
- Modify: `lib/dune` (add `pprint` to `(libraries …)`)
- Modify: `.github/workflows/ci.yml` (ensure the opam install step resolves new deps)

- [ ] **Step 0: Install PPrint in the dev switch**

Run: `opam install pprint` — Expected: installed (it is NOT currently in the switch, so `dune build` would otherwise fail with "Library pprint not found"). Confirm with `ocamlfind list | grep pprint`.

- [ ] **Step 1: Add to `dune-project`**

In the `(package (name ocaml-compose-dsl-lib) (depends …))` stanza, add `pprint` after `sedlex`:

```
  menhir
  sedlex
  pprint
  (alcotest :with-test)
```

- [ ] **Step 2: Add to `lib/dune`**

```
 (libraries menhirLib sedlex pprint)
```

- [ ] **Step 3: Build to regenerate the opam file**

Run: `dune build`
Expected: succeeds; `ocaml-compose-dsl-lib.opam` is regenerated to include `pprint` (and the auto-injected `menhir {>= …}` from `(using menhir 2.1)` — keep it).

- [ ] **Step 4: Ensure CI installs the new dep**

`.github/workflows/ci.yml` runs `dune test` on fresh runners. Confirm its dependency-install step installs from the generated opam files (e.g. `opam install . --deps-only --with-test`), so `pprint` resolves on CI. Adjust if it pins an explicit dep list.

- [ ] **Step 5: Commit**

```bash
git add dune-project lib/dune ocaml-compose-dsl-lib.opam
git commit -m "build: add pprint dependency for the workflow emitter"
```

---

## Task 2: Define the Workflow IR

**Files:**
- Create: `lib/wf_ir.ml`
- Test: `test/test_wf_ir.ml`, register in `test/main.ml`

- [ ] **Step 1: Write the failing test**

`test/test_wf_ir.ml` — a smoke test that the types construct and `Emit_error` is raisable:

```ocaml
open Compose_dsl

let test_construct () =
  let a : Wf_ir.agent_spec =
    { label = "x"; prompt = "x"; agent_type = None;
      out_hint = None; comment = None; phase = None }
  in
  let t : Wf_ir.t =
    { name = "demo"; description = "d"; header = []; root = Wf_ir.Agent a }
  in
  Alcotest.(check string) "name" "demo" t.name

let test_emit_error () =
  Alcotest.check_raises "raises Emit_error"
    (Wf_ir.Emit_error ({ Ast.line = 1; col = 1 }, "boom"))
    (fun () -> raise (Wf_ir.Emit_error ({ Ast.line = 1; col = 1 }, "boom")))

let tests =
  [ Alcotest.test_case "construct IR" `Quick test_construct
  ; Alcotest.test_case "Emit_error" `Quick test_emit_error ]
```

- [ ] **Step 2: Run to verify it fails**

Run: `dune build` — Expected: FAIL, `Unbound module Wf_ir`.

- [ ] **Step 3: Implement `lib/wf_ir.ml`**

```ocaml
(* Workflow IR: the bridge between the Arrow AST and the emitted JS.
   Structure only — JS syntax lives in Wf_emit. *)

(* Raised by Wf_lower on any construct unsupported by --emit workflow (v1). *)
exception Emit_error of Ast.pos * string

(* Shape of the value threaded as `prev` into a node. *)
type shape = Scalar | Array

type agent_spec = {
  label      : string;        (* node name → opts.label *)
  prompt     : string;        (* prompt: arg, else label + folded named args *)
  agent_type : string option; (* agent: arg → opts.agentType *)
  out_hint   : string option; (* type_ann.output → "Return a <Out>." prompt line *)
  comment    : string option; (* recovered source comment → // above the call *)
  phase      : string option; (* gather/branch/leaf → phase("…") before the call *)
}

type wf_node =
  | Agent      of agent_spec
  | Seq        of wf_node list
  | Parallel   of wf_node list
  | Synthesize of agent_spec                            (* merge *)
  | Verify     of { spec : agent_spec; skeptics : int } (* check / check? *)

type t = {
  name        : string;
  description : string;
  header      : string list;
  root        : wf_node;
}
```

- [ ] **Step 4: Alias the module in `lib/compose_dsl.ml`**

Add `module Wf_ir = Wf_ir` so `Compose_dsl.Wf_ir` resolves (the wrapper is manual).

- [ ] **Step 5: Register the suite in `test/main.ml`**

Add `; "Wf_ir", Test_wf_ir.tests` to the suite list.

- [ ] **Step 6: Run to verify it passes**

Run: `dune test` — Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/wf_ir.ml lib/compose_dsl.ml test/test_wf_ir.ml test/main.ml
git commit -m "feat: add Wf_ir workflow IR type and Emit_error"
```

---

## Task 3: Lower named nodes to `Agent` (+ empty-program rejection)

**Files:**
- Create: `lib/wf_lower.ml`
- Test: `test/test_wf_lower.ml`, register in `test/main.ml`

Lowering helpers needed: extract `prompt:`/`agent:` named args; fold the rest into a `Parameters:` line; append `out_hint` from `type_ann`. `schema:` is **not** special — it folds into the prompt like any other arg.

- [ ] **Step 1: Write the failing tests**

`test/test_wf_lower.ml`:

```ocaml
open Compose_dsl

let lower input =
  Wf_lower.lower ~name:"t" (Reducer.reduce_program (Parse_errors.parse input))

let agent_of = function Wf_ir.Agent a -> a | _ -> Alcotest.fail "expected Agent"

let test_bare_node () =
  let a = agent_of (lower "deploy").root in
  Alcotest.(check string) "label" "deploy" a.label;
  Alcotest.(check string) "prompt" "deploy" a.prompt

let test_named_args () =
  let a = agent_of (lower {|build(prompt: "do x", agent: "Explore", profile: static)|}).root in
  Alcotest.(check bool) "prompt has override + folded arg"
    true (Helpers.contains a.prompt "do x" && Helpers.contains a.prompt "profile=static");
  Alcotest.(check (option string)) "agent_type" (Some "Explore") a.agent_type

let test_type_ann_hint () =
  let a = agent_of (lower "summarize :: Sources -> Context").root in
  Alcotest.(check bool) "out_hint set" true (a.out_hint = Some "Context")

let test_empty_program () =
  Alcotest.check_raises "empty → Emit_error"
    (Wf_ir.Emit_error ({ Ast.line = 1; col = 1 }, "empty pipeline"))
    (fun () -> ignore (lower "()"))

let tests =
  [ Alcotest.test_case "bare node" `Quick test_bare_node
  ; Alcotest.test_case "named args" `Quick test_named_args
  ; Alcotest.test_case "type-ann hint" `Quick test_type_ann_hint
  ; Alcotest.test_case "empty program" `Quick test_empty_program ]
```

(Note: `check_raises` matches the exception structurally; if the loc differs, relax to a custom matcher that only checks the `Emit_error` constructor + message substring. Prefer a small helper `lower_fails input substr` in `test/helpers.ml` that asserts `Emit_error (_, msg)` with `contains msg substr`.)

- [ ] **Step 2: Add the `lower_fails` helper to `test/helpers.ml`**

```ocaml
let lower_fails lower input substr =
  match lower input with
  | _ -> Alcotest.fail "expected Emit_error"
  | exception Wf_ir.Emit_error (_, msg) ->
    Alcotest.(check bool) (Printf.sprintf "Emit_error contains %S" substr)
      true (contains msg substr)
```

Rewrite `test_empty_program` to use it. Use this helper for all rejection tests below.

- [ ] **Step 3: Run to verify it fails**

Run: `dune build` — Expected: FAIL, `Unbound module Wf_lower`.

- [ ] **Step 4: Implement the `Agent` path in `lib/wf_lower.ml`**

```ocaml
open Ast

let err pos msg = raise (Wf_ir.Emit_error (pos, msg))

let value_to_text = function
  | String s -> s
  | Ident s -> s
  | Number s -> s
  | List vs -> "[" ^ String.concat ", " (List.map value_to_text vs) ^ "]"
(* value_to_text is recursive over List → make it `let rec`. *)

(* Pull prompt:/agent: out; fold the remaining named args into a Parameters line. *)
let agent_spec_of_app (e : expr) (callee_name : string) (args : call_arg list) =
  let prompt = ref None and agent_type = ref None and params = ref [] in
  List.iter (function
    | Named { key = "prompt"; value = String s } -> prompt := Some s
    | Named { key = "agent"; value = (String s | Ident s) } -> agent_type := Some s
    | Named { key; value } -> params := (key ^ "=" ^ value_to_text value) :: !params
    | Positional _ -> err e.loc.start
        "higher-order application (positional args) not supported by --emit workflow (v1)")
    args;
  let base = match !prompt with Some p -> p | None -> callee_name in
  let params_line =
    match List.rev !params with [] -> "" | ps -> "\n\nParameters: " ^ String.concat ", " ps in
  let out_hint = match e.type_ann with Some { output; _ } -> Some output | None -> None in
  { Wf_ir.label = callee_name; prompt = base ^ params_line;
    agent_type = !agent_type; out_hint; comment = None; phase = None }

(* Lower a single expression to a wf_node (epistemic + structure added in later tasks). *)
let rec lower_expr (e : expr) : Wf_ir.wf_node =
  match e.desc with
  | Var name ->
    Wf_ir.Agent (agent_spec_of_app e name [])
  | App ({ desc = Var name; _ }, args) ->
    Wf_ir.Agent (agent_spec_of_app e name args)
  | Unit -> err e.loc.start "empty pipeline: nothing to emit"
  | _ -> err e.loc.start "unsupported construct (todo: later tasks)"

(* Optional args added now (even though comments/header/description are wired in
   Task 11/13), so later tasks never change this signature and break earlier callers. *)
let lower ?(comments = []) ?(header = []) ?description ~name (prog : Ast.program) : Wf_ir.t =
  ignore comments;  (* consumed in Task 11 for node-comment attachment *)
  let root = match prog with
    | [] -> err { line = 1; col = 1 } "empty pipeline: nothing to emit"
    | [e] -> lower_expr e
    | _ -> err (List.hd prog).loc.start
             "multi-statement programs not supported by --emit workflow (v1)"
  in
  let description = match description with Some d -> d | None -> "Generated from " ^ name in
  { name; description; header; root }
```

(Multi-statement handling is intentionally rejected for v1 — examples like `checker.arr` use `;` separators. This is recorded in the spec's deferred list.)

- [ ] **Step 5: Alias the module + register the suite, run tests**

Add `module Wf_lower = Wf_lower` to `lib/compose_dsl.ml`. Add `; "Wf_lower", Test_wf_lower.tests` to `test/main.ml`. Run: `dune test` — Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/wf_lower.ml lib/compose_dsl.ml test/test_wf_lower.ml test/helpers.ml test/main.ml
git commit -m "feat: lower named nodes to Agent; reject empty/multi-statement programs"
```

---

## Task 4: Lower `Seq`, `Group`, `Unit`-in-Seq

**Files:**
- Modify: `lib/wf_lower.ml`
- Test: `test/test_wf_lower.ml`

- [ ] **Step 1: Write failing tests**

```ocaml
let test_seq () =
  match (lower "a >>> b >>> c").root with
  | Wf_ir.Seq [Agent a; Agent b; Agent c] ->
    Alcotest.(check string) "labels" "a,b,c"
      (String.concat "," [a.label; b.label; c.label])
  | _ -> Alcotest.fail "expected flat Seq of 3 Agents"

let test_group_transparent () =
  match (lower "(a >>> b)").root with
  | Wf_ir.Seq [Agent _; Agent _] -> ()
  | _ -> Alcotest.fail "Group should be transparent"

let test_unit_dropped_in_seq () =
  match (lower "a >>> () >>> b").root with
  | Wf_ir.Seq [Agent _; Agent _] -> ()
  | _ -> Alcotest.fail "Unit dropped from Seq"
```

Add to the `tests` list.

- [ ] **Step 2: Run to verify they fail** — Run: `dune test` — Expected: FAIL (`_ -> err … unsupported`).

- [ ] **Step 3: Implement Seq/Group flattening**

In `lower_expr`, add cases (the Reducer **preserves** `Group`, so these are required, not defensive):

```ocaml
  | Group inner -> lower_expr inner
  | Seq _ -> Wf_ir.Seq (flatten_seq e)
```

Add a helper that flattens nested `Seq` and drops `Unit`:

```ocaml
and flatten_seq (e : expr) : Wf_ir.wf_node list =
  match e.desc with
  | Seq (a, b) -> flatten_seq a @ flatten_seq b
  | Group inner -> flatten_seq inner
  | Unit -> []                       (* identity: drop from the chain *)
  | _ -> [lower_expr e]
```

- [ ] **Step 4: Run to verify pass** — `dune test` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/wf_lower.ml test/test_wf_lower.ml
git commit -m "feat: lower Seq (flattened), transparent Group, Unit dropped"
```

---

## Task 5: Lower `Par`/`Fanout` to `Parallel`

**Files:**
- Modify: `lib/wf_lower.ml`
- Test: `test/test_wf_lower.ml`

- [ ] **Step 1: Write failing tests**

```ocaml
let test_fanout () =
  match (lower "a &&& b").root with
  | Wf_ir.Parallel [Agent _; Agent _] -> ()
  | _ -> Alcotest.fail "&&& → Parallel"

let test_par_flattened () =
  match (lower "a *** b *** c").root with
  | Wf_ir.Parallel [Agent _; Agent _; Agent _] -> ()
  | _ -> Alcotest.fail "*** → flat Parallel of 3"
```

- [ ] **Step 2: Run to verify fail** — `dune test`.

- [ ] **Step 3: Implement**

```ocaml
  | Par _ | Fanout _ -> Wf_ir.Parallel (flatten_par e)
```

```ocaml
and flatten_par (e : expr) : Wf_ir.wf_node list =
  match e.desc with
  | Par (a, b) | Fanout (a, b) -> flatten_par a @ flatten_par b
  | Group inner -> flatten_par inner
  | _ -> [lower_expr e]
```

(`***` and `&&&` both flatten to `Parallel`; the split-vs-shared-input distinction is documented as simplified to shared in the spec.)

- [ ] **Step 4: Run to verify pass** — `dune test`.

- [ ] **Step 5: Commit**

```bash
git add lib/wf_lower.ml test/test_wf_lower.ml
git commit -m "feat: lower *** and &&& to Parallel"
```

---

## Task 6: Lower the epistemic operators (+ root `check`/`merge` rejection)

**Files:**
- Modify: `lib/wf_lower.ml`
- Test: `test/test_wf_lower.ml`

`leaf`/`gather`/`branch` → `Agent` with `phase` set; `merge` → `Synthesize`; `check`/`check?` → `Verify {skeptics=3}`. `check`/`merge` need an upstream, so at **root position** (program root, or head of the top-level Seq) they raise `Emit_error`. The lowerer detects root position by who calls `lower_expr`: only the head element of the program / a `Seq` is "root" when nothing precedes it.

Implement root-detection by making `lower` and `flatten_seq` aware of position: the first node of the program-level chain is the root. Simplest: after building the IR, walk it once and reject a `Verify`/`Synthesize` that sits first in the top-level `Seq` or is the whole `root`.

- [ ] **Step 1: Write failing tests**

```ocaml
let test_leaf_phase () =
  match (lower "leaf").root with
  | Wf_ir.Agent a -> Alcotest.(check (option string)) "phase" (Some "Leaf") a.phase
  | _ -> Alcotest.fail "leaf → Agent with phase"

let test_check_verify () =
  match (lower "a >>> check?").root with
  | Wf_ir.Seq [Agent _; Verify { skeptics = 3; _ }] -> ()
  | _ -> Alcotest.fail "a >>> check? → …; Verify{3}"

let test_merge_synth () =
  match (lower "a >>> merge").root with
  | Wf_ir.Seq [Agent _; Synthesize _] -> ()
  | _ -> Alcotest.fail "a >>> merge → …; Synthesize"

let test_root_check_rejected () =
  Helpers.lower_fails lower "check?" "needs an upstream"

let test_root_merge_rejected () =
  Helpers.lower_fails lower "merge" "needs an upstream"
```

- [ ] **Step 2: Run to verify fail** — `dune test`.

- [ ] **Step 3: Implement epistemic recognition**

In `lower_expr`, before the generic `Var`/`App` cases, special-case the names. Extract the callee name and args uniformly first:

```ocaml
and epistemic_node (e : expr) (name : string) (args : call_arg list) : Wf_ir.wf_node option =
  let spec () = agent_spec_of_app e name args in
  match name with
  | "merge"  -> Some (Wf_ir.Synthesize (spec ()))
  | "check"  -> Some (Wf_ir.Verify { spec = spec (); skeptics = 3 })
  | "leaf"   -> Some (Wf_ir.Agent { (spec ()) with phase = Some "Leaf" })
  | "gather" -> Some (Wf_ir.Agent { (spec ()) with phase = Some "Gather" })
  | "branch" -> Some (Wf_ir.Agent { (spec ()) with phase = Some "Branch" })
  | _ -> None
```

Handle `check?` — `Question (Var "check")` / `Question (App (Var "check", args))` → `Verify`; any other `Question` → reject (Task 7). In `lower_expr`:

```ocaml
  | Question inner ->
    (match inner.desc with
     | Var "check" -> Wf_ir.Verify { spec = agent_spec_of_app inner "check" []; skeptics = 3 }
     | App ({ desc = Var "check"; _ }, args) ->
       Wf_ir.Verify { spec = agent_spec_of_app inner "check" args; skeptics = 3 }
     | _ -> err e.loc.start "'?' is only supported on 'check' by --emit workflow (v1)")
```

And route `Var`/`App` through `epistemic_node` first:

```ocaml
  | Var name ->
    (match epistemic_node e name [] with Some n -> n | None -> Wf_ir.Agent (agent_spec_of_app e name []))
  | App ({ desc = Var name; _ }, args) ->
    (match epistemic_node e name args with Some n -> n | None -> Wf_ir.Agent (agent_spec_of_app e name args))
```

- [ ] **Step 4: Implement root-position rejection**

After `lower` builds `root`, validate:

```ocaml
let reject_root_verify_synth pos = function
  | Wf_ir.Verify _ -> err pos "check/merge needs an upstream result to verify/fuse"
  | Wf_ir.Synthesize _ -> err pos "check/merge needs an upstream result to verify/fuse"
  | _ -> ()
in
(match root with
 | Wf_ir.Seq (first :: _) -> reject_root_verify_synth (List.hd prog).loc.start first
 | other -> reject_root_verify_synth (List.hd prog).loc.start other);
```

- [ ] **Step 5: Run to verify pass** — `dune test`.

- [ ] **Step 6: Commit**

```bash
git add lib/wf_lower.ml test/test_wf_lower.ml
git commit -m "feat: lower epistemic ops (leaf/gather/branch/merge/check); reject root check/merge"
```

---

## Task 7: Reject unsupported constructs (fail-loud)

**Files:**
- Modify: `lib/wf_lower.ml`
- Test: `test/test_wf_lower.ml`

Reject `Alt` (`|||`), `Loop`, and any `***`/`&&&` branch whose subtree **contains** a `Verify`/`Synthesize`. (`Question` on non-check and higher-order positional `App` are already handled in Tasks 3/6.)

- [ ] **Step 1: Write failing tests**

```ocaml
let test_alt_rejected () = Helpers.lower_fails lower "a ||| b" "not supported"
let test_loop_rejected () = Helpers.lower_fails lower "loop(a)" "not supported"
let test_question_noncheck_rejected () = Helpers.lower_fails lower "x?" "only supported on 'check'"
let test_higher_order_rejected () = Helpers.lower_fails lower "map(check)" "positional"
let test_check_in_branch_rejected () = Helpers.lower_fails lower "a &&& check?" "parallel"
let test_check_in_branch_subtree_rejected () =
  Helpers.lower_fails lower "(a >>> check?) &&& b" "parallel"
```

- [ ] **Step 2: Run to verify fail** — `dune test`.

- [ ] **Step 3: Implement rejections**

Add explicit `lower_expr` cases:

```ocaml
  | Alt _ -> err e.loc.start "'|||' (alternation) not supported by --emit workflow (v1)"
  | Loop _ -> err e.loc.start "'loop' not supported by --emit workflow (v1)"
```

(`loop` is a reserved keyword, so `loop(a)` parses as `Loop`, never `App(Var "loop", _)` — no separate `App` case is needed.)

For the branch-subtree check, after lowering a `Parallel`, scan each branch's `wf_node` for `Verify`/`Synthesize`:

```ocaml
and contains_verify_or_synth = function
  | Wf_ir.Verify _ | Wf_ir.Synthesize _ -> true
  | Wf_ir.Agent _ -> false
  | Wf_ir.Seq ns | Wf_ir.Parallel ns -> List.exists contains_verify_or_synth ns
```

In the `Par`/`Fanout` case, after building the branch nodes:

```ocaml
  | Par _ | Fanout _ ->
    let branches = flatten_par e in
    if List.exists contains_verify_or_synth branches then
      err e.loc.start
        "check/merge inside a '***'/'&&&' branch is not supported by --emit workflow (v1)";
    Wf_ir.Parallel branches
```

- [ ] **Step 4: Run to verify pass** — `dune test`.

- [ ] **Step 5: Commit**

```bash
git add lib/wf_lower.ml test/test_wf_lower.ml
git commit -m "feat: reject |||, loop, non-check ?, higher-order app, check/merge in parallel"
```

---

## Task 8: Emit — JS primitives, `meta`, `Agent`, `Seq` threading

**Files:**
- Create: `lib/wf_emit.ml`
- Test: `test/test_wf_emit.ml`, register in `test/main.ml`

Use PPrint for layout; keep a single `js_string` helper that escapes/quotes so the template-literal contents never break. The emitter threads `~prev:(string * Wf_ir.shape) option` — `None` at the program root (omit `## Input`).

- [ ] **Step 1: Write failing tests**

```ocaml
open Compose_dsl

let emit input =
  let prog = Reducer.reduce_program (Parse_errors.parse input) in
  Wf_emit.to_string (Wf_lower.lower ~name:"t" prog)

let test_meta_present () =
  Alcotest.(check bool) "one meta" true (Helpers.contains (emit "a >>> b") "export const meta")

let test_root_no_input () =
  let out = emit "a >>> b" in
  (* first agent omits "## Input"; second includes it *)
  Alcotest.(check bool) "second threads prev" true (Helpers.contains out "## Input")

let test_no_date_random () =
  let out = emit "a >>> b" in
  Alcotest.(check bool) "no Date.now" false (Helpers.contains out "Date.now");
  Alcotest.(check bool) "no Math.random" false (Helpers.contains out "Math.random")

let tests =
  [ Alcotest.test_case "meta present" `Quick test_meta_present
  ; Alcotest.test_case "root omits input" `Quick test_root_no_input
  ; Alcotest.test_case "no Date/random" `Quick test_no_date_random ]
```

- [ ] **Step 2: Run to verify fail** — `dune build` — `Unbound module Wf_emit`.

- [ ] **Step 3: Implement primitives + meta + Agent + Seq (PPrint-based)**

The printer builds `PPrint.document` values (PPrint owns layout/indentation; dedicated helpers own escaping). Each node emits a document **and** returns the `(var, shape)` it binds for the next node's `prev`.

```ocaml
open Wf_ir
let str = PPrint.string
let (^^) = PPrint.(^^)
let nl = PPrint.hardline
let lines docs = PPrint.separate nl docs

(* JS single-quoted string literal — escapes \, ', newline. *)
let js_string s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '\'';
  String.iter (fun c -> match c with
    | '\\' -> Buffer.add_string b "\\\\"
    | '\'' -> Buffer.add_string b "\\'"
    | '\n' -> Buffer.add_string b "\\n"
    | c -> Buffer.add_char b c) s;
  Buffer.add_char b '\'';
  Buffer.contents b

(* Escape text for a `…` template literal: backslash, backtick, and ${ . *)
let js_template_body s =
  let b = Buffer.create (String.length s) in
  let n = String.length s in
  let i = ref 0 in
  while !i < n do
    (match s.[!i] with
     | '\\' -> Buffer.add_string b "\\\\"
     | '`'  -> Buffer.add_string b "\\`"
     | '$' when !i + 1 < n && s.[!i + 1] = '{' -> Buffer.add_string b "\\${"; incr i
     | c    -> Buffer.add_char b c);
    incr i
  done;
  Buffer.contents b

(* The prompt as a JS template literal, with optional out-hint + ## Input.
   Interpolations (${…}) are intentionally NOT escaped — they are emitter-controlled. *)
let prompt_expr (a : agent_spec) ~(prev : (string * shape) option) =
  let hint = match a.out_hint with Some o -> Printf.sprintf "\\n\\nReturn a %s." o | None -> "" in
  let input = match prev with
    | None -> ""
    | Some (expr, Scalar) -> Printf.sprintf "\\n\\n## Input\\n${%s}" expr
    | Some (expr, Array)  -> Printf.sprintf "\\n\\n## Input\\n${JSON.stringify(%s)}" expr in
  "`" ^ js_template_body a.prompt ^ hint ^ input ^ "`"

let opts (a : agent_spec) =
  let parts = [Printf.sprintf "label: %s" (js_string a.label)]
    @ (match a.agent_type with Some t -> [Printf.sprintf "agentType: %s" (js_string t)] | None -> [])
    @ (match a.phase with Some p -> [Printf.sprintf "phase: %s" (js_string p)] | None -> []) in
  "{ " ^ String.concat ", " parts ^ " }"
```

**Phase is emitted via `opts.phase`, not a separate `phase("…")` statement.** The
CC workflow API warns that the global `phase()` call races when used inside
concurrent `parallel` thunks and recommends `opts.phase` to assign an agent to a
progress group safely. Using `opts.phase` everywhere also means a `gather`/
`branch`/`leaf` node that appears as a *direct* `&&&`/`***` branch keeps its
phase (the thunk fast-path in Task 9 calls `opts`), with no bypass. `meta.phases`
still declares the phase list.

```ocaml
(* Resettable counter — reset at the top of to_string so golden output is deterministic. *)
let fresh_counter = ref 0
let fresh () = incr fresh_counter; !fresh_counter

(* A fresh, valid JS identifier. DSL labels may be hyphenated/Unicode/duplicated
   (a >>> a), so NEVER use the raw label as a const name — only inside opts.label. *)
let sanitize s =
  String.map (fun c -> if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
                          || (c >= '0' && c <= '9') || c = '_' then c else '_') s
let fresh_var label =
  let s = sanitize label in
  let s = if s = "" || not ((s.[0] >= 'a' && s.[0] <= 'z') || (s.[0] >= 'A' && s.[0] <= 'Z') || s.[0] = '_')
          then "n_" ^ s else s in
  Printf.sprintf "%s_%d" s (fresh ())

(* returns (document, var_name, shape). The var/shape feed the next node's prev. *)
let rec emit_node ~prev (n : wf_node) : PPrint.document * string * shape =
  match n with
  | Agent a ->
    let var = fresh_var a.label in
    let comment = match a.comment with Some c -> str ("// " ^ c) ^^ nl | None -> PPrint.empty in
    (* phase is carried in opts (opts.phase), not a separate phase() statement *)
    let call = str (Printf.sprintf "const %s = await agent(%s, %s)" var (prompt_expr a ~prev) (opts a)) in
    (comment ^^ call, var, Scalar)
  | Seq ns -> emit_seq ~prev ns
  | _ -> failwith "Parallel/Verify/Synthesize: Tasks 9-10"

and emit_seq ~prev = function
  | [] -> (PPrint.empty, "undefined", Scalar)
  | [n] -> emit_node ~prev n
  | n :: rest ->
    let (d1, v, sh) = emit_node ~prev n in
    let (d2, v2, sh2) = emit_seq ~prev:(Some (v, sh)) rest in
    (d1 ^^ nl ^^ d2, v2, sh2)

let to_string (t : t) =
  fresh_counter := 0;   (* deterministic var names per render → stable golden output *)
  let header = List.map (fun h -> str ("// " ^ h)) t.header in
  let meta = lines [
    str "export const meta = {";
    str (Printf.sprintf "  name: %s," (js_string t.name));
    str (Printf.sprintf "  description: %s," (js_string t.description));
    str "  phases: [{ title: 'Run' }],";   (* refined in Task 10 *)
    str "}" ] in
  let (body, last, _) = emit_node ~prev:None t.root in
  let doc = lines (header @ [meta; str ""; body; str (Printf.sprintf "return %s" last)]) ^^ nl in
  let buf = Buffer.create 1024 in
  PPrint.ToBuffer.pretty 1.0 100 buf doc;
  Buffer.contents buf
```

(`js_template_body` makes constraint 009-style "no broken JS" hold for arbitrary `prompt:` strings — the Task 14 property generator may now include backticks/`${`. `fresh` is reset implicitly per `to_string` only if made local; if module-level, reset it at the top of `to_string`.)

- [ ] **Step 4: Alias the module + register suite + run** — add `module Wf_emit = Wf_emit` to `lib/compose_dsl.ml`; add `; "Wf_emit", Test_wf_emit.tests` to `test/main.ml`; `dune test` — PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/wf_emit.ml lib/compose_dsl.ml test/test_wf_emit.ml test/main.ml
git commit -m "feat: emit meta, Agent, and Seq prev-threading"
```

---

## Task 9: Emit — `Parallel` with `.filter(Boolean)` and branch-root prev

**Files:**
- Modify: `lib/wf_emit.ml`
- Test: `test/test_wf_emit.ml`

- [ ] **Step 1: Write failing tests**

```ocaml
let test_parallel_filter () =
  let out = emit "(a *** b) >>> c" in
  Alcotest.(check bool) "parallel" true (Helpers.contains out "parallel([");
  Alcotest.(check bool) "filter(Boolean)" true (Helpers.contains out ".filter(Boolean)");
  Alcotest.(check bool) "c gets array prev" true (Helpers.contains out "JSON.stringify")
```

- [ ] **Step 2: Run to verify fail** — `dune test` (currently `failwith`).

- [ ] **Step 3: Implement `Parallel`**

```ocaml
  | Parallel ns ->
    (* Each branch root receives the SAME prev (the parallel's input), per the B1 contract. *)
    let thunk n =
      match n with
      | Agent a -> str (Printf.sprintf "() => agent(%s, %s)" (prompt_expr a ~prev) (opts a))
      | (Seq _ | Parallel _) ->
        (* A Seq/Parallel branch (e.g. (a >>> b) &&& c) hoists into an inline async IIFE thunk. *)
        let (d, last, _) = emit_node ~prev n in
        str "() => (async () => {" ^^ nl
        ^^ PPrint.nest 2 (d ^^ nl ^^ str (Printf.sprintf "return %s" last)) ^^ nl
        ^^ str "})()"
      | Verify _ | Synthesize _ ->
        failwith "unreachable: check/merge in a branch is rejected by Wf_lower (Task 7)"
    in
    let var = Printf.sprintf "par%d" (fresh ()) in
    let arr = PPrint.separate (str "," ^^ nl) (List.map thunk ns) in
    let d = str (Printf.sprintf "const %s = (await parallel([" var)
            ^^ nl ^^ PPrint.nest 2 arr ^^ nl ^^ str "])).filter(Boolean)" in
    (d, var, Array)
```

`fresh` is the counter from Task 8. Branch roots get the parallel's `~prev` (matching the B1 `emit_node ~prev:(expr*shape)` contract). The `Verify`/`Synthesize` branch arms are statically unreachable because Task 7's lowering rejects them — keep them as `failwith` to satisfy exhaustiveness and document the invariant. The direct-`Agent` thunk fast-path preserves `opts.phase` (via `opts a`) but **drops a node `// comment`** on that branch (comments can't sit in a `() => …` thunk expression); this is an accepted v1 limitation — node comments are preserved on all non-parallel-branch nodes. If it ever matters, route direct agents through the async-IIFE path too.

- [ ] **Step 4: Run to verify pass** — `dune test`.

- [ ] **Step 5: Commit**

```bash
git add lib/wf_emit.ml test/test_wf_emit.ml
git commit -m "feat: emit Parallel with filter(Boolean) and branch-root prev"
```

---

## Task 10: Emit — `Synthesize`, `Verify`, `opts.phase` / `meta.phases`

**Files:**
- Modify: `lib/wf_emit.ml`
- Test: `test/test_wf_emit.ml`

- [ ] **Step 1: Write failing tests**

```ocaml
let test_verify () =
  let out = emit "a >>> check?" in
  Alcotest.(check bool) "skeptic fan" true (Helpers.contains out "parallel(");
  Alcotest.(check bool) "VERDICT schema" true (Helpers.contains out "VERDICT");
  Alcotest.(check bool) "majority vote" true (Helpers.contains out "filter(Boolean)")

let test_synth_scalar () =
  let out = emit "a >>> merge" in
  Alcotest.(check bool) "synthesis agent" true (Helpers.contains out "agent(")

let test_phases_derived () =
  let out = emit "gather >>> a >>> leaf" in
  Alcotest.(check bool) "agent carries opts.phase" true (Helpers.contains out "phase: 'Gather'");
  Alcotest.(check bool) "meta phases lists Gather" true (Helpers.contains out "title: 'Gather'")
```

- [ ] **Step 2: Run to verify fail** — `dune test`.

- [ ] **Step 3: Implement Synthesize + Verify**

```ocaml
  | Synthesize a ->
    let p = js_template_body a.prompt in
    let body = (match prev with
      | Some (v, Array) ->
        Printf.sprintf "%s\\n\\n## Inputs\\n${%s.map((r,i)=>`### ${i}\\n${r}`).join('\\n')}" p v
      | Some (v, Scalar) -> Printf.sprintf "%s\\n\\n## Input\\n${%s}" p v
      | None -> p (* unreachable: root merge rejected by Wf_lower *)) in
    let var = fresh_var a.label in
    let d = str (Printf.sprintf "const %s = await agent(`%s`, %s)" var body (opts a)) in
    (d, var, Scalar)
  | Verify { spec; skeptics } ->
    let subj = match prev with Some (v, _) -> v | None -> "''" (* unreachable: root check rejected *) in
    let var = Printf.sprintf "verdicts%d" (fresh ()) in
    let passed = Printf.sprintf "passed%d" (fresh ()) in
    let d = lines [
      str (Printf.sprintf "const %s = (await parallel(Array.from({length: %d}, (_, i) => () =>" var skeptics);
      PPrint.nest 2 (str (Printf.sprintf
        "agent(`Adversarially verify the following; try to REFUTE it, default refuted if unsure.\\n\\n## Subject\\n${%s}`, { label: `%s:skeptic-${i}`, schema: VERDICT }))))"
        subj spec.label));
      str ".filter(Boolean)";
      str (Printf.sprintf "const %s = %s.filter(v => !v.refuted).length >= Math.ceil(%d / 2)" passed var skeptics) ] in
    (d, passed, Scalar)
```

Note: `Verify` uses a fixed skeptic instruction and **ignores** `spec.prompt` / any folded params on `check(...)` in v1 (the `check` node's own args don't shape the skeptics). Document this in the spec's deferred list. `Verify` also has no `phase` (only `gather`/`branch`/`leaf` set one), so it contributes nothing to `meta.phases`.

Emit the `VERDICT` schema const once, near the top (after `meta`), only if the IR contains a `Verify`. Add a `has_verify : wf_node -> bool` scan and, in `to_string`, conditionally splice a `str "const VERDICT = { type: 'object', properties: { refuted: { type: 'boolean' } }, required: ['refuted'] }"` document into the line list after `meta` when `has_verify t.root`.

- [ ] **Step 4: Implement `meta.phases` derivation**

Replace the hard-coded phases line. Walk the IR collecting `phase` labels in first-seen order (dedup); default `[{ title: 'Run' }]`. Each epistemic `Agent`'s phase is already emitted as `opts.phase` in Task 8 — no separate `phase()` statements.

```ocaml
let collect_phases (n : wf_node) : string list =
  let seen = ref [] in
  let rec go = function
    | Agent { phase = Some p; _ } -> if not (List.mem p !seen) then seen := !seen @ [p]
    | Agent _ | Synthesize _ -> ()
    | Verify { spec; _ } -> (match spec.phase with Some p when not (List.mem p !seen) -> seen := !seen @ [p] | _ -> ())
    | Seq ns | Parallel ns -> List.iter go ns
  in go n;
  match !seen with [] -> ["Run"] | ps -> ps
```

In `to_string`, replace the hard-coded `phases:` line with `phases: [` + the rendered `collect_phases t.root` titles + `]` (default `[{ title: 'Run' }]` when there are no epistemic phases). **No top-level `phase()` statements are emitted** — each epistemic `Agent` carries `opts.phase` (Task 8); agents with no epistemic phase carry no `phase` opt and belong implicitly to the single default phase.

- [ ] **Step 5: Run to verify pass** — `dune test`.

- [ ] **Step 6: Commit**

```bash
git add lib/wf_emit.ml test/test_wf_emit.ml
git commit -m "feat: emit Synthesize, Verify (adversarial fan), opts.phase and meta.phases"
```

---

## Task 11: Context preservation — comments and `meta` derivation

**Files:**
- Modify: `lib/wf_lower.ml` (accept recovered comments), `bin/main.ml` will pass them in (Task 13). For now add a pure function.
- Create: `lib/wf_context.ml` (comment recovery from tokens / markdown)
- Test: `test/test_wf_context.ml`, register in `test/main.ml`

- [ ] **Step 1: Write failing test**

```ocaml
open Compose_dsl
let test_leading_comment_to_header () =
  let comments = Wf_context.comments_of_source "-- hello world\na >>> b" in
  Alcotest.(check bool) "captured" true (List.exists (fun (_,t) -> Helpers.contains t "hello") comments)

let test_description_from_first_comment () =
  Alcotest.(check string) "desc" "hello world"
    (Wf_context.derive_description ["-- hello world"] ~fallback:"x")
```

- [ ] **Step 2: Run to verify fail** — `dune build`.

- [ ] **Step 3: Implement `lib/wf_context.ml`**

```ocaml
(* "-- foo" → "foo". The tokenizer already strips the prefix from COMMENT
   tokens, so this matters only for the literate/prose path (raw "-- …" lines). *)
let strip_dashes s =
  let s = String.trim s in
  if String.length s >= 2 && s.[0] = '-' && s.[1] = '-'
  then String.trim (String.sub s 2 (String.length s - 2)) else s

(* Recover comments (line, text) via the batch tokenizer — NOT the AST.
   Lexer.tokenize returns `located` records: { token; loc }. *)
let comments_of_source (src : string) : (int * string) list =
  Lexer.tokenize src
  |> List.filter_map (fun (t : Lexer.located) ->
       match t.token with
       | Lexer.COMMENT text -> Some (t.loc.start.line, String.trim text)
       | _ -> None)

let derive_description comments ~fallback =
  match comments with c :: _ -> strip_dashes c | [] -> fallback

let derive_name ~path =
  match path with
  | None -> "workflow"
  | Some p ->
    let base = Filename.remove_extension (Filename.basename p) in
    if base = "" then "workflow" else base

(* Standard mode: consecutive leading comments (from line 1) → file-header banner. *)
let leading_block (comments : (int * string) list) : string list =
  let rec take expected = function
    | (ln, txt) :: rest when ln = expected -> txt :: take (expected + 1) rest
    | _ -> []
  in take 1 comments

(* Literate mode: the doc's intro prose = non-empty lines BEFORE the first arrow
   fence (the surrounding Markdown that combine() discards). Header/description
   come from here when the .arr blocks carry no -- comments. *)
let markdown_prose (raw : string) : string list =
  let rec collect acc = function
    | [] -> List.rev acc
    | line :: _ when Markdown.is_opening_fence line -> List.rev acc
    | line :: rest ->
      let t = String.trim line in
      collect (if t = "" then acc else t :: acc) rest
  in collect [] (String.split_on_char '\n' raw)
```

`strip_dashes` is defined before its uses (the COMMENT text is already prefix-stripped, so `comments_of_source` need not call it; `derive_description` applies it for the raw-prose path). `Markdown.is_opening_fence` is reachable directly (same library; no `.mli` hides it).

- [ ] **Step 4: Attach node-level comments in `Wf_lower`**

`lower` already accepts `?comments` (Task 3). Use it: thread the node's `expr.loc.start.line` into `agent_spec_of_app` (add a `~line` param), and set `agent_spec.comment` to the recovered comment whose line matches the node's start line. Header/description are passed in by the caller (Task 13), not derived here. Keep comment attachment best-effort (exact line match).

(The CLI in Task 13 computes `header`/`description` per mode — `leading_block`/`derive_description` of `comments_of_source` in standard mode, `markdown_prose` of the original input in literate mode — and passes them to `lower`. This is where literate-prose preservation actually happens; Task 11 only provides the functions.)

- [ ] **Step 5: Alias the module + run** — add `module Wf_context = Wf_context` to `lib/compose_dsl.ml`; `dune test` — PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/wf_context.ml lib/wf_lower.ml lib/compose_dsl.ml test/test_wf_context.ml test/main.ml
git commit -m "feat: recover comments/prose for header, node comments, and meta description"
```

---

## Task 12: Interactive-ident advisory warning

**Files:**
- Modify: `lib/wf_lower.ml` (or `lib/wf_context.ml`) — add `interactive_idents : Wf_ir.t -> string list`
- Test: `test/test_wf_lower.ml`

- [ ] **Step 1: Write failing test**

```ocaml
let test_interactive_advisory () =
  let t = lower "ask_questions >>> a" in
  Alcotest.(check bool) "flags ask_questions" true
    (List.mem "ask_questions" (Wf_lower.interactive_idents t))
```

- [ ] **Step 2: Run to verify fail** — `dune test`.

- [ ] **Step 3: Implement**

```ocaml
let interactive_set = ["ask_questions"; "present_design"; "propose"; "review"; "ask"; "confirm"; "approve"; "feedback"]
let interactive_idents (t : Wf_ir.t) : string list =
  let found = ref [] in
  let note l = if List.mem l interactive_set && not (List.mem l !found) then found := !found @ [l] in
  let rec go = function
    | Wf_ir.Agent a -> note a.label
    | Wf_ir.Synthesize a -> note a.label
    | Wf_ir.Verify { spec; _ } -> note spec.label
    | Wf_ir.Seq ns | Wf_ir.Parallel ns -> List.iter go ns
  in go t.root; !found
```

(The CLI prints these to stderr in Task 13; emission still exits 0.)

- [ ] **Step 4: Run to verify pass** — `dune test`.

- [ ] **Step 5: Commit**

```bash
git add lib/wf_lower.ml test/test_wf_lower.ml
git commit -m "feat: collect interactive-ident advisories for the emitter"
```

---

## Task 13: CLI wiring — `--emit`, `-o`, value-flag parsing

**Files:**
- Modify: `bin/main.ml`
- Test: `test/test_integration.ml` (or a new `test/test_emit_cli.ml` that shells out is overkill; prefer asserting on library functions). Add a CLI-level integration check via `dune exec`.

- [ ] **Step 1: Write a failing integration test (library-level)**

Add to `test/test_integration.ml` a test that the end-to-end lower+emit on `examples/brainstorming.arr` content contains `export const meta`. (Full CLI arg parsing is verified manually in Step 5.)

- [ ] **Step 2: Run to verify fail** — `dune test`.

- [ ] **Step 3: Add value-flag parsing helpers to `bin/main.ml`**

```ocaml
(* Defined first — both the dangling-value guard and consumed_indices use it. *)
let value_flags = ["--emit"; "-o"; "--output"]

(* Returns the value after `flag`, or None. *)
let flag_value flag =
  let v = ref None in
  for i = 1 to Array.length Sys.argv - 2 do
    if Sys.argv.(i) = flag then v := Some Sys.argv.(i + 1)
  done;
  !v

let emit_target = flag_value "--emit"
let output_path =
  match flag_value "-o" with Some p -> Some p | None -> flag_value "--output"

(* Reject a dangling value-flag (e.g. `--emit` with no following token): flag_value
   only scans 1..len-2, so without this guard a trailing --emit would be silently
   ignored and fall back to default AST printing. *)
let () =
  let n = Array.length Sys.argv in
  if n >= 2 && List.mem Sys.argv.(n - 1) value_flags then begin
    Printf.eprintf "missing value for %s\n" Sys.argv.(n - 1); exit 1
  end
```

Compute a set of consumed indices (the value-flags and their value tokens) once, and have `first_positional_arg` / `first_unknown_flag` skip those indices. Update `usage_text` with the new options.

```ocaml
(* value_flags is already defined above (before flag_value). *)
let consumed_indices =
  let s = Hashtbl.create 8 in
  for i = 1 to Array.length Sys.argv - 1 do
    if List.mem Sys.argv.(i) value_flags && i + 1 < Array.length Sys.argv then begin
      Hashtbl.replace s i ();       (* the flag itself *)
      Hashtbl.replace s (i + 1) ()  (* its value token *)
    end
  done;
  s
```

Then guard the loop body in both `first_positional_arg` and `first_unknown_flag` with `if not (Hashtbl.mem consumed_indices i)`. (`flag_value`'s own bound `1 to len-2` is already correct.) Recognized flags `--emit`/`-o`/`--output` must also be excluded from `first_unknown_flag`'s "starts with `-`" check — the consumed-index guard handles the flag token itself, but add them to the known-flag allowlist too for clarity.

- [ ] **Step 4: Wire the emit pass after a clean check**

In the `| prog ->` branch, after computing `result.warnings` (still print them to stderr), branch on `emit_target`:

```ocaml
  (match emit_target with
   | None ->
     let output = Compose_dsl.Printer.program_to_string prog in
     if output <> "" then print_endline output
   | Some "workflow" ->
     let module C = Compose_dsl.Wf_context in
     (* Node comments come from the Arrow source (`source`); the file header/description
        come from -- comments (standard mode) or the surrounding Markdown prose (literate
        mode — `input` is the ORIGINAL text, before combine() discarded the prose). *)
     let comments = C.comments_of_source source in
     let header, description =
       if literate then
         let prose = C.markdown_prose input in
         prose, (match prose with d :: _ -> Some d | [] -> None)
       else
         C.leading_block comments, Some (C.derive_description (List.map snd comments) ~fallback:("Generated from " ^ C.derive_name ~path:(first_positional_arg ())))
     in
     (match Compose_dsl.Wf_lower.lower
              ~name:(C.derive_name ~path:(first_positional_arg ()))
              ~comments ~header ?description prog with
      | exception Compose_dsl.Wf_ir.Emit_error (pos, msg) ->
        Printf.eprintf "emit error at %d:%d: %s\n" (tl pos.line) pos.col msg; exit 1
      | ir ->
        List.iter (fun id -> Printf.eprintf
          "warning: '%s' implies user interaction; workflows run autonomously and do not pause\n" id)
          (Compose_dsl.Wf_lower.interactive_idents ir);
        let js = Compose_dsl.Wf_emit.to_string ir in
        (match output_path with
         | Some p -> let oc = open_out p in output_string oc js; close_out oc
         | None -> print_string js))
   | Some other ->
     Printf.eprintf "unknown --emit target: %s (valid: workflow)\n" other; exit 1);
  exit 0
```

- [ ] **Step 5: Manual end-to-end verification**

Run:
```bash
dune exec ocaml-compose-dsl -- --emit workflow examples/brainstorming.arr
dune exec ocaml-compose-dsl -- --emit workflow examples/tdd-loop.arr   # expect: emit error (loop)
echo 'a ||| b' | dune exec ocaml-compose-dsl -- --emit workflow         # expect: emit error (|||)
dune exec ocaml-compose-dsl -- --emit                                   # expect: "missing value for --emit", exit 1
dune exec ocaml-compose-dsl -- examples/brainstorming.arr --output      # expect: "missing value for --output", exit 1
```
Expected: first prints a workflow script with `export const meta`; the loop/`|||` cases print `emit error …` and exit 1; the dangling-flag cases print `missing value …` and exit 1.

- [ ] **Step 6: Commit**

```bash
git add bin/main.ml test/test_integration.ml
git commit -m "feat: wire --emit workflow / -o into the CLI with value-flag parsing"
```

---

## Task 14: Golden + property tests

**Files:**
- Create fixtures under `test/golden/`: copy `examples/brainstorming.arr` → `test/golden/brainstorming.arr` and `examples/release.arr` → `test/golden/release.arr`, plus the generated `test/golden/brainstorming.js`, `test/golden/release.js`
- Modify: `test/dune` (add a `(deps …)` field), `test/test_properties.ml`, `test/test_emit_golden.ml` (new), register in `test/main.ml`

Keeping both the input `.arr` and expected `.js` under `test/golden/` avoids the cross-directory cwd problem: dune runs the test exe with cwd = `_build/default/test/`, so a `golden/` subdir resolves by the simple relative path `golden/<name>.<ext>` once declared as a dep.

- [ ] **Step 1: Add deps to `test/dune`**

```
(test
 (name main)
 (package ocaml-compose-dsl-lib)
 (deps (glob_files golden/*))
 (libraries compose_dsl alcotest qcheck-core qcheck-alcotest))
```

- [ ] **Step 2: Generate, inspect, and freeze the golden output**

Copy the two examples into `test/golden/*.arr`, then:
```bash
dune exec ocaml-compose-dsl -- --emit workflow test/golden/brainstorming.arr > test/golden/brainstorming.js
dune exec ocaml-compose-dsl -- --emit workflow test/golden/release.arr   > test/golden/release.js
```
**Read both** `.js` files and confirm they match the spec's worked-example shape (remember: `type_ann` on parenthesized Groups is dropped — verify against actual output, not a hand-prediction) before committing them as the source of truth.

- [ ] **Step 3: Write the golden test**

`test/test_emit_golden.ml` reads `golden/<name>.arr` and `golden/<name>.js` by relative path (cwd = `_build/default/test/`), emits from the `.arr`, and compares to the `.js` with `Alcotest.(check string)`. A helper reads a file into a string.

- [ ] **Step 4: Write property tests**

In `test/test_properties.ml`, add a QCheck generator for the supported-subset AST (Agent/Seq/Par/Fanout over named idents; optionally one `check`/`merge` with an upstream) and assert on the emitted string + IR:
- exactly one occurrence of `export const meta`;
- balanced `{}` and `()` and `[]` (simple counter scan);
- no `Date.now`, `Math.random`, `new Date` substrings;
- IR-level: the number of `Agent` nodes equals the number of top-level `const … = await agent(` bindings. Compute `count_agents` by walking the IR **in the test module** (no new emitter API); for the substring side, count only `await agent(` (which excludes the `() => agent(` thunks and skeptic calls). Assert structurally where possible.
- IR-level: every `Parallel` node yields an array-shaped binding. Assert structurally (count `Parallel` nodes by walking the IR in the test). For a substring cross-check, count the **`(await parallel([`** pattern — which matches a `Parallel` but **not** `Verify`'s `(await parallel(Array.from(` — and require it to equal the `Parallel`-node count, each immediately `.filter(Boolean)`-ed. Do **not** count bare `.filter(Boolean)` (Verify emits its own), which would double-count.

- [ ] **Step 5: Register + run** — add `; "Emit golden", Test_emit_golden.tests`; `dune test` — PASS.

- [ ] **Step 6: Commit**

```bash
git add test/golden/ test/test_emit_golden.ml test/test_properties.ml test/main.ml test/dune
git commit -m "test: golden + property tests for the workflow emitter"
```

---

## Task 15: Constraints

**Files:**
- Create: `constraints/007-emit-meta-single.md`, `constraints/008-emit-reject-unsupported.md`, `constraints/009-emit-no-nondeterminism.md`

- [ ] **Step 1: Write the three constraint docs**

Follow the Given/When/Then/Examples/Properties format of `constraints/004-epistemic-pairing.md`:
1. **007** — emitted output always has exactly one pure-literal `meta` with `name` + `description`.
2. **008** — an unsupported construct (`|||`, `loop`, non-`check` `?`, higher-order app, `check`/`merge` in a parallel branch, root `check`/`merge`, empty program) never produces output — always `Emit_error`.
3. **009** — output never contains `Date.now` / `Math.random` / `new Date`.

- [ ] **Step 2: Cross-check against existing tests** — confirm each constraint maps to a test added in Tasks 7/8/14.

- [ ] **Step 3: Commit**

```bash
git add constraints/007-emit-meta-single.md constraints/008-emit-reject-unsupported.md constraints/009-emit-no-nondeterminism.md
git commit -m "docs: add constraints 007-009 for the workflow emitter"
```

---

## Task 16: Documentation

**Files:**
- Modify: `README.md`, `CLAUDE.md`

- [ ] **Step 1: README — add an `--emit workflow` section**

Document the flag, the mapping table, the data-flow convention, context preservation, and the non-interactivity limitation. State explicitly that emitted files are CC-workflow scripts (not standalone JS). No EBNF change.

- [ ] **Step 2: CLAUDE.md updates**

- CLI Usage: add `--emit workflow` / `-o` examples.
- Project Structure: add `Wf_ir`, `Wf_lower`, `Wf_emit`, `Wf_context` to the module list.
- Future Ideas: record deferred items (`|||`/`loop` lowering, author `schema:`/real JSON Schema, js_of_ocaml distribution, configurable skeptic count, check/merge-in-parallel hoisting, phase body-grouping, full positional comment interleaving, multi-statement programs).

- [ ] **Step 3: Verify the EBNF still matches** — confirm no grammar changed (the emitter reuses existing named-arg + type-annotation syntax). Per CLAUDE.md's "After Any Implementation Change" workflow.

- [ ] **Step 4: Run the full suite** — `dune test` — Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: document --emit workflow in README and CLAUDE.md"
```

---

## Version bump (after all tasks)

Follow the CLAUDE.md "Version Bumps" workflow: bump `dune-project` version (e.g. 0.11.0 → 0.12.0), update CLAUDE.md / README / CHANGELOG, `dune build` (regenerates opam), `dune test`, commit. This is a feature addition, so a minor bump is appropriate.

## Notes for the implementer

- **Backtick escaping is handled, not punted:** prompts are interpolated into JS template literals, so `js_template_body` (Task 8) escapes `` \ ``, `` ` ``, and `${`. Add a focused test feeding a node whose `prompt:` arg contains a backtick and a `${`, asserting the output still has balanced delimiters. The Task 14 property generator may include these characters.
- **Emit is PPrint-document-based** (Tasks 8–10): each node returns `(PPrint.document, var, shape)`; `to_string` renders once via `PPrint.ToBuffer.pretty`. PPrint owns layout/indentation; the `js_string` / `js_template_body` helpers own escaping. This honors the spec's PPrint mandate while keeping escaping centralized.
- **Root rejection** for `check`/`merge` and the **branch-subtree** scan are the two correctness-critical lowering checks — do not skip their tests.
- **`Group` is preserved by the reducer**, so the emitter's `Group` handling is required (not defensive), and a `type_ann` on a Group is dropped — generate golden output, don't hand-predict it.
- Run `dune test` after every task; never commit with a failing suite.
