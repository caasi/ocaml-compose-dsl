# Unicode Identifier and Number Unit Support

**Date:** 2026-03-21
**Status:** Approved

## Problem

The lexer currently restricts identifiers to ASCII `[a-zA-Z_][a-zA-Z0-9_-]*` and number unit suffixes to ASCII `[a-zA-Z]`. This prevents using non-Latin function/action names (e.g., `翻譯`, `α`) and non-Latin unit suffixes (e.g., `500ミリ秒`).

## Design

### Approach: Byte-level exclusion list

Instead of enumerating allowed Unicode categories, define characters by what they are **not**. Any byte that is not an ASCII special character is a valid identifier/unit character. This requires zero new dependencies and minimal lexer changes.

### Character classification

Two exclusion sets, differing only in whether `-` and ASCII digits are excluded:

**`is_ident_start`**: any byte that is NOT one of:
- ASCII digits `0-9`
- ASCII whitespace (space, tab, newline, carriage-return)
- ASCII operators and delimiters: `( ) [ ] : , > * | & - " .`
- Reserved ASCII punctuation: `! # $ % ^ + = { } < ; ' \` ~ / ? @  \`

**`is_ident_char`**: any byte that is NOT one of:
- ASCII whitespace (space, tab, newline, carriage-return)
- ASCII operators and delimiters: `( ) [ ] : , > * | & " .`
- Reserved ASCII punctuation: `! # $ % ^ + = { } < ; ' \` ~ / ? @ \`

Key differences from `is_ident_start`:
- `-` (hyphen) is **allowed** in continue position (preserving current behavior like `a-b`)
- ASCII digits `0-9` are **allowed** in continue position

`_` (underscore) is not in either exclusion set, so it remains valid as both start and continue — preserving current behavior.

Bytes > 127 (UTF-8 multi-byte sequences) automatically satisfy both predicates since they don't match any ASCII character.

### Lexer dispatch

The main `match c with` dispatch already routes to `read_ident` via `c when is_ident_start c`. Widening `is_ident_start` to accept bytes > 127 means Unicode-leading bytes will naturally enter this path — no new match arm needed.

### Number unit suffix

The unit suffix in `read_number` must start with a non-digit (`is_ident_start`-like byte, excluding `-`), then continues with `is_ident_char` (which allows digits). This allows:

- `500ミリ秒` → NUMBER `"500ミリ秒"`
- `100m2` → NUMBER `"100m2"` (area unit shorthand)
- `100` followed by `200` → two separate NUMBER tokens (no suffix on first, digits don't start a suffix)

### Unchanged components

- **AST** — `name: string` and `Number of string` are already opaque strings; Unicode passes through.
- **Parser** — operates on token kinds, not content. No changes needed.
- **Checker / Printer** — no changes needed.
- **`loop` keyword** — still matched by `if s = "loop" then LOOP`; unaffected.

### EBNF update

```ebnf
ident       = ident_start , { ident_char } ;
ident_start = ? any byte that is not an ASCII digit, not ASCII whitespace,
                and not one of ( ) [ ] : , > * | & - " .
                ! # $ % ^ + = { } < ; ' ` ~ / ? @ \ ? ;
ident_char  = ? any byte that is not ASCII whitespace,
                and not one of ( ) [ ] : , > * | & " .
                ! # $ % ^ + = { } < ; ' ` ~ / ? @ \ ? ;

unit_start  = ? is_ident_start excluding "-" ? ;
number      = [ "-" ] , digit , { digit } , [ "." , digit , { digit } ] , [ unit_start , { ident_char } ] ;
```

### Trade-offs

- **No Unicode normalization**: `é` (precomposed U+00E9) and `é` (e + combining acute U+0301) are different identifiers. Acceptable for a DSL.
- **No `XID_Start`/`XID_Continue`**: theoretically allows odd identifiers like emoji. Acceptable given the loose design intent.
- **Zero new dependencies**: no `uutf`, `uucp`, or lookup tables needed.

### Known limitations

- **Column tracking**: the lexer increments column by 1 per byte. Multi-byte UTF-8 characters (e.g., 3-byte CJK) will report inflated column numbers in error messages. This is a cosmetic issue — error line numbers remain correct. Fixing this would require UTF-8 codepoint-aware advancing, which is out of scope for this change.

## Test plan

| Input | Expected |
|---|---|
| `翻譯(來源: "日文")` | Node with name `翻譯`, arg key `來源`, String value |
| `wait(duration: 500ミリ秒)` | NUMBER `"500ミリ秒"` |
| `café >>> naïve` | Seq of two nodes with non-ASCII Latin idents |
| `α >>> β` | Seq of two nodes with Greek letter idents |
| `a_名前-test` | Single ident mixing ASCII and Unicode |
| `100m2` | NUMBER `"100m2"` (unit suffix starts with letter, then digit) |
| `### invalid` | Lex error on `#` (reserved punctuation) |
