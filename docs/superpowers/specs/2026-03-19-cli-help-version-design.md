# CLI `--help` and `--version` Support

## Summary

Add `--help` / `-h` and `--version` / `-v` flags to the `ocaml-compose-dsl` CLI. Hand-written argument handling (no library dependency). Version string injected at build time from `dune-project`.

## Motivation

The CLI currently has no usage information or version output. Running it with no arguments silently blocks on stdin, which is confusing for first-time users. Standard Unix CLI tools provide `--help` and `--version`.

## Design

### Version Injection

A `bin/version.ml` file is generated at build time by a dune rule using the `%{version:ocaml-compose-dsl}` variable, which reads the `(version ...)` field from `dune-project`. This keeps the version in a single source of truth.

**`bin/dune` addition:**

```dune
(rule
 (target version.ml)
 (action (write-file version.ml "let value = \"%{version:ocaml-compose-dsl}\"")))
```

### Argument Handling

Added to the top of `bin/main.ml`, before the existing stdin/file logic:

1. Scan **all** of `Sys.argv` (not just position 1) for known flags. Flags take priority regardless of position.
2. `--help` / `-h`: print usage text to stdout, exit 0.
3. `--version` / `-v`: print `ocaml-compose-dsl <version>` to stdout, exit 0.
4. Any argument starting with `-` that is not a known flag: print `unknown option: <arg>` to stderr, print usage text to stderr, exit 1.
5. No flags found: fall through to existing behavior (first non-flag arg as file, or stdin if none).

No changes to existing stdin/file reading logic.

### Help Output

```
ocaml-compose-dsl <version>
A structural checker for Arrow-style DSL pipelines.

Usage:
  ocaml-compose-dsl [<file>]
  cat <file> | ocaml-compose-dsl
  ocaml-compose-dsl --help
  ocaml-compose-dsl --version

Options:
  -h, --help     Show this help message
  -v, --version  Show version

Reads from file argument or stdin.
Exits 0 with "OK" on valid input, 1 with error messages.
```

`<version>` is replaced by the build-time version string.

### Version Output

```
ocaml-compose-dsl <version>
```

## Files Changed

| File | Change |
|------|--------|
| `bin/dune` | Add rule to generate `version.ml` |
| `bin/main.ml` | Add `--help`/`--version` handling before existing logic |

## Testing

- `dune exec ocaml-compose-dsl -- --help` prints usage, exits 0.
- `dune exec ocaml-compose-dsl -- --version` prints version, exits 0.
- `dune exec ocaml-compose-dsl -- -h` same as `--help`.
- `dune exec ocaml-compose-dsl -- -v` same as `--version`.
- `dune exec ocaml-compose-dsl -- --foo` prints unknown option error and usage to stderr, exits 1.
- `dune exec ocaml-compose-dsl -- file.arr --help` prints help (flag scanned across all args).
- Existing stdin/file behavior unchanged (run existing test suite).

## Future Work

- Support `-` as a pseudo-filename for explicit stdin reading.
