# Changelog

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
