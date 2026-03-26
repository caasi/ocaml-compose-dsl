# Literate Mode (`--literate` / `-l`)

## Summary

Add a `--literate` / `-l` CLI flag that accepts a Markdown file as input, extracts all `` ```arrow `` and `` ```arr `` fenced code blocks, concatenates them into a single source string, and runs the existing Lexer → Parser → Reducer → Checker → Printer pipeline on the result. Error line numbers are translated back to the original Markdown file positions.

This enables checking literate Arrow documents (like this project's own `CLAUDE.md`) and lays groundwork for future `let` bindings that reference across code blocks.

## Motivation

The project already uses the concept of "literate Arrow documents" — Markdown files with embedded `arrow` code blocks. Currently there is no way to validate these blocks without manually extracting them. A `--literate` flag makes the CLI a first-class tool for checking literate documents.

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| CLI flag name | `--literate` / `-l` | Follows Haskell literate programming precedent |
| Block semantics | Concatenation — all blocks treated as one `.arr` file | Enables future cross-block `let` binding references |
| Fence syntax | Backtick only (`` ``` ``), info string `arrow` or `arr` | Tilde fences are rare; both info strings are natural |
| Output | Same as normal mode — single merged AST on stdout | Consistent with "treat as one .arr file" semantics |
| Error line numbers | Translated to Markdown source positions | Users need to find errors in the `.md` file, not the concatenated string |
| Empty input | Let Parser report its natural parse error | No special handling; don't add stdout output |

## New Module: `lib/markdown.ml`

A pure string-processing module added to the `compose_dsl` library.

### Types

```ocaml
type block = {
  content : string;       (* code block content, excluding fences *)
  markdown_start : int;   (* 1-based start line in the original Markdown *)
}
```

### Functions

```ocaml
val extract : string -> block list
(** Scans a Markdown string and returns all ```arrow / ```arr code blocks
    in order of appearance. Only recognizes backtick fences. The opening
    fence line may have up to 3 leading spaces (CommonMark rule). The info
    string, after trimming trailing whitespace, must equal exactly "arrow"
    or "arr" — prefix matches like "arrows" or "arrow-diagram" do not
    count. Matching regex: ^[ ]{0,3}`{3}(arrow|arr)\s*$ *)

val combine : block list -> string * (int * int) list
(** Concatenates all blocks separated by a single newline ("\n"). Each
    block's content is included verbatim (trailing newlines preserved).
    Returns:
    - The combined source string ("" if block list is empty)
    - An offset table: list of (combined_start, markdown_start), both 1-based
      ([] if block list is empty).
    Used to translate line numbers from combined source back to Markdown. *)

val translate_line : (int * int) list -> int -> int
(** Given an offset table and a 1-based line number in the combined source,
    returns the corresponding 1-based line number in the original Markdown.
    Returns the input unchanged if the offset table is empty. *)
```

### Extraction Rules

The extractor is a line-by-line state machine with two states: `Outside` and `Inside`.

- **Outside → Inside**: A line matching the regex `^[ ]{0,3}`{3}(arrow|arr)\s*$` triggers entry. Only exactly 3 backticks are recognized (not 4+). The content starts on the next line. `markdown_start` records the line after the opening fence (1-based).
- **Inside → Outside**: A line matching `^[ ]{0,3}`{3}\s*$` (exactly 3 backticks, no info string) triggers exit. The closing fence line is not included in block content.
- Tilde fences (`~~~`) are ignored.
- Nested fences with 4+ backticks are not recognized and will be treated as plain content if inside a block, or ignored if outside.

### Line Number Translation

`combine` builds an offset table as it concatenates blocks. Each entry maps a range of lines in the combined string back to the original Markdown:

```
markdown_line = combined_line - combined_start + markdown_start
```

All values are 1-based, matching the Lexer's convention. `translate_line` searches the table from the end to find the entry where `combined_start <= target_line`.

The Lexer internally uses 1-based line/col tracking. This module's interface aligns with that — no base conversion needed at the boundary.

## Library Changes (`lib/compose_dsl.ml`)

Expose the new module so the CLI can access it as `Compose_dsl.Markdown`:

```ocaml
module Markdown = Markdown
```

## CLI Changes (`bin/main.ml`)

### Flag Recognition

Add `--literate` and `-l` to:
- `argv_has` checks
- `first_unknown_flag` exclusion list
- `usage_text`

### Main Flow

```ocaml
let literate = argv_has "--literate" || argv_has "-l" in
let input = match first_positional_arg () with
  | Some path -> read_file path
  | None -> read_all_stdin ()
in
let source, offset_table =
  if literate then
    let blocks = Compose_dsl.Markdown.extract input in
    Compose_dsl.Markdown.combine blocks
  else
    input, []
in
(* Lexer → Parser → Reducer → Checker → Printer as before *)
```

### Error Reporting

All `Printf.eprintf` calls for lex errors, parse errors, reduce errors, and checker warnings pass the line number through `Compose_dsl.Markdown.translate_line offset_table` before printing. This covers `pos.line` (lex/parse/reduce errors) and `loc.start.line` (checker warnings). The checker returns `{ warnings }` only — no errors. The current CLI only prints `start` positions; if `end_` positions are printed in the future, they must also be translated.

Column numbers are unchanged — each code block's content preserves its original columns.

## What Does NOT Change

- **Lexer** — no changes, stays 1-based internally
- **Parser** — no changes (`parse_program` entry point)
- **Reducer** — no changes (runs between parser and checker)
- **Checker** — no changes (returns `{ warnings }` only, no errors)
- **Printer** — no changes
- **stdout** — only AST output, same as normal mode
- **Exit codes** — 0 for success (with warnings on stderr), 1 for errors

## Updated Usage Text

```
ocaml-compose-dsl 0.7.0
A structural checker for Arrow-style DSL pipelines.

Usage:
  ocaml-compose-dsl [options] [<file>]
  cat <file> | ocaml-compose-dsl [options]

Options:
  -l, --literate  Extract and check ```arrow/```arr code blocks from Markdown
  -h, --help      Show this help message
  -v, --version   Show version

Reads from file argument or stdin.
Exits 0 with AST output (constructor-style format) on valid input, 1 with error messages.
```

## Testing Strategy

- **Unit tests for `Markdown.extract`**: single block, multiple blocks, no blocks, nested fences, indented fences, `arrow` vs `arr` info strings, tilde fences ignored, extra text after info string
- **Unit tests for `Markdown.combine`**: offset table correctness, empty block list
- **Unit tests for `Markdown.translate_line`**: single block, multiple blocks, empty table passthrough
- **Integration tests**: CLI with `--literate` flag on a sample `.md` file, error line number accuracy
