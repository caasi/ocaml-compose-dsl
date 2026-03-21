# Unicode Identifier and Number Unit Support

**Date:** 2026-03-21
**Status:** Approved

## Problem

The lexer currently restricts identifiers to ASCII `[a-zA-Z_][a-zA-Z0-9_-]*` and number unit suffixes to ASCII `[a-zA-Z]`. This prevents using non-Latin function/action names (e.g., `翻譯`, `α`) and non-Latin unit suffixes (e.g., `500ミリ秒`).

## Design

### Approach: Byte-level exclusion list

Instead of enumerating allowed Unicode categories, define characters by what they are **not**. Any byte that is not an ASCII special character is a valid identifier/unit character. This requires zero new dependencies and minimal lexer changes.

### Character classification

**Special ASCII set** (never part of an identifier):

```
( ) [ ] : , > * | & - " . space tab newline carriage-return
```

**`is_ident_start`**: any byte that is not in the special ASCII set AND not an ASCII digit `0-9`.

**`is_ident_char`**: any byte that is not in the special ASCII set. (ASCII digits allowed in continue position.)

Bytes > 127 (UTF-8 multi-byte sequences) automatically satisfy both predicates since they don't match any ASCII special character.

### Number unit suffix

The unit suffix loop in `read_number` changes from matching `[a-zA-Z]` to matching `is_ident_char`. This allows `500ミリ秒` to parse as `NUMBER "500ミリ秒"`.

### Unchanged components

- **AST** — `name: string` and `Number of string` are already opaque strings; Unicode passes through.
- **Parser** — operates on token kinds, not content. No changes needed.
- **Checker / Printer** — no changes needed.
- **`loop` keyword** — still matched by `if s = "loop" then LOOP`; unaffected.

### EBNF update

```ebnf
ident       = ident_start , { ident_char } ;
ident_start = ? any byte not ASCII digit, ASCII whitespace,
                or one of ( ) [ ] : , > * | & - " . ? ;
ident_char  = ? any byte not ASCII whitespace,
                or one of ( ) [ ] : , > * | & - " . ? ;

number      = [ "-" ] , digit , { digit } , [ "." , digit , { digit } ] , { ident_char } ;
```

### Trade-offs

- **No Unicode normalization**: `é` (precomposed U+00E9) and `é` (e + combining acute U+0301) are different identifiers. Acceptable for a DSL.
- **No `XID_Start`/`XID_Continue`**: theoretically allows odd identifiers like emoji. Acceptable given the loose design intent.
- **Zero new dependencies**: no `uutf`, `uucp`, or lookup tables needed.

## Test plan

| Input | Expected |
|---|---|
| `翻譯(來源: "日文")` | Node with name `翻譯`, arg key `來源`, String value |
| `wait(duration: 500ミリ秒)` | NUMBER `"500ミリ秒"` |
| `café >>> naïve` | Seq of two nodes with non-ASCII Latin idents |
| `α >>> β` | Seq of two nodes with Greek letter idents |
| `a_名前-test` | Single ident mixing ASCII and Unicode |
