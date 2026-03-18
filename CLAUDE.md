# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

- `dune build` — build everything
- `dune exec ocaml-compose-dsl` — run the main executable
- `dune test` — run tests
- `dune clean` — remove build artifacts

## Project Structure

Two opam packages defined in `dune-project` (opam files are auto-generated via `generate_opam_files`):

- **ocaml-compose-dsl** — the executable (`bin/main.ml`), depends on the library
- **ocaml-compose-dsl-lib** — the library (`lib/compose_dsl.ml`), exposed as `compose_dsl`

## Requirements

- OCaml >= 5.1
- Dune 3.0+
- ocamlformat 0.26.2 (configured in `.ocamlformat`)

## Plans

- prefix any plan with 3 digits starts from 000
- treat plans as RFCs

