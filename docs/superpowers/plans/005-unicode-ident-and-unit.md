# 005 Unicode Identifier and Number Unit Support

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow non-ASCII characters (CJK, Greek, accented Latin, etc.) in identifiers and number unit suffixes.

**Architecture:** Replace ASCII-only character predicates (`is_ident_start`, `is_ident_char`) with byte-level exclusion predicates. Any byte not in an explicit "special ASCII" set is valid. Number unit suffix reuses the same predicates with the constraint that suffix must start with a non-digit.

**Tech Stack:** OCaml, Alcotest

**Spec:** `docs/superpowers/specs/2026-03-21-unicode-ident-and-unit-design.md`

---

## File Map

- **Modify:** `lib/lexer.ml` — rewrite `is_ident_start`, `is_ident_char`, update `read_number` unit suffix loop
- **Modify:** `test/test_compose_dsl.ml` — add unicode lexer/parser tests, update existing error test
- **Modify:** `README.md` — update EBNF grammar

---

### Task 1: Add failing tests for unicode identifiers

**Files:**
- Modify: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write failing test — CJK identifier**

```ocaml
let test_lex_unicode_cjk_ident () =
  let tokens = Lexer.tokenize "翻譯" in
  match (List.hd tokens).token with
  | Lexer.IDENT "翻譯" -> ()
  | _ -> Alcotest.fail "expected IDENT 翻譯"
```

Add to `lexer_tests`:
```ocaml
; "unicode CJK ident", `Quick, test_lex_unicode_cjk_ident
```

- [ ] **Step 2: Write failing test — Greek letter identifier**

```ocaml
let test_lex_unicode_greek_ident () =
  let tokens = Lexer.tokenize "α" in
  match (List.hd tokens).token with
  | Lexer.IDENT "α" -> ()
  | _ -> Alcotest.fail "expected IDENT α"
```

Add to `lexer_tests`:
```ocaml
; "unicode Greek ident", `Quick, test_lex_unicode_greek_ident
```

- [ ] **Step 3: Write failing test — accented Latin identifier**

```ocaml
let test_lex_unicode_accented_ident () =
  let tokens = Lexer.tokenize "café" in
  match (List.hd tokens).token with
  | Lexer.IDENT "café" -> ()
  | _ -> Alcotest.fail "expected IDENT café"
```

Add to `lexer_tests`:
```ocaml
; "unicode accented ident", `Quick, test_lex_unicode_accented_ident
```

- [ ] **Step 4: Write failing test — mixed ASCII and unicode identifier**

```ocaml
let test_lex_unicode_mixed_ident () =
  let tokens = Lexer.tokenize "a_名前-test" in
  match (List.hd tokens).token with
  | Lexer.IDENT "a_名前-test" -> ()
  | _ -> Alcotest.fail "expected IDENT a_名前-test"
```

Add to `lexer_tests`:
```ocaml
; "unicode mixed ident", `Quick, test_lex_unicode_mixed_ident
```

- [ ] **Step 5: Run tests to verify they fail**

Run: `dune test 2>&1 | tail -20`
Expected: FAIL — `Lex_error` on non-ASCII bytes

- [ ] **Step 6: Commit failing tests**

```bash
git add test/test_compose_dsl.ml
git commit -m "test: add failing tests for unicode identifiers"
```

---

### Task 2: Add failing tests for unicode number unit suffix

**Files:**
- Modify: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write failing test — CJK unit suffix**

```ocaml
let test_lex_unicode_unit_suffix () =
  let tokens = Lexer.tokenize "500ミリ秒" in
  match (List.hd tokens).token with
  | Lexer.NUMBER "500ミリ秒" -> ()
  | _ -> Alcotest.fail "expected NUMBER 500ミリ秒"
```

Add to `lexer_tests`:
```ocaml
; "unicode unit suffix", `Quick, test_lex_unicode_unit_suffix
```

- [ ] **Step 2: Write failing test — unit suffix with digit**

```ocaml
let test_lex_unit_suffix_with_digit () =
  let tokens = Lexer.tokenize "100m2" in
  match (List.hd tokens).token with
  | Lexer.NUMBER "100m2" -> ()
  | _ -> Alcotest.fail "expected NUMBER 100m2"
```

Add to `lexer_tests`:
```ocaml
; "unit suffix with digit", `Quick, test_lex_unit_suffix_with_digit
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `dune test 2>&1 | tail -20`
Expected: FAIL — `500ミリ秒` hits `Lex_error` on non-ASCII byte after reading `500`; `100m2` produces NUMBER `"100m"` (suffix stops at digit) so the test fails on token value mismatch, not `Lex_error`

- [ ] **Step 4: Commit failing tests**

```bash
git add test/test_compose_dsl.ml
git commit -m "test: add failing tests for unicode number unit suffix"
```

---

### Task 3: Implement unicode-aware character predicates

**Files:**
- Modify: `lib/lexer.ml:25-27`

- [ ] **Step 1: Replace `is_ident_start` and `is_ident_char`**

Replace the existing two functions (lines 25-27):

```ocaml
let is_ident_start c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_'

let is_ident_char c = is_ident_start c || (c >= '0' && c <= '9') || c = '-'
```

With:

```ocaml
let is_special_ascii c =
  c = '(' || c = ')' || c = '[' || c = ']' || c = ':' || c = ','
  || c = '>' || c = '*' || c = '|' || c = '&' || c = '"' || c = '.'
  || c = '!' || c = '#' || c = '$' || c = '%' || c = '^' || c = '+'
  || c = '=' || c = '{' || c = '}' || c = '<' || c = ';' || c = '\''
  || c = '`' || c = '~' || c = '/' || c = '?' || c = '@' || c = '\\'
  || c = ' ' || c = '\t' || c = '\n' || c = '\r'

let is_ident_start c =
  not (is_special_ascii c) && not (c >= '0' && c <= '9') && c <> '-'

let is_ident_char c =
  not (is_special_ascii c)
```

- [ ] **Step 2: Run tests to verify unicode ident tests pass**

Run: `dune test 2>&1 | tail -20`
Expected: The 4 unicode ident tests from Task 1 now PASS. The 2 unicode unit tests from Task 2 still FAIL (unit suffix loop not yet updated).

- [ ] **Step 3: Commit**

```bash
git add lib/lexer.ml
git commit -m "feat: widen ident predicates to accept non-ASCII bytes"
```

---

### Task 4: Update number unit suffix to use new predicates

**Files:**
- Modify: `lib/lexer.ml:99-101`

- [ ] **Step 1: Replace the unit suffix loop in `read_number`**

Replace the existing unit suffix loop (lines 99-101):

```ocaml
    while !i < len && ((input.[!i] >= 'a' && input.[!i] <= 'z') || (input.[!i] >= 'A' && input.[!i] <= 'Z')) do
      advance ()
    done;
```

With (suffix must start with `is_ident_start` excluding `-`, then continues with `is_ident_char`):

```ocaml
    if !i < len && is_ident_start input.[!i] then begin
      advance ();
      while !i < len && is_ident_char input.[!i] do
        advance ()
      done
    end;
```

Note: `is_ident_start` already excludes `-` and digits, so no extra check needed.

- [ ] **Step 2: Run tests to verify all pass**

Run: `dune test`
Expected: ALL tests pass, including `unicode unit suffix` and `unit suffix with digit`.

- [ ] **Step 3: Commit**

```bash
git add lib/lexer.ml
git commit -m "feat: support unicode and digits in number unit suffix"
```

---

### Task 5: Add failing tests for unicode in parser context

**Files:**
- Modify: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write test — CJK node with CJK arg key**

```ocaml
let test_parse_unicode_node_with_args () =
  let ast = parse_ok {|翻譯(來源: "日文")|} in
  match ast with
  | Ast.Node n ->
    Alcotest.(check string) "name" "翻譯" n.name;
    Alcotest.(check int) "1 arg" 1 (List.length n.args);
    Alcotest.(check string) "arg key" "來源" (List.hd n.args).key;
    (match (List.hd n.args).value with
     | Ast.String "日文" -> ()
     | _ -> Alcotest.fail "expected String value")
  | _ -> Alcotest.fail "expected Node"
```

Add to `parser_tests`:
```ocaml
; "unicode node with args", `Quick, test_parse_unicode_node_with_args
```

- [ ] **Step 2: Write test — unicode ident seq**

```ocaml
let test_parse_unicode_seq () =
  let ast = parse_ok "café >>> naïve" in
  match ast with
  | Ast.Seq (Ast.Node a, Ast.Node b) ->
    Alcotest.(check string) "lhs" "café" a.name;
    Alcotest.(check string) "rhs" "naïve" b.name
  | _ -> Alcotest.fail "expected Seq"
```

Add to `parser_tests`:
```ocaml
; "unicode seq", `Quick, test_parse_unicode_seq
```

- [ ] **Step 3: Write test — Greek letter seq**

```ocaml
let test_parse_greek_seq () =
  let ast = parse_ok "α >>> β" in
  match ast with
  | Ast.Seq (Ast.Node a, Ast.Node b) ->
    Alcotest.(check string) "lhs" "α" a.name;
    Alcotest.(check string) "rhs" "β" b.name
  | _ -> Alcotest.fail "expected Seq"
```

Add to `parser_tests`:
```ocaml
; "Greek letter seq", `Quick, test_parse_greek_seq
```

- [ ] **Step 4: Write test — unicode unit in arg value**

```ocaml
let test_parse_unicode_unit_value () =
  let ast = parse_ok "wait(duration: 500ミリ秒)" in
  match ast with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.Number "500ミリ秒" -> ()
     | _ -> Alcotest.fail "expected Number with unicode unit")
  | _ -> Alcotest.fail "expected Node"
```

Add to `parser_tests`:
```ocaml
; "unicode unit in arg value", `Quick, test_parse_unicode_unit_value
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `dune test`
Expected: ALL pass (lexer already handles unicode, parser is token-level).

- [ ] **Step 6: Commit**

```bash
git add test/test_compose_dsl.ml
git commit -m "test: add parser-level tests for unicode identifiers and units"
```

---

### Task 6: Update existing error test and add reserved punctuation test

**Files:**
- Modify: `test/test_compose_dsl.ml`

- [ ] **Step 1: Update the `@` error test**

The existing `test_lex_unexpected_char` tests `@`. With the new predicates, `@` is in the reserved set so it should still fail. Verify the test still passes as-is — no change needed.

- [ ] **Step 2: Write test — `#` is rejected as reserved punctuation**

```ocaml
let test_lex_reserved_hash () =
  match Lexer.tokenize "#invalid" with
  | _ -> Alcotest.fail "expected lex error"
  | exception Lexer.Lex_error (_, msg) ->
    Alcotest.(check string) "error msg" "unexpected character '#'" msg
```

Add to `lexer_tests`:
```ocaml
; "reserved hash", `Quick, test_lex_reserved_hash
```

- [ ] **Step 3: Run tests to verify all pass**

Run: `dune test`
Expected: ALL pass.

- [ ] **Step 4: Commit**

```bash
git add test/test_compose_dsl.ml
git commit -m "test: add reserved punctuation error test"
```

---

### Task 7: Update EBNF in README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace the `ident` and `number` rules in the EBNF**

Replace:

```ebnf
ident    = ( letter | "_" ) , { letter | digit | "-" | "_" } ;
```

With:

```ebnf
ident       = ident_start , { ident_char } ;
ident_start = ? any byte that is not an ASCII digit, not ASCII whitespace,
                and not one of ( ) [ ] : , > * | & - " .
                ! # $ % ^ + = { } < ; ' ` ~ / ? @ \ ? ;
ident_char  = ? any byte that is not ASCII whitespace,
                and not one of ( ) [ ] : , > * | & " .
                ! # $ % ^ + = { } < ; ' ` ~ / ? @ \ ? ;
```

Replace:

```ebnf
number   = [ "-" ] , digit , { digit } , [ "." , digit , { digit } ] , { letter } ;
```

With:

```ebnf
unit_start = ? is_ident_start excluding "-" ? ;
number     = [ "-" ] , digit , { digit } , [ "." , digit , { digit } ] , [ unit_start , { ident_char } ] ;
```

- [ ] **Step 2: Run tests to make sure nothing is broken**

Run: `dune test`
Expected: ALL pass (README change is docs-only).

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: update EBNF for unicode ident and unit suffix support"
```

---

### Task 8: Final verification

- [ ] **Step 1: Run full test suite**

Run: `dune test`
Expected: ALL pass.

- [ ] **Step 2: Run CLI with unicode input**

Run: `echo '翻譯(來源: "日文") >>> α' | dune exec ocaml-compose-dsl`
Expected: prints AST output with unicode names.

- [ ] **Step 3: Verify build is clean**

Run: `dune clean && dune build`
Expected: no warnings.
