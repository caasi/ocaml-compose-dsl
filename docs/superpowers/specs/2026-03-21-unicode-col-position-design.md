# Unicode Column Position Fix

**Issue:** [#10](https://github.com/caasi/ocaml-compose-dsl/issues/10)
**Date:** 2026-03-21

## Problem

`pos.col` in the lexer increments by 1 per byte via `advance()`. With unicode identifiers (introduced in #9), error positions report byte offsets rather than codepoint positions for non-ASCII content.

Example: `翻譯` is 6 bytes (2 CJK chars x 3 bytes), but col after it reports 7 instead of 3.

## Decision

- `col` semantics: **Unicode codepoint count** (not byte offset, not grapheme cluster)
- Error message format: **unchanged** (`line:col`, no extra annotation)
- Implementation: **OCaml stdlib `String.get_utf_8_uchar` / `Uchar`** (no external dependency)

## Design

### 1. `advance()` rewrite

Replace the current byte-level advance:

```ocaml
let advance () =
  if !i < len then begin
    let d = String.get_utf_8_uchar input !i in
    if Uchar.utf_decode_is_valid d then begin
      let n = Uchar.utf_decode_length d in
      let u = Uchar.utf_decode_uchar d in
      if Uchar.equal u (Uchar.of_char '\n') then
        (incr line; col := 1)
      else
        incr col;
      i := !i + n
    end else
      raise (Lex_error (pos (), "invalid UTF-8 byte sequence"))
  end
in
```

One call to `advance()` now skips an entire UTF-8 codepoint (1-4 bytes) and increments col by 1. Malformed UTF-8 raises `Lex_error` immediately.

### 2. `peek_uchar()` helper

```ocaml
let peek_uchar () =
  if !i >= len then None
  else
    let d = String.get_utf_8_uchar input !i in
    if Uchar.utf_decode_is_valid d then
      Some (Uchar.utf_decode_uchar d)
    else
      raise (Lex_error (pos (), "invalid UTF-8 byte sequence"))
in
```

Available for future use where unicode-aware peeking is needed.

### 3. `read_string` fix

`read_string` currently uses `Buffer.add_char buf input.[!i]` (adds one byte) then `advance()`. With the new `advance()` skipping entire codepoints (1-4 bytes), only the first byte of multibyte characters would be added, corrupting unicode string content.

Fix: replace the byte-by-byte `Buffer.add_char` loop with a `String.sub`-based approach (same pattern as `read_ident` and `read_comment`). Record `start` position before the loop, use `String.sub input start (!i - start)` after.

```ocaml
let read_string () =
  let p = pos () in
  advance (); (* skip opening quote *)
  let start = !i in
  while !i < len && input.[!i] <> '"' do
    advance ()
  done;
  if !i >= len then raise (Lex_error (p, "unterminated string"));
  let s = String.sub input start (!i - start) in
  advance (); (* skip closing quote *)
  { token = STRING s; pos = p }
in
```

Note: the `input.[!i] <> '"'` comparison remains byte-level. This is safe because `'"'` (`0x22`) cannot appear as a continuation byte in valid UTF-8, and malformed UTF-8 is caught by `advance()`.

### 4. Main loop dispatch — byte-level, with comment

The main `while` loop continues to use `input.[!i]` for pattern matching on operators and delimiters. This is safe because:

- All operators/delimiters are ASCII single-byte characters
- UTF-8 continuation bytes (`0x80-0xBF`) never collide with ASCII values
- UTF-8 lead bytes (`0xC0-0xFF`) fall through to the ident branch correctly

A comment is added to mark this as a future migration point for `Uchar.t`-based dispatch.

Rename `peek2` to `peek_byte` to clarify it returns a raw byte, not a codepoint. It is only ever called when sitting on an ASCII byte (`>`, `*`, `|`, `&`, `-`), so `!i + 1` is always the next byte boundary. Safe for the same reason.

### 5. What does NOT change

- `is_ident_start`, `is_ident_char` — byte-level predicates, still correct
- `pos` type — `{ line : int; col : int }` unchanged
- Error message format — unchanged
- `read_ident`, `read_comment` — use `String.sub` on byte ranges, correct since `i` is still a byte index
- README EBNF — grammar is unchanged, only position tracking semantics change

## Testing

### Update existing tests

Unicode-related tests that assert col values need their expected col updated from byte offset to codepoint count.

### New tests

| Test | Input | Expected |
|------|-------|----------|
| Unicode ident col | `翻譯 >>> b` | `翻譯` at col 1, `>>>` at col 4, `b` at col 8 |
| Mixed ASCII + unicode col | `a翻譯b >>> c` | ident at col 1, `>>>` at col 6 |
| Malformed UTF-8 | `\xff\xfe` | `Lex_error` with "invalid UTF-8 byte sequence" |
| Multiline unicode | `翻譯\nb` | `翻譯` at line 1 col 1, `b` at line 2 col 1 |
| Unicode in string literal col | `"翻譯" >>> b` | string at col 1, `>>>` at col 6, `b` at col 10 |
| Error position after unicode | `翻譯 @` | `Lex_error` at col 4 |

## Scope

- Files modified: `lib/lexer.ml`, `test/test_compose_dsl.ml`
- No new dependencies
- No API surface change
- No EBNF change
