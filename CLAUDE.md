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

- `Ast` — ADT for DSL expressions: Node, Seq (`>>>`), Par (`***`), Alt (`|||`), Loop, Group
- `Lexer` — tokenizer, raises `Lex_error` on invalid input
- `Parser` — recursive descent parser, raises `Parse_error`
- `Checker` — structural validation (e.g. loop must contain an evaluation node)

## CLI Usage

Reads from file argument or stdin. Exits 0 with "OK" on success, exits 1 with error messages on failure.

```
echo 'a >>> b' | dune exec ocaml-compose-dsl
dune exec ocaml-compose-dsl -- pipeline.arrow
```

## Plans

- prefix any plan with 3 digits starts from 000
- treat plans as RFCs
