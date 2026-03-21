# Unicode Column Position Fix — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix `pos.col` to report Unicode codepoint counts instead of byte offsets, so error positions are correct for non-ASCII content (fixes #10).

**Architecture:** Rewrite `advance()` to use `String.get_utf_8_uchar` for UTF-8-aware stepping, fix `read_string` to use `String.sub` instead of byte-by-byte `Buffer.add_char`, rename `peek2` to `peek_byte`, add main loop comment. All changes in `lib/lexer.ml`.

**Tech Stack:** OCaml stdlib `Uchar` / `String.get_utf_8_uchar` (no external dependencies)

**Spec:** `docs/superpowers/specs/2026-03-21-unicode-col-position-design.md`

---

## Chunk 1: Failing tests for Unicode col positions

### Task 1: Add failing test — unicode ident col positions

**Files:**
- Modify: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write the failing test**

Add after `test_lex_unicode_mixed_ident` (around line 237):

```ocaml
let test_lex_unicode_ident_col () =
  let tokens = Lexer.tokenize "翻譯 >>> b" in
  let tok0 = List.nth tokens 0 in (* 翻譯 *)
  let tok1 = List.nth tokens 1 in (* >>> *)
  let tok2 = List.nth tokens 2 in (* b *)
  Alcotest.(check int) "翻譯 col" 1 tok0.pos.col;
  Alcotest.(check int) ">>> col" 4 tok1.pos.col;
  Alcotest.(check int) "b col" 8 tok2.pos.col
```

Register in `lexer_tests` list:

```ocaml
  ; "unicode ident col", `Quick, test_lex_unicode_ident_col
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dune exec test/test_compose_dsl.exe -- test Lexer 'unicode ident col'`
Expected: FAIL — col values will be byte offsets (e.g. 8 instead of 4 for `>>>`)

- [ ] **Step 3: Commit**

```bash
git add test/test_compose_dsl.ml
git commit -m "test: add failing test for unicode ident col positions"
```

### Task 2: Add failing test — mixed ASCII + unicode col

**Files:**
- Modify: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write the failing test**

Add after the previous test:

```ocaml
let test_lex_mixed_unicode_col () =
  let tokens = Lexer.tokenize "a翻譯b >>> c" in
  let tok0 = List.nth tokens 0 in (* a翻譯b *)
  let tok1 = List.nth tokens 1 in (* >>> *)
  Alcotest.(check string) "ident" "a翻譯b" (match tok0.token with Lexer.IDENT s -> s | _ -> "");
  Alcotest.(check int) "ident col" 1 tok0.pos.col;
  Alcotest.(check int) ">>> col" 6 tok1.pos.col
```

Register in `lexer_tests` list:

```ocaml
  ; "mixed unicode col", `Quick, test_lex_mixed_unicode_col
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dune exec test/test_compose_dsl.exe -- test Lexer 'mixed unicode col'`
Expected: FAIL — `>>>` col will be byte offset 10 instead of 6

- [ ] **Step 3: Commit**

```bash
git add test/test_compose_dsl.ml
git commit -m "test: add failing test for mixed ASCII + unicode col"
```

### Task 3: Add failing test — unicode in string literal col

**Files:**
- Modify: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write the failing test**

```ocaml
let test_lex_unicode_string_col () =
  let tokens = Lexer.tokenize {|"翻譯" >>> b|} in
  let tok0 = List.nth tokens 0 in (* "翻譯" *)
  let tok1 = List.nth tokens 1 in (* >>> *)
  let tok2 = List.nth tokens 2 in (* b *)
  Alcotest.(check int) "string col" 1 tok0.pos.col;
  Alcotest.(check int) ">>> col" 6 tok1.pos.col;
  Alcotest.(check int) "b col" 10 tok2.pos.col
```

Register in `lexer_tests` list:

```ocaml
  ; "unicode string col", `Quick, test_lex_unicode_string_col
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dune exec test/test_compose_dsl.exe -- test Lexer 'unicode string col'`
Expected: FAIL

- [ ] **Step 3: Commit**

```bash
git add test/test_compose_dsl.ml
git commit -m "test: add failing test for unicode string literal col"
```

### Task 4: Add regression guard — multiline unicode col

**Files:**
- Modify: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write the failing test**

```ocaml
let test_lex_multiline_unicode_col () =
  let tokens = Lexer.tokenize "翻譯\nb" in
  let tok0 = List.nth tokens 0 in (* 翻譯 *)
  let tok1 = List.nth tokens 1 in (* b *)
  Alcotest.(check int) "翻譯 line" 1 tok0.pos.line;
  Alcotest.(check int) "翻譯 col" 1 tok0.pos.col;
  Alcotest.(check int) "b line" 2 tok1.pos.line;
  Alcotest.(check int) "b col" 1 tok1.pos.col
```

Register in `lexer_tests` list:

```ocaml
  ; "multiline unicode col", `Quick, test_lex_multiline_unicode_col
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dune exec test/test_compose_dsl.exe -- test Lexer 'multiline unicode col'`
Expected: PASS — col resets on newline, so values are already correct. This is a regression guard for the advance() rewrite.

- [ ] **Step 3: Commit**

```bash
git add test/test_compose_dsl.ml
git commit -m "test: add regression guard for multiline unicode col"
```

### Task 5: Add test — malformed UTF-8 detection

**Files:**
- Modify: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write the failing test**

```ocaml
let test_lex_malformed_utf8 () =
  match Lexer.tokenize "\xff\xfe" with
  | _ -> Alcotest.fail "expected Lex_error"
  | exception Lexer.Lex_error (_, msg) ->
    Alcotest.(check string) "error msg" "invalid UTF-8 byte sequence" msg
```

Register in `lexer_tests` list:

```ocaml
  ; "malformed UTF-8", `Quick, test_lex_malformed_utf8
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dune exec test/test_compose_dsl.exe -- test Lexer 'malformed UTF-8'`
Expected: FAIL — current lexer treats `\xff` as a valid ident start byte (not special ASCII, not digit, not `-`), so it produces a token instead of erroring

- [ ] **Step 3: Commit**

```bash
git add test/test_compose_dsl.ml
git commit -m "test: add failing test for malformed UTF-8 detection"
```

### Task 6: Add test — error position after unicode

**Files:**
- Modify: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write the failing test**

```ocaml
let test_lex_error_col_after_unicode () =
  match Lexer.tokenize "翻譯 @" with
  | _ -> Alcotest.fail "expected Lex_error"
  | exception Lexer.Lex_error (pos, _) ->
    Alcotest.(check int) "error col" 4 pos.col
```

Register in `lexer_tests` list:

```ocaml
  ; "error col after unicode", `Quick, test_lex_error_col_after_unicode
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dune exec test/test_compose_dsl.exe -- test Lexer 'error col after unicode'`
Expected: FAIL — error col will be byte offset 8 instead of codepoint 4

- [ ] **Step 3: Commit**

```bash
git add test/test_compose_dsl.ml
git commit -m "test: add failing test for error col after unicode content"
```

---

## Chunk 2: Implementation

### Task 7: Rewrite `advance()` to use `String.get_utf_8_uchar`

**Files:**
- Modify: `lib/lexer.ml:46-49`

- [ ] **Step 1: Replace `advance()`**

Replace lines 46-49:

```ocaml
  let advance () =
    if !i < len && input.[!i] = '\n' then (incr line; col := 1)
    else incr col;
    incr i
  in
```

With:

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

- [ ] **Step 2: Run all tests**

Run: `dune test`
Expected: Most new unicode col tests should now pass. `test_lex_unicode_string_col` may still fail (read_string corruption). Malformed UTF-8 test should pass now.

- [ ] **Step 3: Commit**

```bash
git add lib/lexer.ml
git commit -m "fix: rewrite advance() to use String.get_utf_8_uchar for codepoint-level col tracking"
```

### Task 8: Fix `read_string` to use `String.sub`

**Files:**
- Modify: `lib/lexer.ml:57-68`

- [ ] **Step 1: Replace `read_string`**

Replace lines 57-68:

```ocaml
  let read_string () =
    let p = pos () in
    advance (); (* skip opening quote *)
    let buf = Buffer.create 32 in
    while !i < len && input.[!i] <> '"' do
      Buffer.add_char buf input.[!i];
      advance ()
    done;
    if !i >= len then raise (Lex_error (p, "unterminated string"));
    advance (); (* skip closing quote *)
    { token = STRING (Buffer.contents buf); pos = p }
  in
```

With:

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

- [ ] **Step 2: Run all tests**

Run: `dune test`
Expected: `test_lex_unicode_string_col` should now pass. All existing string tests should still pass.

- [ ] **Step 3: Commit**

```bash
git add lib/lexer.ml
git commit -m "fix: use String.sub in read_string to handle multibyte chars correctly"
```

### Task 9: Rename `peek2` to `peek_byte`

**Files:**
- Modify: `lib/lexer.ml:51` (definition) and all call sites (lines 132, 138, 144, 150, 156, 159)

- [ ] **Step 1: Rename definition and all call sites**

Replace line 51:
```ocaml
  let peek2 () = if !i + 1 < len then Some input.[!i + 1] else None in
```
With:
```ocaml
  let peek_byte () = if !i + 1 < len then Some input.[!i + 1] else None in
```

Then replace all `peek2 ()` calls with `peek_byte ()` (6 call sites in the main match).

- [ ] **Step 2: Run all tests**

Run: `dune test`
Expected: All tests pass (pure rename, no behavior change)

- [ ] **Step 3: Commit**

```bash
git add lib/lexer.ml
git commit -m "refactor: rename peek2 to peek_byte for clarity"
```

### Task 10: Add `peek_uchar` helper and main loop comment

**Files:**
- Modify: `lib/lexer.ml`

- [ ] **Step 1: Add `peek_uchar` after `peek_byte`**

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

- [ ] **Step 2: Add comment before `let c = input.[!i]` in main loop**

Before the line `let c = input.[!i] in` add:

```ocaml
      (* NOTE: byte-level dispatch. All operators/delimiters are ASCII, so
         matching on the raw byte is safe — UTF-8 continuation bytes (0x80-0xBF)
         never collide with ASCII, and lead bytes (0xC0-0xFF) fall through to
         the ident branch. To migrate to Uchar.t-based dispatch, change this
         match and the peek_byte calls above. *)
```

- [ ] **Step 3: Run all tests**

Run: `dune test`
Expected: All tests pass (no behavior change)

- [ ] **Step 4: Commit**

```bash
git add lib/lexer.ml
git commit -m "refactor: add peek_uchar helper and document byte-level dispatch"
```

---

## Chunk 3: Verification

### Task 11: Run full test suite and verify

- [ ] **Step 1: Run full test suite**

Run: `dune test`
Expected: All tests pass, 0 failures

- [ ] **Step 2: Run the CLI with unicode input to smoke test**

Run: `echo '翻譯 >>> café' | dune exec ocaml-compose-dsl`
Expected: Successful parse, AST output showing `Seq(Node(翻譯), Node(café))`

- [ ] **Step 3: Run the CLI with malformed UTF-8**

Run: `printf '\xff\xfe' | dune exec ocaml-compose-dsl`
Expected: Exit 1, error message containing "invalid UTF-8 byte sequence"

- [ ] **Step 4: Final commit if any fixups needed, then done**
