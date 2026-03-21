# Changelog

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
