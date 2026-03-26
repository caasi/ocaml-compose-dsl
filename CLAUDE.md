# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository. It is written as a **literate Arrow document** — prose mixed with `arrow` code blocks that describe workflows using the Arrow-style DSL defined in this project.

> **Skill:** This project ships a `/compose` skill for Claude Code. Use it to validate DSL syntax, plan tool composition, or write pipelines. If the skill is not installed, you can check the [README](./README.md) for grammar and semantics, or search the internet for `ocaml-compose-dsl` / `compose skill claude code`.
>
> **Binary:** `ocaml-compose-dsl` (or `dune exec ocaml-compose-dsl`) can validate any `arrow` code block — pipe a snippet through it to check syntax.

## Build Commands

- `dune build` — build everything
- `dune exec ocaml-compose-dsl` — run the main executable
- `dune test` — run all tests (alcotest)
- `dune exec test/test_compose_dsl.exe -- test <Suite> <N>` — run a single test by suite name and index
- `dune clean` — remove build artifacts

## Project Structure

Two opam packages defined in `dune-project` (opam files are auto-generated via `generate_opam_files`):

- **ocaml-compose-dsl** — the CLI executable (`bin/main.ml`), depends on the library
- **ocaml-compose-dsl-lib** — the library (`lib/`), exposed as `compose_dsl`

Library modules form a pipeline themselves:

```arrow
let lex = Lexer :: String -> Token
let parse = Parser :: Token -> Ast       -- parse_program entry point
let reduce = Reducer :: Ast -> Ast       -- desugar let, beta reduce lambda
let check = Checker :: Ast -> Result

lex >>> parse >>> reduce >>> check
```

- `Ast` — ADT for DSL expressions: Var (variable reference, bound or free), StringLit (string literal as expression), Seq (`>>>`), Par (`***`), Fanout (`&&&`), Alt (`|||`), Loop, Group, Question (`?`), Lambda (`\x -> body`), App (unified application with `call_arg list` — mixed named/positional), Let (`let x = expr`). Lambda and Let are reduced away by the Reducer. Free Var and App with free Var callee survive reduction. Values: String, Ident, Number (with optional unit suffix, e.g. `100mg`), List. Question takes an `expr` directly (parser allows Var, StringLit, or App). Expressions carry optional `type_ann` (`:: Ident -> Ident`) for documentation.
- `Lexer` — tokenizer, raises `Lex_error` on invalid input. Supports Unicode identifiers and unit suffixes (non-ASCII bytes accepted). Column positions track codepoints, not bytes (via `String.get_utf_8_uchar`). Tokens include `DOUBLE_COLON` (`::`) and `ARROW` (`->`); `read_ident` uses lookahead to stop before `->` so that `A->B` tokenizes correctly despite `-` being a valid identifier character.
- `Parser` — recursive descent parser, raises `Parse_error`. Single entry point: `parse_program` (handles both `let` bindings and plain expressions). Per-arg disambiguation: `IDENT ":"` → Named arg, otherwise → Positional arg.
- `Reducer` — desugars `Let` into `App(Lambda)`, performs beta reduction (substituting args into lambda bodies). Free `Var` and `App` with free `Var` callee survive reduction. Raises `Reduce_error` on arity mismatch, named args on lambda, non-function application, or unreduced nodes. Alpha-renaming counter is local to each `reduce` call (deterministic, thread-safe).
- `Checker` — structural validation and well-formedness warnings. Returns `{ warnings }`. Warnings: e.g. `?` without matching `|||`. Uses `normalize` (graph reduction) to strip `Group` wrappers before balance checking. Independently checks each Positional arg sub-expression in `App`.
- `Printer` — AST to constructor-style format string (for agent verification). Type annotations are wrapped as `TypeAnn(expr, "input", "output")`.

## CLI Usage

Reads from file argument or stdin. Exits 0 with AST output (constructor-style format) on success (warnings, if any, go to stderr), exits 1 with error messages on failure.

```
echo 'a >>> b' | dune exec ocaml-compose-dsl
dune exec ocaml-compose-dsl -- pipeline.arr
```

## After Any Implementation Change

Every code change should follow this workflow:

```arrow
let verify = verify_ebnf :: Code -> Spec   -- check README.md EBNF still matches parser/lexer
let test =
  update_tests :: Spec -> Test             -- update or add tests in test/test_compose_dsl.ml
  >>> dune_test :: Test -> Pass             -- run dune test, confirm all pass

implement :: Code -> Code >>> verify >>> test
```

The EBNF in `README.md` is the language spec. If parser behavior and EBNF diverge, either fix the parser or update the EBNF.

## CI/CD

Two GitHub Actions workflows in `.github/workflows/`:

- **`ci.yml`** — runs `dune test` on ubuntu-latest and macos-latest (OCaml 5.1) for every push to main and PR
- **`release.yml`** — triggered by `v*` tags; builds Linux x86_64 static binary (Alpine/musl, `--profile static`) and macOS arm64 binary (macos-15, `--profile release`), uploads to GitHub Releases

`dune-workspace` defines a `static` profile with `-ccopt -static` for musl static linking.

macOS x86_64 binary is **not built in CI** (Rosetta cross-compile doesn't work with OCaml — `ocamlopt` emits arm64 assembly regardless of shell arch). It must be built locally and uploaded via `scripts/release-macos-x86_64.sh`.

### Version Bumps

```arrow
let docs =
  update_docs(file: "CLAUDE.md")
  &&& update_docs(file: "README.md")
  &&& update_docs(file: "CHANGELOG.md")

bump(file: "dune-project")
  >>> docs
  >>> build -- dune build to regenerate opam files
  >>> test  -- dune test to confirm nothing broke
  >>> commit
```

### Releasing

```arrow
tag(format: "vX.Y.Z")
  >>> push(remote: origin, tag: "vX.Y.Z")
  >>> wait_ci -- wait for CI release workflow to complete
  >>> run(script: "scripts/release-macos-x86_64.sh") -- local Intel Mac upload
```

## Known Bugs

- `parser.ml`: Comments on `Var`, `App`, `Lambda`, and `Let` nodes are silently dropped during parsing (`attach_comments_right` treats them as leaves). After reduction, any comments attached to variables used in `let` bindings are lost entirely. See Future Ideas for candidate designs.
- `reducer.ml`: Curried free variable application (`let g = f(b)\ng(c)` where `f` is free) only survives one level of nesting. Deeper chains like `let h = g(d)\nh(e)` would fail at reduction. The current fix handles depth-2 (`App(App(Var _, _), _)`) but not arbitrary depth. A proper solution is to introduce an `in` keyword to delimit `let` scope, making the reducer's job explicit. See Future Ideas.
- `parser.ml`: The right-recursive precedence parser (`parse_seq_expr`/`parse_alt_expr`/`parse_par_expr`) is not tail-recursive. Extremely long pipelines (thousands of chained operators) could overflow the OCaml stack. In practice this is unlikely for human-authored workflows. If needed, switch to loop + `List.fold_right` to build right-associative AST iteratively.

## Future Ideas

- **Arrow laws rewriting** — now that the reducer exists, add an optimization pass that applies Arrow algebraic laws to simplify pipeline structure. Sits between reduce and check: `parse >>> reduce >>> optimize >>> check`. Candidates: associativity normalization, functor law for `***` (`(a *** b) >>> (c *** d)` → `(a >>> c) *** (b >>> d)`), identity elimination.
- **Expression-level comments** — currently comments only attach to `node.comments`, so `Var`/`Lambda`/`App`/`Let` nodes silently drop comments during parsing. After reduction, comments on variables are lost entirely. Two candidate designs: (a) add a `comments: string list` field to `expr` (like `type_ann`), making comments a first-class expression annotation that survives reduction; (b) add a `Commented of expr * string list` AST node wrapper that the reducer passes through. Both require updating `substitute` to preserve/merge comments when replacing a `Var`. Design (a) is cleaner but touches every `mk_expr` call and pattern match; design (b) is less invasive but adds a wrapping layer.
- **De Bruijn index IR** — replace the current alpha-renaming approach in the reducer with a de Bruijn index intermediate representation. Convert named AST to de Bruijn IR before reduction, perform substitution via index shifting (structurally capture-avoiding), then convert back to named AST. Eliminates the per-`reduce`-call `fresh_name` counter and makes substitution correctness a structural property rather than an algorithmic one. See: "Lambda Calculus and Combinators" (Hindley & Seldin), locally nameless representation as a lighter alternative.
- **`in` keyword for let scope** — introduce `let x = expr in body` syntax to explicitly delimit `let` scope, replacing the current implicit "rest of program" scoping. This would make the reducer's substitution boundary explicit, solving the curried free variable application depth issue (see Known Bugs) and aligning with standard functional language semantics. Alternative: use `;` as a separator. Requires lexer token, parser changes, and possibly AST adjustment.
- **Cost annotation and critical path analysis** — nodes already support unit-suffixed numbers (`3s`, `500ms`) as arg values, so `cost:` / `weight:` args need zero grammar changes. The AST is a free arrow — cost propagation maps naturally: `Seq` = sum, `Par`/`Fanout` = max, `Alt` = max or weighted average, `Loop` = cost × iterations. Enables PERT/CPM-style critical path identification, bottleneck detection in parallel branches, and cost-aware optimization (don't apply Arrow law rewrites that increase latency). See: Airflow `priority_weight`, Halide auto-scheduler, free arrows for static analysis (Fancher 2017), Granule graded modal types.

## Plans

- prefix any plan with 3 digits starts from 000
- treat plans as RFCs
