# Changelog

## [0.7.0] - 2026-03-25

### Added
- Type annotation syntax (`:: Ident -> Ident`) — optional annotations on nodes and terms to document data flow (e.g. `fetch :: URL -> HTML`)
- `DOUBLE_COLON` and `ARROW` tokens in lexer; lexer lookahead stops `read_ident` before `->` so `A->B` tokenizes correctly
- Printer outputs type annotations as `TypeAnn(expr, "input", "output")`
- Literate Arrow document convention — any Markdown file can embed `arrow` code blocks, no special extension needed
- `/compose` skill reference in CLAUDE.md for agent discoverability
- CLAUDE.md rewritten as a literate Arrow document

### Fixed
- Lexer: `read_ident` no longer consumes `->` as part of an identifier when no whitespace separates them (#18)
- Checker: specific warning when `?` is used as a `|||` operand (#16)
- `--help` text now reflects AST output instead of "OK"

## [0.6.1] - 2026-03-22

### Removed
- Loop evaluation node check from checker — loops no longer require English-named evaluation nodes (`evaluate`, `check`, `verify`, etc.). This was a semantic concern, not structural; the `?` + `|||` warning mechanism remains as a language-agnostic structural hint. (closes #12)

### Added
- Regression test `test_check_loop_plain_no_error` to prevent eval check from being reintroduced
- Version bump checklist in CLAUDE.md

### Fixed
- Stale Checker module description in CLAUDE.md (still referenced removed eval check)

## [0.6.0] - 2026-03-22

### Added
- AST location tracking — `pos` and `loc` types for all tokens and expressions
- Location spans on all `expr` nodes (parser captures start/end positions)
- Lexer emits `loc` spans on all tokens, tracking codepoint-level positions
- Checker attaches `loc` to all errors and warnings
- CLI displays `line:col` in error and warning output
- Loc span tests for lexer, parser, and checker diagnostics

### Changed
- `expr` split into `expr` (with `loc`) and `expr_desc` (the payload) — pattern matches use `expr.desc`
- Printer matches on `expr.desc` (output unchanged)

## [0.5.0] - 2026-03-22

### Added
- Question operator `?` — `string?` and `node?` syntax to explicitly mark Either-producing steps for `|||` branching
- `question_term` AST type (QNode | QString) constraining what `?` can wrap
- Checker warning mechanism — returns `{ errors; warnings }` instead of just `error list`
- Well-formedness warning: `?` without matching `|||` in scope
- Graph reduction (`normalize`) to strip `Group` wrappers before balance checking
- Helpful parse error for bare strings: `"did you mean to add '?'?"`
- CLI prints warnings to stderr without affecting exit code

## [0.4.0] - 2026-03-21

### Added
- Unicode identifier support — non-ASCII UTF-8 codepoints accepted in identifiers and number unit suffixes
- Full ASCII whitespace set — vertical tab (VT) and form feed (FF) now recognized as whitespace

### Fixed
- Column positions now track codepoints instead of byte offsets, so error messages report correct columns for multibyte characters
- `read_string` uses `String.sub` to handle multibyte characters correctly

## [0.3.0] - 2026-03-19

### Added
- Numeric literal support — `Number of string` value variant with integers, floats, negatives, and optional unit suffixes (e.g. `100mg`, `-3.14`, `2.5cm`)
- `number` production in EBNF grammar
- `parse_value` now handles list items directly (removes duplication, enables nested lists)

## [0.2.0] - 2026-03-19

### Added
- Fanout operator `&&&` — AST variant, lexer token, and parser support
- Precedence levels: `>>>` (lowest) < `|||` < `***`/`&&&` (highest), all right-associative
- Printer module — AST output in OCaml constructor format
- CLI `--help` and `--version` flags
- Example `.arr` files for subagent workflows

### Changed
- CLI output now prints AST in OCaml constructor format (was plain confirmation)

### Fixed
- Checker `String.sub` crash on node names shorter than 5 characters (e.g. `test`)
- Comments silently discarded on non-Node expressions (Group, Loop, etc.) — now attached to rightmost Node via `attach_comments_right`
- `|||` rendering in printer output

## [0.1.0] - 2025-06-07

Initial release.
