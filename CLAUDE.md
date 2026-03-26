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
Lexer :: String -> Token
  >>> Parser :: Token -> Ast
  >>> Reducer :: Ast -> Ast   -- desugar let, beta reduce lambda
  >>> Checker :: Ast -> Result
```

- `Ast` — ADT for DSL expressions: Node, Seq (`>>>`), Par (`***`), Fanout (`&&&`), Alt (`|||`), Loop, Group, Question (`?`), Lambda (`\x -> body`), Var (variable reference), App (positional application), Let (`let x = expr`). Lambda, Var, App, and Let are reduced away by the Reducer before structural checking. Values: String, Ident, Number (with optional unit suffix, e.g. `100mg`), List. Question uses `question_term` (QNode | QString) to constrain what `?` can wrap. Expressions carry optional `type_ann` (`:: Ident -> Ident`) for documentation. **No unit value:** the DSL has no unit type or `()` literal; `f()` is a parse error, not zero-arg application. Positional application requires at least one argument per the EBNF (`positional_args = seq_expr , { "," , seq_expr }`).
- `Lexer` — tokenizer, raises `Lex_error` on invalid input. Supports Unicode identifiers and unit suffixes (non-ASCII bytes accepted). Column positions track codepoints, not bytes (via `String.get_utf_8_uchar`). Tokens include `DOUBLE_COLON` (`::`) and `ARROW` (`->`); `read_ident` uses lookahead to stop before `->` so that `A->B` tokenizes correctly despite `-` being a valid identifier character.
- `Parser` — recursive descent parser, raises `Parse_error`
- `Reducer` — desugars `Let` into `App(Lambda)`, performs beta reduction (substituting args into lambda bodies), and verifies no unreduced Lambda/Var/App/Let nodes remain. Raises `Reduce_error` on arity mismatch, non-function application, or unreduced nodes.
- `Checker` — structural validation and well-formedness warnings. Returns `{ errors; warnings }`. Warnings: e.g. `?` without matching `|||`. Uses `normalize` (graph reduction) to strip `Group` wrappers before balance checking.
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
implement :: Code -> Code
  >>> verify_ebnf :: Code -> Spec   -- check README.md EBNF still matches parser/lexer
  >>> update_tests :: Spec -> Test  -- update or add tests in test/test_compose_dsl.ml
  >>> dune_test :: Test -> Pass     -- run dune test, confirm all pass
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
bump(file: dune-project)
  >>> (update_docs(file: CLAUDE.md) &&& update_docs(file: README.md) &&& update_docs(file: CHANGELOG.md))
  >>> build -- dune build to regenerate opam files
  >>> test  -- dune test to confirm nothing broke
  >>> commit
```

### Releasing

```arrow
tag(format: "vX.Y.Z")
  >>> push(remote: origin, tag: "vX.Y.Z")
  >>> wait_ci -- wait for CI release workflow to complete
  >>> run(script: scripts/release-macos-x86_64.sh) -- local Intel Mac upload
```

## Known Bugs

- `parser.ml`: The right-recursive precedence parser (`parse_seq_expr`/`parse_alt_expr`/`parse_par_expr`) is not tail-recursive. Extremely long pipelines (thousands of chained operators) could overflow the OCaml stack. In practice this is unlikely for human-authored workflows. If needed, switch to loop + `List.fold_right` to build right-associative AST iteratively.

## Future Ideas

- **Arrow laws rewriting** — after plan 012 (lambda/let binding) lands and we have a reducer, add an optimization pass that applies Arrow algebraic laws to simplify pipeline structure. Sits between reduce and check: `parse >>> reduce >>> optimize >>> check`. Candidates: associativity normalization, functor law for `***` (`(a *** b) >>> (c *** d)` → `(a >>> c) *** (b >>> d)`), identity elimination.
- **Expression-level comments** — currently comments only attach to `node.comments`, so `Var`/`Lambda`/`App`/`Let` nodes silently drop comments during parsing. After reduction, comments on variables are lost entirely. Two candidate designs: (a) add a `comments: string list` field to `expr` (like `type_ann`), making comments a first-class expression annotation that survives reduction; (b) add a `Commented of expr * string list` AST node wrapper that the reducer passes through. Both require updating `substitute` to preserve/merge comments when replacing a `Var`. Design (a) is cleaner but touches every `mk_expr` call and pattern match; design (b) is less invasive but adds a wrapping layer.
- **De Bruijn index IR** — replace the current alpha-renaming approach in the reducer with a de Bruijn index intermediate representation. Convert named AST to de Bruijn IR before reduction, perform substitution via index shifting (structurally capture-avoiding), then convert back to named AST. Eliminates the `fresh_name` counter and makes substitution correctness a structural property rather than an algorithmic one. See: "Lambda Calculus and Combinators" (Hindley & Seldin), locally nameless representation as a lighter alternative.
- **Cost annotation and critical path analysis** — nodes already support unit-suffixed numbers (`3s`, `500ms`) as arg values, so `cost:` / `weight:` args need zero grammar changes. The AST is a free arrow — cost propagation maps naturally: `Seq` = sum, `Par`/`Fanout` = max, `Alt` = max or weighted average, `Loop` = cost × iterations. Enables PERT/CPM-style critical path identification, bottleneck detection in parallel branches, and cost-aware optimization (don't apply Arrow law rewrites that increase latency). See: Airflow `priority_weight`, Halide auto-scheduler, free arrows for static analysis (Fancher 2017), Granule graded modal types.

## Plans

- prefix any plan with 3 digits starts from 000
- treat plans as RFCs
