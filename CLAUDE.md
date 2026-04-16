# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository. It is written as a **literate Arrow document** — prose mixed with `arrow` code blocks that describe workflows using the Arrow-style DSL defined in this project.

> **Skill:** This project ships a `/compose` skill for Claude Code. Use it to validate DSL syntax, plan tool composition, or write pipelines. If the skill is not installed, you can check the [README](./README.md) for grammar and semantics, or search the internet for `ocaml-compose-dsl` / `compose skill claude code`.
>
> **Binary:** `ocaml-compose-dsl` (or `dune exec ocaml-compose-dsl`) can validate Arrow syntax. The `arrow` blocks in this file are independent statements separated by `;` — validate them together with `dune exec ocaml-compose-dsl -- --literate CLAUDE.md`.

## Arrow DSL Conventions

- Use `->` for arrows (not `=>`). Follow standard PLT/Haskell arrow conventions.
- `&&&` is fanout, `***` is parallel, `|||` is alternation. Do not confuse them.
- When in doubt about operator semantics, check the EBNF in README.md.

## Build Commands

- `dune build` — build everything
- `dune exec ocaml-compose-dsl` — run the main executable
- `dune test` — run all tests (alcotest + QCheck property tests)
- `dune exec test/main.exe -- test <Suite> <N>` — run a single test by suite name and index
- `dune clean` — remove build artifacts

## Project Structure

Two opam packages defined in `dune-project` (opam files are auto-generated via `generate_opam_files`):

- **ocaml-compose-dsl** — the CLI executable (`bin/main.ml`), depends on the library
- **ocaml-compose-dsl-lib** — the library (`lib/`), exposed as `compose_dsl`

Library modules form a pipeline themselves:

```arrow
Parse_errors :: String -> Program;   -- Menhir incremental API; drives Lexer internally
Reducer :: Program -> Program;       -- desugar let, beta reduce lambda
Checker :: Program -> Result;        -- structural validation and warnings
Markdown :: Markdown -> String;      -- literate mode: extract arrow blocks

Parse_errors >>> Reducer >>> Checker;            -- standard mode
Markdown >>> Parse_errors >>> Reducer >>> Checker -- literate mode
```

- `Ast` — ADT for DSL expressions: Var (variable reference, bound or free), StringLit (string literal as expression), Unit (`()`), Seq (`>>>`), Par (`***`), Fanout (`&&&`), Alt (`|||`), Loop, Group, Question (`?`), Lambda (`\x -> body`), App (unified application with `call_arg list` — mixed named/positional), Let (`let x = expr in body`). Lambda and Let are reduced away by the Reducer. Free Var and App with free Var callee survive reduction. Values: String, Ident, Number (with optional unit suffix, e.g. `100mg`), List. Question takes an `expr` directly (parser allows Var, StringLit, App, or Unit). Expressions carry optional `type_ann` (`:: type_name -> type_name` where `type_name` is an ident or `()`) for documentation.
- `Lexer` — sedlex PPX-based tokenizer, raises `Lex_error` on invalid input. Pre-validates UTF-8 via `validate_utf8`. Pull-based `token` function skips comments (for Menhir); `read_token` returns all tokens including `COMMENT` (for batch `tokenize`). Supports Unicode identifiers and unit suffixes. Column positions track codepoints via `Sedlexing.lexeme_start`. Reserved keywords (`let`, `loop`, `in`) are disambiguated by `finalize_keyword` after lexing the full identifier. Hyphenated identifiers (e.g., `my-node`) use a separate sedlex rule; the DFA backtracks correctly before `->`. Re-exports `Parser.token` type for backward compatibility. `to_lexing_position` bridges `Ast.pos` to `Lexing.position` for the Menhir incremental API.
- `Parser` — Menhir-generated LALR(1) parser (`parser.mly`), compiled with `--table` for incremental API support. Entry point: `Parser.Incremental.program`. Per-arg disambiguation: `IDENT ":"` → Named arg, otherwise → Positional arg.
- `Parse_errors` — Menhir incremental API driver with custom error messages. Public entry point: `Parse_errors.parse :: string -> Ast.program`. Reads tokens via `Lexer.token`, feeds them to Menhir's `loop_handle`, and maps parser states to messages defined in `parser.messages` (compiled to `parser_messages.ml` by `menhir --compile-errors`). Detects reserved keyword usage and reports specific hints. Catches `Ast.Duplicate_param` and re-raises as `Parse_error`.
- `Reducer` — desugars `Let` into `App(Lambda)`, performs beta reduction (substituting args into lambda bodies). Free `Var` and `App` with free `Var` callee survive reduction. Raises `Reduce_error` on arity mismatch, named args on lambda, non-function application, or unreduced nodes. Alpha-renaming counter is local to each `reduce` call (deterministic, thread-safe).
- `Checker` — structural validation and well-formedness warnings. Returns `{ warnings }`. Warnings: `?` without matching `|||`; epistemic pairing: `branch` without `merge`, `leaf` without `check` (suggestion). Uses `normalize` (graph reduction) to strip `Group` wrappers before balance checking. Independently checks each Positional arg sub-expression in `App`. `collect_ident_names` deliberately uses list concatenation (`@`) instead of `StringSet` for simplicity — DSL pipelines are small; convert to `StringSet` only if profiling shows a bottleneck.
- `Printer` — AST to constructor-style format string (for agent verification). Type annotations are wrapped as `TypeAnn(expr, "input", "output")`.
- `Markdown` — literate mode support. `extract` scans Markdown for `` ```arrow ``/`` ```arr `` fenced code blocks (handles CRLF line endings). `combine` concatenates extracted blocks into a single source string with an offset table mapping combined line numbers to original Markdown line numbers. `translate_line` converts a combined-source line number back to the original Markdown position. Used by the CLI when `--literate` is passed.

## CLI Usage

Reads from file argument or stdin. Exits 0 with AST output (constructor-style format) on success (warnings, if any, go to stderr), exits 1 with error messages on failure.

```
echo 'a >>> b' | dune exec ocaml-compose-dsl
dune exec ocaml-compose-dsl -- pipeline.arr
dune exec ocaml-compose-dsl -- --literate README.md
```

## After Any Implementation Change

Every code change should follow this workflow:

```arrow
implement :: Code -> Code
  >>> verify_ebnf :: Code -> Spec    -- check README.md EBNF still matches parser/lexer
  >>> update_tests :: Spec -> Test   -- update or add tests under test/
  >>> dune_test :: Test -> ()        -- run dune test, confirm all pass
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
  &&& update_docs(file: "CHANGELOG.md") in
bump(file: "dune-project")
  >>> docs
  >>> build -- dune build to regenerate opam files
  >>> test  -- dune test to confirm nothing broke
  >>> commit :: () -> ()
```

### Releasing

```arrow
version_bump
  >>> tag(format: "vX.Y.Z")
  >>> push(remote: origin, tag: "vX.Y.Z")
  >>> wait_ci -- wait for CI release workflow to complete
  >>> run(script: "scripts/release-macos-x86_64.sh") -- local Intel Mac upload
```

## Testing

- **Unit tests** (alcotest) — example-based tests in `test/test_*.ml`, registered in `test/main.ml`
- **Property tests** (QCheck via `qcheck-alcotest`) — in `test/test_properties.ml`, integrated into the same alcotest runner under the "Properties" suite. Use `QCheck_alcotest.to_alcotest` to convert QCheck tests.
- **Constraints** — structured invariants in `constraints/*.md` (Given/When/Then/Examples/Properties format). These document the rules that tests enforce.
- **Mutation testing** — not yet integrated. mutaml 0.3 requires `ppxlib < 0.36.0` which conflicts with sedlex 3.7 (needs ppxlib >= 0.36.0). Revisit when mutaml supports ppxlib >= 0.36.0, or use a dedicated opam switch.

## Known Bugs

- `parser.mly` / `lexer.ml`: Comments on `Var`, `App`, `Lambda`, `Let`, and `Unit` nodes are silently dropped. The Menhir grammar's `token` function skips `COMMENT` tokens entirely, so they never reach the parser. See Future Ideas for candidate designs.

## Future Ideas

- **Arrow laws rewriting** — now that the reducer exists, add an optimization pass that applies Arrow algebraic laws to simplify pipeline structure. Sits between reduce and check: `parse >>> reduce >>> optimize >>> check`. Candidates: associativity normalization, functor law for `***` (`(a *** b) >>> (c *** d)` → `(a >>> c) *** (b >>> d)`), identity elimination.
- **Expression-level comments** — currently `Lexer.token` (the pull-based entry point for Menhir) skips `COMMENT` tokens entirely, so the parser never sees them. Comments are only available via `Lexer.tokenize` (batch mode). Two candidate designs: (a) add a `comments: string list` field to `expr` (like `type_ann`), making comments a first-class expression annotation that survives reduction — requires a comment-collecting wrapper around `Lexer.token` that buffers skipped comments and attaches them to the next AST node; (b) add a `Commented of expr * string list` AST node wrapper that the reducer passes through. Both require updating `substitute` to preserve/merge comments when replacing a `Var`. Design (a) is cleaner but touches every `mk_expr` call and pattern match; design (b) is less invasive but adds a wrapping layer.
- **De Bruijn index IR** — replace the current alpha-renaming approach in the reducer with a de Bruijn index intermediate representation. Convert named AST to de Bruijn IR before reduction, perform substitution via index shifting (structurally capture-avoiding), then convert back to named AST. Eliminates the per-`reduce`-call `fresh_name` counter and makes substitution correctness a structural property rather than an algorithmic one. See: "Lambda Calculus and Combinators" (Hindley & Seldin), locally nameless representation as a lighter alternative.
- **`let ... in` as expression form** — `let ... in` inside parenthesized groups is already supported (parsed by the `stmt` non-terminal in `parser.mly`). The remaining work is lifting it into `seq_expr` directly so it can appear in any expression position (e.g., as a `seq_expr` operand, inside function arguments) without requiring parentheses, similar to OCaml/Haskell. Deferred as YAGNI until a concrete use case arises.
- **Cost annotation and critical path analysis** — nodes already support unit-suffixed numbers (`3s`, `500ms`) as arg values, so `cost:` / `weight:` args need zero grammar changes. The AST is a free arrow — cost propagation maps naturally: `Seq` = sum, `Par`/`Fanout` = max, `Alt` = max or weighted average, `Loop` = cost × iterations. Enables PERT/CPM-style critical path identification, bottleneck detection in parallel branches, and cost-aware optimization (don't apply Arrow law rewrites that increase latency). See: Airflow `priority_weight`, Halide auto-scheduler, free arrows for static analysis (Fancher 2017), Granule graded modal types.

## Plans

- prefix any plan with 3 digits starts from 000
- treat plans as RFCs
