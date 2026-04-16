---
id: RULE-002
title: Reserved keywords must not capture identifier prefixes
domain: lexer
severity: must
---

## Given

Input text containing identifiers that start with or contain reserved keywords (`let`, `in`, `loop`).

## When

The lexer tokenizes the input.

## Then

- A keyword token is emitted **only** when the keyword appears as a standalone token (not part of a longer identifier).
- An identifier that starts with a keyword prefix (e.g., `letter`, `input`, `in_progress`, `loop_count`) must be tokenized as `IDENT`, not as the keyword.
- The keyword `in` followed by `_` or alphanumeric characters must be `IDENT` (e.g., `in_progress` -> `IDENT "in_progress"`).
- Standalone `in` must be tokenized as `IN`.
- Standalone `let` must be tokenized as `LET`.
- Standalone `loop` must be tokenized as `LOOP`.

## Unless

N/A — this rule has no exceptions.

## Examples

| Input | Expected Token(s) | Pass? |
|---|---|---|
| `letter` | `IDENT "letter"` | yes |
| `let x` | `LET`, `IDENT "x"` | yes |
| `input` | `IDENT "input"` | yes |
| `in` | `IN` | yes |
| `in_progress` | `IDENT "in_progress"` | yes |
| `x in` | `IDENT "x"`, `IN` | yes |
| `loop` | `LOOP` | yes |

## Properties

- **No false positives**: No identifier containing a keyword prefix is misclassified as the keyword.
- **No false negatives**: Standalone keywords are always correctly identified.
- **Longest match**: The lexer always produces the longest possible identifier token.
