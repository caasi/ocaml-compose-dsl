# ocaml-compose-dsl

[![CI](https://github.com/caasi/ocaml-compose-dsl/actions/workflows/ci.yml/badge.svg)](https://github.com/caasi/ocaml-compose-dsl/actions/workflows/ci.yml)

A structural checker — and Claude Code workflow transpiler — for an Arrow-style DSL designed for AI agent workflow composition.

## What Is This?

AI agents compose tools through natural language reasoning, but this approach is unreproducible, hard to review, and disappears when the conversation ends. This DSL gives agents (and humans) a shared, structured language to describe multi-step workflows — **without requiring a runtime or interpreter**. The agent itself expands the DSL into concrete tool calls.

The DSL uses Arrow combinators because they sit at the sweet spot between shell pipes (too linear) and monads (too opaque): pipeline structure is fully visible before execution.

A checked pipeline can also be **frozen into executable code**: `--emit workflow` transpiles it into a [Claude Code dynamic-workflow](https://code.claude.com/docs/en/workflows) JavaScript script (the OCaml tool emits the script; Claude Code runs it). See [Workflow Emitter](#workflow-emitter---emit-workflow).

## Grammar (EBNF)

```ebnf
program     = { ";" } , [ stmt , { ";" , { ";" } , stmt } , { ";" } ] ;

stmt        = let_expr | pipeline ;

let_expr    = "let" , ident , "=" , seq_expr , "in" , stmt ;

lambda  = "\" , ident , { "," , ident } , "->" , seq_expr ;
                                                    (* body is seq_expr, not stmt;
                                                       let_expr is only valid at stmt level
                                                       or inside grouping parens *)

pipeline = seq_expr ;

seq_expr = alt_expr , ">>>" , seq_expr              (* sequential — infixr 1 *)
         | lambda
         | alt_expr ;
alt_expr = par_expr , "|||" , alt_expr              (* branch — infixr 2 *)
         | par_expr ;
par_expr    = typed_term , ( "***" | "&&&" ) , par_expr (* parallel / fanout — infixr 3 *)
            | typed_term ;

typed_term  = term , [ "::" , type_expr ] ;

type_expr   = type_name , "->" , type_name ;
type_name   = ident | "(" , ")" ;

term     = ident , [ "(" , [ call_args ] , ")" ] , [ "?" ]
                                                    (* ident with optional args and question *)
         | string , [ "?" ]                        (* string literal, optionally question;
                                                      AST represents both as Question(expr) *)
         | "(" , ")" , [ "?" ]                     (* unit value, with optional question *)
         | "loop" , "(" , seq_expr , ")"            (* feedback loop *)
         | "(" , stmt , ")"                        (* grouping — allows let bindings
                                                      but not semicolons inside parens *)
         ;

call_args = call_arg , { "," , call_arg } ;
                                                    (* empty call_args in f() produces
                                                       [Positional Unit], not an empty list;
                                                       zero-arg application is eliminated *)
call_arg  = arg_key , ":" , value                   (* Named — per-arg disambiguation via key ":" *)
          | seq_expr                                (* Positional — any expression *)
          ;
arg_key   = ident | "in" ;                          (* reserved words allowed as named arg keys *)

value    = string
         | number
         | ident
         | "[" , [ value , { "," , value } ] , "]"
         ;

ident       = ident_start , { ident_char } - reserved ;
                (* reserved words are excluded at the lexer level *)
reserved    = "let" | "loop" | "in" ;
ident_start = ? any valid UTF-8 codepoint that is not an ASCII digit,
                not ASCII whitespace, and not one of ( ) [ ] : , > * | & - " .
                ! # $ % ^ + = { } < ; ' ` ~ / ? @ \ ? ;
ident_char  = ? any valid UTF-8 codepoint that is not ASCII whitespace,
                and not one of ( ) [ ] : , > * | & " .
                ! # $ % ^ + = { } < ; ' ` ~ / ? @ \ ? ;
                (* note: "-" is a valid ident_char, but the lexer stops
                   before "->" so that the arrow token is recognized
                   even without surrounding whitespace *)

string   = '"' , { ? any valid UTF-8 codepoint except '"' ? } , '"' ;

number     = [ "-" ] , digit , { digit } , [ "." , digit , { digit } ] , [ ident_start , { ident_char } ] ;

comment  = "--" , { any char - newline } ;
```

All operators are right-associative (matching Haskell Arrow fixity).

## Arrow Semantics

The operators follow Arrow combinator semantics. The DSL has no type checker —
the `::` type annotations and the types in this table describe the data flow for the agent (and human) reading the pipeline.

| Operator | Name           | Type                                          |
|----------|----------------|-----------------------------------------------|
| `>>>`    | compose        | `Arrow a b → Arrow b c → Arrow a c`           |
| `***`    | product        | `Arrow a b → Arrow c d → Arrow (a,c) (b,d)`   |
| `&&&`    | fanout         | `Arrow a b → Arrow a c → Arrow a (b,c)`       |
| <code>&#124;&#124;&#124;</code> | fanin / branch | `Arrow a c → Arrow b c → Arrow (Either a b) c` |
| `loop`   | feedback       | `Arrow (a,s) (b,s) → Arrow a b`               |
| `?`     | question       | `Arrow a (Either a a)`                        |

`***` is right-associative: `a *** b *** c` types as `(A, (B, C))`.
Comments can annotate the concrete types when the structure isn't obvious from node names.

## Type Annotations

Terms can carry optional type annotations using `::`:

```
fetch(url: "https://example.com") :: URL -> HTML
  >>> parse :: HTML -> Data
  >>> filter(condition: "age > 18") :: Data -> Data
  >>> format(as: report) :: Data -> Report
```

Annotations are optional — a pipeline can freely mix annotated and unannotated nodes. Type identifiers follow the same `ident` rule as node names, including Unicode support.

Type annotations are **documentation, not enforcement**. They are parsed into the AST but not checked. The DSL has no type checker — annotations describe the intended data flow for the agent (and human) reading the pipeline.

## Example

```
read(source: "data.csv")
  >>> parse(format: csv)
  >>> filter(condition: "age > 18")
  >>> (count *** collect(fields: [email]))
  >>> format(as: report)
```

```
loop (
  generate(artifact: code, from: spec)
    >>> verify(method: test_suite)
    >>> evaluate(criteria: all_pass)
)
```

```
(lint &&& test)
  >>> gate(require: [pass, pass])
  >>> (build_linux(profile: static) *** build_macos(profile: release))
  >>> upload(tag: "v0.1.0")
```

```
resize(width: 1920, height: 1080)
  >>> compress(quality: 85)
  >>> dose(amount: 100mg)       -- numeric literals with unit suffixes
  >>> adjust(offset: -3.14)     -- negative floats supported
```

```
読み込み(ソース: "データ.csv")
  >>> フィルタ(条件: "年齢 > 18")
  >>> 出力
```

```
"earth is not flat"?
  >>> (believe ||| doubt)
```

```
loop(
  generate >>> verify >>> "all tests pass"?
  >>> (continue ||| fix_and_retry)
)
```

```
planning :: Doc -> Commit
  >>> commit(branch: main)

implementation :: Code -> Commit
  >>> git_branch(pattern: "feature/*") :: Code -> Branch
  >>> commit :: Branch -> Commit
```

```
let greet = \name -> hello(to: name) >>> respond in
greet(alice) >>> greet(bob)
```

```
let review = \trigger, fix ->
  loop(trigger >>> (pass ||| fix))
in
let phase1 = gather >>> review(check?, rework) in
let phase2 = build >>> review(test?, fix) in
phase1 >>> phase2
```

```
let v = some_pipeline in
push(remote: origin, v)
```

Named and positional arguments can be freely mixed. Named arguments (`key: value`) provide static configuration; positional arguments pass pipeline expressions.

Lambdas and let bindings are reduced to pure Arrow pipelines before structural checking. They provide abstraction without adding runtime semantics.

Identifiers and unit suffixes accept any non-ASCII UTF-8 codepoint, so the DSL works naturally with non-Latin scripts. Error positions report codepoint-level columns, not byte offsets.

## Epistemic Conventions

Five identifier names serve as **epistemic operators** —
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

The checker currently lints two of these conventions:

- `branch` without `merge` in the same statement
- `leaf` without `check` in the same statement (suggestion)

These operators are not keywords — they can be shadowed by `let` bindings or
used as regular nodes. The checker matches them by name only.

## Usage

```sh
# From file
ocaml-compose-dsl pipeline.arr

# From stdin
echo 'a >>> b' | ocaml-compose-dsl

# Check arrow blocks in a Markdown file
ocaml-compose-dsl --literate README.md

# Help and version
ocaml-compose-dsl --help
ocaml-compose-dsl --version
```

Exits `0` with AST output in a constructor-style format (e.g. `TypeAnn(Var("name"), "Input", "Output")` for annotated terms) on valid input, `1` with error messages on lex/parse/reduction errors. Well-formedness warnings (e.g. `?` without matching `|||`) are printed to stderr without affecting the exit code.

## Literate Arrow Documents

Arrow DSL is designed to work inside natural language documents. Use fenced code blocks with the `arrow` (or `arr`) language tag to embed workflow definitions and lightweight type constraints alongside prose — no special file extension or evaluator required. Any Markdown document can be a literate Arrow document. Both LF and CRLF line endings are supported.

````markdown
## Deployment

Build artifacts must pass CI before release.

```arrow
build :: Source -> Artifact
  >>> test :: Artifact -> Verified
  >>> deploy(env: production) :: Verified -> Released
```

The `:: Source -> Artifact` annotations serve as simple type
constraints that document what each step expects and produces,
making the workflow reviewable by both humans and agents.
````

Convention: `.arr` for standalone DSL files. For literate documents, just use regular `.md` — the `arrow` code blocks speak for themselves.

## Workflow Emitter (`--emit workflow`)

The `--emit workflow` flag transpiles a checked Arrow pipeline into a
[Claude Code dynamic-workflow](https://code.claude.com/docs/en/workflows)
JavaScript script. OCaml never executes the script — it emits a `.js` file that
Claude Code runs.

```sh
# Emit to stdout
ocaml-compose-dsl --emit workflow pipeline.arr

# Emit to a file
ocaml-compose-dsl --emit workflow pipeline.arr -o pipeline.js

# Combine with literate mode
ocaml-compose-dsl --literate --emit workflow README.md -o workflow.js
```

The emit pass runs **only after a clean checker pass** (warnings are fine; parse
or reduction errors abort before emitting).

**Important:** Emitted files are **Claude Code workflow scripts**, not standalone
JavaScript modules. They use `export const meta`, top-level `await`, and
top-level `return` — a combination the workflow runtime wraps before evaluating.
Running them with `node` directly will fail. No EBNF change: the emitter reuses
the DSL's existing named-argument and type-annotation grammar.

### Operator Mapping

| DSL construct | IR node | Emitted JS |
|---|---|---|
| named node `n` / `n(named-args)` | `Agent` | `const n = await agent(prompt, { label: '…', agentType?: '…', phase?: '…' })` |
| `a >>> b` | `Seq` | sequential `await` calls, threading `prev` as `## Input` |
| `a &&& b` (fanout) | `Parallel` | `parallel([…]).filter(Boolean)` — same `prev` to every branch |
| `a *** b` (parallel) | `Parallel` | `parallel([…]).filter(Boolean)` — shared `prev` (split-input simplified to shared) |
| `leaf` / `gather` / `branch` | `Agent` with `phase` set | plain `agent()` call carrying `opts.phase: '…'` |
| `merge` | `Synthesize` | barrier + synthesis agent fusing upstream `prev` array into one artifact |
| `check` / `check?` | `Verify` (3 skeptics) | `parallel` fan of 3 adversarial skeptics over `prev`, majority vote |
| `Group(e)` (parenthesized) | transparent | unwrapped; type annotation on group is dropped |
| `()` `Unit` in a `Seq` | identity | dropped from the chain |

### Data-Flow Convention

The emitter is point-free, so it threads a `prev` binding through the pipeline:

- The **program root** has no upstream (`prev = None`) and omits the `## Input`
  section in its prompt.
- Each **non-root node** receives `prev` interpolated into its prompt as
  `` `…\n\n## Input\n${prev}` `` (scalar) or
  `` `…\n\n## Input\n${JSON.stringify(prev)}` `` (array from a `Parallel`).
- **`Parallel`** (`&&&` / `***`) produces a `.filter(Boolean)` array binding;
  every branch receives the same `prev` as its branch input.
- **`Synthesize`** (`merge`) fuses the array from an upstream `Parallel` with
  `.map((r,i) => ...)`.
- **`Verify`** (`check`) fans out 3 adversarial skeptics over `prev` and
  threads forward a `passed` boolean (scalar), not the verdict array.

### Context Preservation

- **File header** — the leading `--` comment block (standard mode) or the
  Markdown prose before the first `arrow` fence (literate mode) becomes a
  top-of-file `//` comment in the emitted JS.
- **Node comments** — a `--` comment on the same line as a node (inline) or on
  the immediately preceding line is emitted as a `//` line above that node's
  `agent()` call.
- **`meta` derivation** — `name` = the input filename stem (e.g.
  `brainstorming.arr` → `'brainstorming'`; stdin → `'workflow'`).
  `description` = the first recovered comment / prose line; fallback
  `'Generated from <file>'`.
- **`meta.phases`** — the ordered, de-duplicated list of `phase` labels from
  epistemic nodes (`gather`, `branch`, `leaf`). Default: `[{ title: 'Run' }]`.

### Non-Interactivity Limitation

Claude Code workflows run **autonomously** with no mid-run user input. DSL
pipelines can describe interactive steps (`ask_questions`, `present_design`,
etc.); a transpiled interactive pipeline will run but will not pause where the
DSL implies a human.

The emitter is honest about this: it prints an **advisory stderr warning** for
nodes whose names match a documented interactive-ident set (`ask_questions`,
`present_design`, `propose`, `review`, `ask`, `confirm`, `approve`, `feedback`).
Emission still succeeds (exit 0).

### Supported and Rejected Constructs

**Supported:** `Var`, `App` with named args, `>>>`, `***`, `&&&`, `Group`,
`Unit`, `gather`, `branch`, `leaf`, `merge`, `check` (incl. `check?`), type
annotations.

**Rejected with a clear error (never silently dropped):** `|||`, `loop`, `?` on
any node other than `check`, positional sub-expression arguments
(`map(check)`), a `***`/`&&&` branch whose subtree contains `check`/`merge`
anywhere, root-position `check`/`merge`, empty program, multi-statement program.

## Install

Pre-built binaries are available on the [Releases](https://github.com/caasi/ocaml-compose-dsl/releases) page for:

- Linux x86_64 (statically linked)
- macOS x86_64
- macOS arm64

## Build

Requires OCaml >= 5.1 and Dune >= 3.0.

```sh
dune build
dune test
```

## License

MIT
