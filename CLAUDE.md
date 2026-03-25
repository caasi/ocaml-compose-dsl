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
  >>> Checker :: Ast -> Result
```

- `Ast` — ADT for DSL expressions: Node, Seq (`>>>`), Par (`***`), Fanout (`&&&`), Alt (`|||`), Loop, Group, Question (`?`). Values: String, Ident, Number (with optional unit suffix, e.g. `100mg`), List. Question uses `question_term` (QNode | QString) to constrain what `?` can wrap. Expressions carry optional `type_ann` (`:: Ident -> Ident`) for documentation.
- `Lexer` — tokenizer, raises `Lex_error` on invalid input. Supports Unicode identifiers and unit suffixes (non-ASCII bytes accepted). Column positions track codepoints, not bytes (via `String.get_utf_8_uchar`). Tokens include `DOUBLE_COLON` (`::`) and `ARROW` (`->`); `read_ident` uses lookahead to stop before `->` so that `A->B` tokenizes correctly despite `-` being a valid identifier character.
- `Parser` — recursive descent parser, raises `Parse_error`
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

## Plans

- prefix any plan with 3 digits starts from 000
- treat plans as RFCs
