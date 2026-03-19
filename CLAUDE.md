# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

Library modules:

- `Ast` — ADT for DSL expressions: Node, Seq (`>>>`), Par (`***`), Fanout (`&&&`), Alt (`|||`), Loop, Group
- `Lexer` — tokenizer, raises `Lex_error` on invalid input
- `Parser` — recursive descent parser, raises `Parse_error`
- `Checker` — structural validation (e.g. loop must contain an evaluation node)
- `Printer` — AST to OCaml constructor format string (for agent verification)

## CLI Usage

Reads from file argument or stdin. Exits 0 with AST output (OCaml constructor format) on success, exits 1 with error messages on failure.

```
echo 'a >>> b' | dune exec ocaml-compose-dsl
dune exec ocaml-compose-dsl -- pipeline.arrow
```

## After Any Implementation Change

1. Verify the EBNF in `README.md` still matches the parser/lexer behavior
2. Update or add tests in `test/test_compose_dsl.ml` to cover the change
3. Run `dune test` and confirm all tests pass

The EBNF is the language spec. If the parser diverges from the EBNF, either fix the parser or update the EBNF — they must stay in sync.

## CI/CD

Two GitHub Actions workflows in `.github/workflows/`:

- **`ci.yml`** — runs `dune test` on ubuntu-latest and macos-latest (OCaml 5.1) for every push to main and PR
- **`release.yml`** — triggered by `v*` tags; builds Linux x86_64 static binary (Alpine/musl, `--profile static`) and macOS arm64 binary (macos-15, `--profile release`), uploads to GitHub Releases

`dune-workspace` defines a `static` profile with `-ccopt -static` for musl static linking.

macOS x86_64 binary is **not built in CI** (Rosetta cross-compile doesn't work with OCaml — `ocamlopt` emits arm64 assembly regardless of shell arch). It must be built locally and uploaded via `scripts/release-macos-x86_64.sh`.

### Releasing

```sh
git tag v0.1.0
git push origin v0.1.0
# After CI release completes, upload macOS x86_64 from local Intel Mac:
./scripts/release-macos-x86_64.sh v0.1.0
```

## Known Bugs

- `checker.ml`: `String.sub s 0 5 = "check"` crashes when `String.length n.name = 4` — the guard only checks `>= 4` but `String.sub` needs `>= 5`. Same pattern may affect other substring checks in `scan`.
- `parser.ml`: Comments consumed by `eat_comments` in `parse_seq_expr`, `parse_alt_expr`, and `parse_par_expr` are silently discarded when `lhs` is not a `Node` (e.g. `Group`, `Loop`, `Fanout`). Only `Node` expressions can carry comments.

## Plans

- prefix any plan with 3 digits starts from 000
- treat plans as RFCs
