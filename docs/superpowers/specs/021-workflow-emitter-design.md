# Workflow Script Emitter (`--emit workflow`)

**Date:** 2026-05-31
**Status:** Draft

## Problem

The DSL is a planning language for human-LLM workflows: it parses, reduces, and
structurally checks Arrow pipelines, but it does not *run* anything. A pipeline
like `examples/brainstorming.arr` describes a real orchestration, yet a human
must translate it by hand to actually execute it.

Two recent technologies bracket this gap:

- **[λ-RLM](https://arxiv.org/abs/2603.20105)** ("The Y-Combinator for LLMs:
  Solving Long-Context Rot with λ-Calculus") replaces free-form recursive
  code-generation with a *typed functional runtime grounded in λ-calculus*,
  executing pre-verified combinators and "focusing neural inference only on
  bounded leaf subproblems," with formal termination and closed-form cost
  bounds. This DSL already borrowed λ-RLM's framing — `README.md` describes the
  epistemic `leaf` operator as a "bounded leaf sub-problem."

- **[Claude Code dynamic workflows](https://code.claude.com/docs/en/workflows)**
  are the *executable* counterpart: a JavaScript script that orchestrates
  subagents at scale, "moving the plan into code," with built-in quality
  patterns (adversarial cross-review, multi-angle drafting).

The DSL sits between them: more principled and static than a hand-written
workflow script (it is a typed free-arrow you *analyze*, not run), but currently
with no path to execution. That is the gap. So far the DSL describes and checks a
pipeline, and then the validated structure evaporates — a human re-translates it
by hand to run anything. The missing capability is **freezing a stable, checked
decision into executable code**, which is what codification has always been:
turning a settled decision into something mechanical so you stop re-deciding it.
A Claude Code workflow script is the natural place to freeze an Arrow pipeline.

This spec adds that path. It makes the DSL's existing λ-RLM-inspired framing
**executable** by lowering a checked pipeline to a Claude Code workflow script:
`leaf` becomes a single `agent()` call (the bounded neural subproblem), `check`
becomes an adversarial-verify fan, and `merge` becomes a barrier-plus-synthesis
step.

## Decision

Add an **opt-in backend pass** that transpiles a checked program to a Claude Code
dynamic-workflow JavaScript script. The OCaml CLI does not execute the workflow —
it emits a `.js` script that Claude Code runs. The core identity is preserved:
still no runtime in OCaml; the tool gains a compiler backend.

The emitted file is a **CC workflow script, not standalone JS**: it combines a
top-level `export const meta`, top-level `await`, and a top-level `return`, which
the workflow runtime wraps before evaluating. This format is intentional (it is
what Claude Code expects) and is why the test plan does not validate output with
`node --check` (see Testing).

```
parse >>> reduce >>> check >>> emit      -- when --emit workflow is passed
parse >>> reduce >>> check >>> print     -- default: AST output, unchanged
```

Emit runs **only after a clean check** (warnings are fine; errors abort). No
grammar change: node content comes from the DSL's existing named-argument and
type-annotation syntax.

Note: a `check?` written without a matching `|||` will trip the checker's
existing `?`-balance warning. That is acceptable — warnings do not block emit,
and the emitter consumes the `Question` wrapper when recognizing `check?`.

### Scope (v1)

**Supported:** named nodes (`Var`, `App` with named args), `>>>` (`Seq`), `***`
(`Par`), `&&&` (`Fanout`), `Group`, `()` (`Unit`), the epistemic operators
`gather` / `branch` / `leaf` / `merge` / `check` (incl. `check?`), and type
annotations as prompt hints.

**Deferred (rejected with a clear error — never silently dropped):** `|||`
(`Alt`), `loop` (`Loop`), `?` on any node other than `check`, higher-order
application (`App` with *positional* sub-expression arguments, e.g. `map(check)`),
a `***` / `&&&` branch whose subtree **contains** `check` / `merge` anywhere (not
just as the direct branch — they expand to multi-statement blocks that cannot be
a `parallel` thunk), a **root-position `check` / `merge`** (no upstream `prev` to
verify or fuse), and an **empty program** (a root `()` or a `Seq` that collapses
to nothing — there is no workflow to emit).

## Design

### Architecture — three modules

Mirrors the existing `Printer` separation (AST → string). The mapping logic is
separated from JavaScript syntax so the two can be tested independently.

| Module | Responsibility |
|---|---|
| `lib/wf_ir.ml` | The Workflow IR type (below) |
| `lib/wf_lower.ml` | `Ast.program -> Wf_ir.t` — the operator/epistemic mapping; raises `Emit_error` on unsupported constructs |
| `lib/wf_emit.ml` | `Wf_ir.t -> string` — the JavaScript pretty-printer, built on **PPrint** (owns escaping, quoting, indentation in one place) |

**Why a JS printer and not js_of_ocaml / a JS library.** js_of_ocaml is a
whole-program OCaml→JS *compiler*; its output bundles a runtime and is
machine-only, the opposite of the readable, rerunnable script a workflow is
meant to be. A survey of OCaml JS tooling (`flow_parser`, `js_of_ocaml-compiler`'s
internal `Javascript` AST, `ocaml-js`, `gen_js_api`, `melange`) found nothing
purpose-built and stable for *emitting* idiomatic JS source. The right-shaped
foundation is a pretty-printing combinator library; PPrint (mature, on opam) is
the standard choice and adds one small dependency to the current sedlex+menhir
set.

### The Workflow IR

```ocaml
type agent_spec = {
  label      : string;          (* node name → opts.label *)
  prompt     : string;          (* from prompt: arg; falls back to label + folded named args *)
  agent_type : string option;   (* from agent: arg → opts.agentType *)
  out_hint   : string option;   (* from type_ann.output → appended to prompt as "Return a <Out>." *)
  comment    : string option;   (* recovered source comment → // above the agent() call *)
  phase      : string option;   (* gather/branch/leaf set this → emitted as opts.phase on the agent() *)
}
(* No author-supplied schema field: DSL arg values are String/Ident/Number/List,
   not the structured object a CC `schema` requires. The only schema emitted is
   the internal VERDICT const used by Verify (check). See B3 in Future Ideas. *)

type wf_node =
  | Agent      of agent_spec        (* leaf / ordinary node → agent(); may carry a phase label *)
  | Seq        of wf_node list      (* >>> → sequential, threads `prev` *)
  | Parallel   of wf_node list      (* *** / &&& → parallel([...]) barrier *)
  | Synthesize of agent_spec        (* merge → fuses prev (array; or scalar = single-input) → one artifact *)
  | Verify     of { spec : agent_spec; skeptics : int }  (* check / check? → adversarial fan over prev *)

type t = {
  name        : string;          (* filename stem string; see "meta derivation" *)
  description : string;          (* first source comment / prose line; fallback generic *)
  header      : string list;     (* file-level context → top-of-file /* ... */ banner *)
  root        : wf_node;
}
```

**Flat, not nested — by design.** Epistemic operators are ordinary `Var`/`App`
idents that appear as *siblings* in a `Seq` chain, not as wrappers (e.g.
`gather >>> branch >>> leaf >>> merge` parses as nested `Seq`, but they are
peers). The IR reflects this: there is **no `Phase` wrapper node**. Instead:

- `gather` / `branch` / `leaf` lower to a plain `Agent` whose `phase` field is
  set to a capitalized title (`"Gather"`, `"Branch"`, `"Leaf"`). The title is
  emitted as `opts.phase` on that agent's `agent(…)` call — **not** a separate
  `phase("…")` statement, which would race inside `parallel` thunks (the CC API
  recommends `opts.phase` for exactly this reason). No subtree is grouped.
- `merge` lowers to `Synthesize`; `check` / `check?` lower to `Verify`. Both
  operate on `prev` (the upstream result) — there is no `target` subtree.
- `meta.phases` is the ordered, de-duplicated list of `phase` labels actually
  emitted, in first-seen order. If no epistemic idents appear, `meta.phases` is
  the single default `[{ title: 'Run' }]` and agents carry no `opts.phase`
  (belonging implicitly to that one phase).

**Data-flow shape is tracked during emission, not stored in the IR.** Whether
`prev` holds a scalar or an array depends on the *previous* sibling in a `Seq`:
**`Parallel` produces a (filtered) array; every other node — `Agent`,
`Synthesize`, and `Verify` — produces a scalar.** (`Verify` threads forward the
`passed` boolean, not the verdict array.) The `Seq` emitter therefore threads an
`is_array_prev` flag — set by `Parallel` alone — as it walks its children, so
each child generates correct consuming code (see Data flow). This keeps
`wf_node` a plain tree with no back-references.

### Operator and epistemic mapping

| DSL construct | IR node | Emitted JS |
|---|---|---|
| named node `n` / `n(args)` | `Agent` | `await agent(prompt, {label, agentType?})` |
| `a >>> b` | `Seq` | sequential `await` calls, threading `prev` |
| `a &&& b` (fanout) | `Parallel` | `parallel([…])`, **same** `prev` to every branch (exact fanout) |
| `a *** b` (parallel) | `Parallel` | `parallel([…])`, shared `prev` to each — split-input simplified to shared, documented |
| `leaf`, `gather`, `branch` | `Agent` (`phase` set) | a plain `agent()` carrying `opts.phase: '…'`; no subtree grouping |
| `merge` | `Synthesize` | barrier + synthesis: fuses the upstream `prev` array into one artifact |
| `check` / `check?` | `Verify {skeptics = 3}` | adversarial verify: `parallel` of 3 refuting skeptics over `prev` + majority vote (inline `VERDICT` schema) |
| `Group(e)` | transparent | unwrapped |
| `()` `Unit` | identity | dropped from a `Seq` |

The three Claude Code quality patterns land exactly: **fan-out** ← `&&&`/`***`
(`branch` marks intent), **barrier + synthesis** ← `merge`, **adversarial
verify** ← `check`.

`check` / `merge` are the only epistemic names that produce a special pattern;
`leaf` / `gather` / `branch` lower to a plain `Agent` whose `phase` label makes
the epistemic structure visible in the workflow progress view (see "Flat, not
nested" above for how phases are emitted).

Because `Verify` and `Synthesize` each expand to a multi-statement block (a
`parallel([...])` plus vote/fuse logic), they **cannot** be inlined as a
`() => …` thunk inside another `parallel`. Therefore a `***` / `&&&` branch whose
subtree *contains* a `check` / `merge` anywhere — not only as the direct branch
node, so `(a >>> check?) &&& b` is rejected too — is rejected in v1 (see Rejected
constructs). The lowerer detects this by scanning each branch subtree for a
`Verify` / `Synthesize` node. Hoisting them to named async helpers is a Future
Idea.

**Argument handling.** Named args populate `agent_spec`: `prompt:` → `prompt`
(overriding the name-derived default), `agent:` → `agent_type`. **`schema:` is
not supported in v1** — DSL arg values are `String`/`Ident`/`Number`/`List`, but
a CC `schema` must be a structured object; passing a string verbatim into
`opts.schema` is both type-incoherent (string ≠ object) and a JS-injection
boundary. A `schema:` arg is therefore folded into the prompt like any other
unmatched arg (it does not reach `opts.schema`). Any other named arg (`glob:`,
`n:`, `style:`, `require: [...]`) is likewise folded into the prompt as a
"Parameters:" line. Schemas also cannot be synthesized from type annotations,
since `:: In -> Out` carries only type *names*, not field definitions — so
`out_hint` becomes a prompt line, not a validated schema. (Author-supplied
schemas are deferred until the DSL grows object syntax; see Future Ideas.)

Arg `value`s render to plain text in the `Parameters:` line by kind: `String s`
→ `s` (unquoted), `Ident i` → `i`, `Number n` → `n` (unit suffix preserved, e.g.
`500ms`), `List vs` → `[v1, v2, …]` rendered element-wise. So
`gate(require: [pass, pass])` → `Parameters: require=[pass, pass]` and
`build(profile: static)` → `Parameters: profile=static`. The rendered text is
prompt content, escaped by the printer like any other string.

### Data flow (point-free → threaded)

Arrow is point-free, so the emitter adopts a threading convention rather than
requiring explicit data flow in the surface syntax. The emitter contract is
`emit_node ~prev node`, where `prev : (expr * shape) option` carries both the JS
expression for this node's input **and** its shape (`Scalar | Array`), and is
`None` at the program root. Carrying the shape (not just the expression) is what
lets a branch root correctly consume an array handed down from an upstream
`Parallel` (the only node that yields an array) — `is_array_prev` is this shape:

- Only the **program root** has no upstream (`prev = None`), so it omits the
  `## Input` section. This is *not* a property of `Seq` position in general — a
  `Seq` that sits as a branch of a `Parallel` receives the parallel's shared
  `prev` at its head. So in `x >>> ((a >>> b) &&& c)`, node `a` (the head of the
  branch `a >>> b`) consumes `x`; it does **not** omit `## Input`. The emitter
  passes the branch input down to each branch root.
- Each non-root `Agent` receives its `prev` interpolated as a prompt section:
  `` `<prompt>\n\n## Input\n${prev}` `` when `prev` is a scalar, or
  `` `<prompt>\n\n## Input\n${JSON.stringify(prev)}` `` when `prev` is an array.
- `Parallel` branches all receive the same `prev` as their branch input; the
  emitter binds the parallel's result to a fresh `const`, immediately
  `.filter(Boolean)`-ed (a `parallel()` thunk that errors/skips resolves to
  `null`). The filtered **array** becomes the next node's `prev`, and
  `is_array_prev` is set.
- `Synthesize` (`merge`) **normally** consumes an array `prev`. When the
  preceding sibling was a `Parallel` (`is_array_prev` true — `Verify` does *not*
  set it, it yields a scalar boolean), it fuses the array
  (`${prev.map((r,i) => …).join('\n')}`). When `prev` is a scalar
  (single-input synthesis — no preceding parallel), it lowers to a plain
  synthesis `agent()` over the scalar — well-defined, not an error.
- `Verify` (`check`) counts skeptic verdicts with `.filter(Boolean)` before the
  majority test, refuting `prev`.
- **`check` / `merge` require a non-`None` `prev`.** Both operate on an upstream
  result, so a `check` / `merge` in *root position* (`prev = None` — a standalone
  `merge` program, or the head of the top-level pipeline) has nothing to verify
  or fuse and is rejected with `Emit_error`. Only `check` / `merge` with an
  upstream node are valid.

The `is_array_prev` flag is computed structurally by the `Seq` emitter as it
walks children left to right (**only `Parallel` sets it** — `Verify` and
`Synthesize` produce scalars); it is never guessed at runtime.

Worked example — `examples/brainstorming.arr`, which is
`(read_files *** git_log *** read_docs) >>> summarize >>> ask_questions >>>
propose >>> present_design >>> write_spec` and contains **no** epistemic
operators, so `meta.phases` is the single default `Run` and no `phase()`
statements or `opts.phase` are emitted. The leading `Parallel` is the program
root, so it omits `## Input`; `summarize` consumes the filtered array; later
nodes thread a scalar `prev`. (Binding names below are shown unsuffixed for
readability; the real emitter uses fresh sanitized identifiers like
`summarize_4` so hyphenated/Unicode/duplicate labels can't break the JS.)

```js
export const meta = {
  name: 'brainstorming',
  description: 'structured exploration before implementation',
  phases: [{ title: 'Run' }],
}

const sources = (await parallel([
  () => agent(`read_files\n\nParameters: glob=lib/**/*.ml`, { label: 'read_files' }),
  () => agent(`git_log\n\nParameters: n=20`, { label: 'git_log' }),
  () => agent(`read_docs\n\nParameters: path=CLAUDE.md`, { label: 'read_docs' }),
])).filter(Boolean)                                     // is_array_prev = true
const summarize = await agent(`summarize\n\n## Input\n${JSON.stringify(sources)}`, { label: 'summarize' })
const ask_questions = await agent(`ask_questions\n\nParameters: style=one_at_a_time\n\n## Input\n${summarize}`, { label: 'ask_questions' })
const propose = await agent(`propose\n\nParameters: count=3\n\n## Input\n${ask_questions}`, { label: 'propose' })
const present_design = await agent(`present_design\n\n## Input\n${propose}`, { label: 'present_design' })
const write_spec = await agent(`write_spec\n\n## Input\n${present_design}`, { label: 'write_spec' })
return write_spec
```

(This pipeline trips the interactive-ident advisory on `ask_questions`,
`propose`, and `present_design` — see the non-interactivity limitation. That
warning is expected, not a bug.)

### Context preservation

The emitted file must stay self-documenting. Because the parser drops comments
(a known bug — `Lexer.token` skips `COMMENT` tokens), the emitter recovers
context from a **different channel**, never from the AST:

- **Comments** via `Lexer.tokenize` (the batch tokenizer returns `COMMENT`
  tokens with positions).
- **Literate prose** via `Markdown.extract` and the offset table.

Mapping:

- **File header** → top-of-file `/* … */` banner: the leading `--` comment block
  (standard mode), or the Markdown prose around the `arrow` blocks (literate
  mode).
- **Node comment** → a `--` comment on or adjacent to a node's source line,
  matched by the node's `expr.loc`, emitted as a `//` line above that node's
  `agent()` call.
- **`meta` derivation** → `name` and `description` are both emitted as JS
  **string literals** (the `meta` block must be a pure literal), so `name` need
  not be a JS identifier — any string is valid. `name` = the input filename with
  directory and extension stripped (e.g. `examples/brainstorming.arr` →
  `brainstorming`); if that is empty (stdin input, or a dotfile), fallback
  `workflow`. `description` = the first recovered comment / prose line; fallback
  `"Generated from <file>"`. String contents are escaped by the printer.

### Limitation — workflows are non-interactive

Claude Code workflows run autonomously with no mid-run user input. DSL pipelines
*can* describe interactive steps (`ask_questions`, `present_design`, human
gates). A transpiled interactive pipeline will run but will not pause where the
DSL implies a human.

The emitter is honest about this rather than pretending to fix it:

1. The generated file header carries a one-line note: *"Generated workflow runs
   autonomously; steps that imply human input do not pause."*
2. This limitation is documented in the README `--emit workflow` section.
3. An **advisory stderr warning** lists nodes whose names match a small,
   documented interactive-ident set (`ask_questions`, `present_design`,
   `propose`, `review`, `ask`, `confirm`, `approve`, `feedback`). The warning is
   advisory only — emission still succeeds (exit 0). Its purpose: when this
   emitter is invoked in the future, the operator (or a future agent reading the
   warning) knows that interactive instructions do not belong in an emitted
   workflow and can self-correct.

### Error handling

- New `Emit_error of Ast.pos * string` (a point error, mirroring `Reduce_error`'s
  `pos * string` shape), caught in `bin/main.ml` exactly like the existing
  `Parse_error` / `Reduce_error` → message to stderr, exit 1.
- **Two-phase, never partial:** `wf_lower` fully validates first; only on success
  does `wf_emit` run. A rejected construct aborts *before* any JS is written.
- Rejections (`|||`, `loop`, non-`check` `?`, higher-order positional `App`, a
  `***`/`&&&` branch whose subtree contains `check`/`merge`, a root-position
  `check`/`merge`, and an empty program) → `Emit_error` with loc + the construct
  name + "not supported by `--emit workflow` (v1)". The empty-program error uses
  the program's location (or a synthetic top-of-file loc for empty stdin).
- `--emit <unknown-target>` → error listing valid targets (`workflow`).

### CLI surface

Additive to `bin/main.ml`:

```
--emit <target>      target ∈ { workflow }   (extensible enum; unknown → error)
-o, --output <file>  write JS to file        (default: stdout)
        (composes with the existing --literate flag)
```

No `--name` / `--description` flags — both are derived from the source.

**This is not purely additive.** `bin/main.ml` currently parses only boolean
flags (`argv_has`) plus `first_positional_arg` / `first_unknown_flag`. `--emit`
and `-o`/`--output` each **consume a following value token**, which the current
helpers cannot express — `workflow` and the output path would be misread as the
positional input file, and the new flags would trip `first_unknown_flag` and
exit 1. The implementation must add a small value-flag pass that (a) recognizes
`--emit`, `-o`, `--output`, (b) consumes their value token, (c) excludes those
value tokens from positional-arg and unknown-flag detection. The spec calls this
out so the implementer sizes it correctly.

## Test Cases

### Lowering (`test/test_wf_lower.ml`, alcotest)

| Input | Expected IR / behavior |
|---|---|
| `a >>> b` | `Seq [Agent a; Agent b]` |
| `a &&& b` | `Parallel [Agent a; Agent b]` |
| `a *** b` | `Parallel [Agent a; Agent b]` |
| `a >>> check?` | `Seq [Agent a; Verify {skeptics = 3}]` |
| `merge` (root) | raises `Emit_error` ("check/merge needs an upstream …") |
| `check?` (root) | raises `Emit_error` ("check/merge needs an upstream …") |
| `n(prompt: "do x", agent: "Explore")` | `Agent` with `prompt="do x"`, `agent_type=Some "Explore"` |
| `a ||| b` | raises `Emit_error` ("`|||` not supported …") |
| `loop(x)` | raises `Emit_error` ("`loop` not supported …") |
| `x?` (x ≠ check) | raises `Emit_error` ("`?` only on `check` …") |
| `map(check)` | raises `Emit_error` ("higher-order application …") |
| `a &&& check?` | raises `Emit_error` ("check/merge inside `***`/`&&&` …") |
| `(a >>> check?) &&& b` | raises `Emit_error` (branch subtree *contains* `check`) |
| `()` (root unit / empty program) | raises `Emit_error` ("empty pipeline …") |
| `a >>> merge` (scalar prev) | `Seq [Agent a; Synthesize …]`, emits scalar synthesis (not an error) |
| `(a *** b) >>> merge` | `Synthesize` consumes the filtered array |

### Printer / golden (`test/golden/*.js`)

Transpile each supported `examples/*.arr` (`brainstorming`, `release`; not
`tdd-loop` — it uses `loop`) and diff against committed golden output.

### Syntactic validity — *not* `node --check`

A CC workflow script is a **bespoke module format**: it combines top-level
`export const meta = …`, top-level `await`, and a top-level `return` (how a
workflow surfaces its result). That combination is not valid standalone ESM —
modules forbid top-level `return` — so `node --check` would *reject* correct
emitted output. The runtime wraps the body before evaluating it; reproducing that
undocumented wrapper in a test would couple us to an internal detail.

Therefore there is **no `node --check` gate**. Syntactic confidence comes from:
the PPrint printer (which owns brace/quote/escape correctness in one place), the
golden snapshots, and the balanced-delimiters property test below. The emitted
`.js` is documented as a Claude Code workflow script, not standalone runnable JS.

### Property (QCheck, `test/test_properties.ml`)

Generate random ASTs from the supported subset and assert invariants:

- exactly one `export const meta` in the output;
- balanced braces / parentheses (printer well-formed);
- every `Agent` IR node → exactly one `agent(` call (asserted at the IR/emitter
  level — `Verify` and `Synthesize` emit their own `agent(` calls, so a raw
  substring count would not equal the `Agent`-node count);
- the output contains no `Date.now`, `Math.random`, or `new Date` (resume
  safety — these are forbidden in workflow scripts);
- **at the IR level**, every node whose `prev` is array-typed (the one
  immediately after a `Parallel` — *not* `Verify`, which yields a scalar boolean)
  consumes a `.filter(Boolean)`-ed binding — asserted on the IR/emitter model
  rather than by regex on the emitted text, which would false-match `Verify`'s
  internal `parallel`.

### Constraints (`constraints/*.md`)

Three new Given/When/Then invariants feeding the project's constraint→test
generators:

1. Emitted output always has exactly one pure-literal `meta` with `name` and
   `description`.
2. An unsupported construct never produces output — always `Emit_error`.
3. Output never contains `Date.now` / `Math.random` / `new Date`.

## Other File Changes

### Build config (`lib/dune`, `dune-project`)

Add `pprint` to `lib/dune`'s `(libraries …)`. Because opam files are generated
via `generate_opam_files`, the dependency must **also** be declared in
`dune-project`'s package `depends` stanza, then `dune build` re-run to
regenerate the `.opam` file.

### README.md

Add a `--emit workflow` section: the mapping table, the data-flow convention,
context preservation, and the non-interactivity limitation. No EBNF change — the
emitter reuses existing named-arg and type-annotation grammar.

### CLAUDE.md

- CLI Usage: document `--emit workflow` / `-o`.
- Project Structure: add `wf_ir`, `wf_lower`, `wf_emit` to the module list.
- Future Ideas: record the deferred items (below).

## What This Spec Does Not Cover (deferred → Future Ideas)

- **`|||` alternation lowering** — needs a chosen runtime semantics (fallback vs
  vote vs race).
- **`loop` lowering** — needs a bound/termination model (ties into the existing
  cost-annotation Future Idea and λ-RLM's closed-form cost bounds).
- **Author-supplied `schema:` and real JSON Schema generation** — v1 drops
  `schema:` *semantics*: the arg never reaches `opts.schema` (it is folded into
  the prompt like any other unmatched arg). DSL values are
  `String`/`Ident`/`Number`/`List`, not the structured object `opts.schema`
  needs; raw passthrough would be type-incoherent and a JS-injection risk. Supporting it needs either DSL object-literal syntax or a
  registry of `Ident`-named shipped schema consts; real per-node JSON Schema
  additionally needs field-level type definitions the DSL does not express.
- **js_of_ocaml distribution** — compiling the whole DSL toolchain to JS so the
  parser/checker/emitter runs in a browser or as an npm package. Orthogonal to
  this spec.
- **Configurable skeptic count** for `check` (constant `3` in v1).
- **`check` / `merge` inside `***` / `&&&`** — hoist the multi-statement
  `Verify` / `Synthesize` expansion into a named async helper so it can be used
  as a `parallel` thunk. Rejected with an error in v1.
- **Phase body-grouping** — v1 tags each epistemic node with `opts.phase`; a
  richer model could group following siblings into a phase body (`branch … merge`
  as one phase region).
- **Full positional comment interleaving** — v1 attaches comments at the file
  header and per-node level only, not at every source position.
- **Multi-statement programs** — a program with `;`-separated statements (e.g.
  `checker.arr`) is rejected in v1; the emitter handles a single top-level
  pipeline. (A multi-statement program could map to several phases or several
  workflows.)
- **`check` arguments** — v1's `Verify` uses a fixed skeptic instruction and
  ignores `check(prompt: …)` / other args on the `check` node; a future version
  could let them shape the skeptic prompt.
- **Version bump** — follows the CLAUDE.md Version Bumps workflow after
  implementation.
- **Compose skill update** — the `/compose` skill lives in a separate repo and
  is updated after the binary is released.

## References

- λ-RLM: <https://arxiv.org/abs/2603.20105>
- Claude Code dynamic workflows: <https://code.claude.com/docs/en/workflows>
- Claude Code subagents: <https://code.claude.com/docs/en/sub-agents>
