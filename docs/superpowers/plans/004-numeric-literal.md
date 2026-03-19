# Numeric Literal Support Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `Number of string` to the DSL value type so node arguments can accept numeric literals without evaluation.

**Architecture:** New `NUMBER of string` token in lexer, `Number of string` variant in AST, corresponding updates to parser, printer, and EBNF grammar. No changes to checker.

**Tech Stack:** OCaml, Alcotest, dune

**Spec:** `docs/superpowers/specs/2026-03-19-numeric-literal-design.md`

---

## Task 1: Add NUMBER token and Number value to AST/Lexer types

**Files:**
- Modify: `lib/ast.ml:1-4` (value type)
- Modify: `lib/lexer.ml:1-16` (token type)

- [ ] **Step 1: Add `Number of string` to `value` type in `lib/ast.ml`**

```ocaml
type value =
  | String of string
  | Ident of string
  | Number of string
  | List of value list
```

- [ ] **Step 2: Add `NUMBER of string` to `token` type in `lib/lexer.ml`**

Add after the `STRING of string` variant:

```ocaml
  | NUMBER of string
```

- [ ] **Step 3: Verify it compiles**

Run: `dune build`
Expected: Compiler warnings about non-exhaustive matches in parser and printer (this is expected — we'll fix them in subsequent tasks).

- [ ] **Step 4: Commit**

```bash
git add lib/ast.ml lib/lexer.ml
git commit -m "feat: add Number value variant and NUMBER token type"
```

---

## Task 2: Implement lexer number tokenization

**Files:**
- Modify: `lib/lexer.ml:28-129` (tokenize function)
- Test: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write failing lexer tests**

Add to `test/test_compose_dsl.ml` before `(* === Parser tests === *)`:

```ocaml
let test_lex_integer () =
  let tokens = Lexer.tokenize "42" in
  match (List.hd tokens).token with
  | Lexer.NUMBER "42" -> ()
  | _ -> Alcotest.fail "expected NUMBER 42"

let test_lex_float () =
  let tokens = Lexer.tokenize "3.14" in
  match (List.hd tokens).token with
  | Lexer.NUMBER "3.14" -> ()
  | _ -> Alcotest.fail "expected NUMBER 3.14"

let test_lex_negative_integer () =
  let tokens = Lexer.tokenize "a(x: -5)" in
  let has_neg =
    List.exists
      (fun (t : Lexer.located) ->
        match t.token with Lexer.NUMBER "-5" -> true | _ -> false)
      tokens
  in
  Alcotest.(check bool) "has NUMBER -5" true has_neg

let test_lex_negative_float () =
  let tokens = Lexer.tokenize "a(x: -0.5)" in
  let has_neg =
    List.exists
      (fun (t : Lexer.located) ->
        match t.token with Lexer.NUMBER "-0.5" -> true | _ -> false)
      tokens
  in
  Alcotest.(check bool) "has NUMBER -0.5" true has_neg

let test_lex_negative_is_not_comment () =
  let tokens = Lexer.tokenize "a(x: -3)" in
  let has_comment =
    List.exists
      (fun (t : Lexer.located) ->
        match t.token with Lexer.COMMENT _ -> true | _ -> false)
      tokens
  in
  Alcotest.(check bool) "no comment" false has_comment

let test_lex_trailing_dot () =
  match Lexer.tokenize "a(x: 3.)" with
  | _ -> Alcotest.fail "expected lex error"
  | exception Lexer.Lex_error (_, msg) ->
    Alcotest.(check string) "error msg" "expected digit after '.'" msg

let test_lex_leading_dot () =
  match Lexer.tokenize "a(x: .5)" with
  | _ -> Alcotest.fail "expected lex error"
  | exception Lexer.Lex_error (_, msg) ->
    Alcotest.(check string) "error msg" "unexpected character '.'" msg

let test_lex_unit_suffix () =
  let tokens = Lexer.tokenize "100mg" in
  match (List.hd tokens).token with
  | Lexer.NUMBER "100mg" -> ()
  | _ -> Alcotest.fail "expected NUMBER 100mg"

let test_lex_float_unit_suffix () =
  let tokens = Lexer.tokenize "2.5cm" in
  match (List.hd tokens).token with
  | Lexer.NUMBER "2.5cm" -> ()
  | _ -> Alcotest.fail "expected NUMBER 2.5cm"

let test_lex_negative_unit_suffix () =
  let tokens = Lexer.tokenize "a(x: -10dB)" in
  let has_neg =
    List.exists
      (fun (t : Lexer.located) ->
        match t.token with Lexer.NUMBER "-10dB" -> true | _ -> false)
      tokens
  in
  Alcotest.(check bool) "has NUMBER -10dB" true has_neg

let test_lex_number_no_unit () =
  let tokens = Lexer.tokenize "42" in
  match (List.hd tokens).token with
  | Lexer.NUMBER "42" -> ()
  | _ -> Alcotest.fail "expected NUMBER 42 (no unit)"
```

Register in `lexer_tests`:

```ocaml
  ; "integer literal", `Quick, test_lex_integer
  ; "float literal", `Quick, test_lex_float
  ; "negative integer", `Quick, test_lex_negative_integer
  ; "negative float", `Quick, test_lex_negative_float
  ; "negative is not comment", `Quick, test_lex_negative_is_not_comment
  ; "trailing dot invalid", `Quick, test_lex_trailing_dot
  ; "leading dot invalid", `Quick, test_lex_leading_dot
  ; "unit suffix", `Quick, test_lex_unit_suffix
  ; "float unit suffix", `Quick, test_lex_float_unit_suffix
  ; "negative unit suffix", `Quick, test_lex_negative_unit_suffix
  ; "number no unit", `Quick, test_lex_number_no_unit
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dune test`
Expected: FAIL — `Lex_error` on digit characters since lexer doesn't recognize them as token starts.

- [ ] **Step 3: Implement `read_number` and new match arms in lexer**

Add `read_number` function in `lib/lexer.ml` after `read_comment`:

```ocaml
  let read_number () =
    let p = pos () in
    let start = !i in
    if !i < len && input.[!i] = '-' then advance ();
    while !i < len && input.[!i] >= '0' && input.[!i] <= '9' do
      advance ()
    done;
    if !i < len && input.[!i] = '.' then begin
      advance ();
      let frac_start = !i in
      while !i < len && input.[!i] >= '0' && input.[!i] <= '9' do
        advance ()
      done;
      if !i = frac_start then
        raise (Lex_error (p, "expected digit after '.'"))
    end;
    (* optional unit suffix: letters only *)
    while !i < len && ((input.[!i] >= 'a' && input.[!i] <= 'z') || (input.[!i] >= 'A' && input.[!i] <= 'Z')) do
      advance ()
    done;
    let s = String.sub input start (!i - start) in
    { token = NUMBER s; pos = p }
  in
```

Two changes to the main `match c with` block:

**Change 1:** Replace the existing `'-'` arm with one that handles comment, negative number, and error:

```ocaml
      | '-' ->
        if peek2 () = Some '-' then begin
          tokens := read_comment () :: !tokens
        end else begin
          match peek2 () with
          | Some c2 when c2 >= '0' && c2 <= '9' ->
            tokens := read_number () :: !tokens
          | _ ->
            raise (Lex_error (p, Printf.sprintf "unexpected character '%c'" c))
        end
```

**Change 2:** Add a digit arm before the `c when is_ident_start c` arm:

```ocaml
      | c when c >= '0' && c <= '9' -> tokens := read_number () :: !tokens
```


- [ ] **Step 4: Run tests to verify they pass**

Run: `dune test`
Expected: All tests PASS (including existing tests).

- [ ] **Step 5: Commit**

```bash
git add lib/lexer.ml test/test_compose_dsl.ml
git commit -m "feat: implement number tokenization in lexer"
```

---

## Task 3: Update parser to handle NUMBER values

**Files:**
- Modify: `lib/parser.ml:34-63` (parse_value function)
- Test: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write failing parser tests**

Add to `test/test_compose_dsl.ml` after `test_parse_single_item_list`:

```ocaml
let test_parse_number_value () =
  let ast = parse_ok "resize(width: 1920)" in
  match ast with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.Number "1920" -> ()
     | _ -> Alcotest.fail "expected Number value")
  | _ -> Alcotest.fail "expected Node"

let test_parse_float_value () =
  let ast = parse_ok "delay(seconds: 3.5)" in
  match ast with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.Number "3.5" -> ()
     | _ -> Alcotest.fail "expected Number value")
  | _ -> Alcotest.fail "expected Node"

let test_parse_negative_value () =
  let ast = parse_ok "adjust(offset: -10)" in
  match ast with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.Number "-10" -> ()
     | _ -> Alcotest.fail "expected Number value")
  | _ -> Alcotest.fail "expected Node"

let test_parse_number_in_list () =
  let ast = parse_ok "a(dims: [1920, 1080])" in
  match ast with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.List [Ast.Number "1920"; Ast.Number "1080"] -> ()
     | _ -> Alcotest.fail "expected List of Numbers")
  | _ -> Alcotest.fail "expected Node"

let test_parse_number_with_unit () =
  let ast = parse_ok "dose(amount: 100mg)" in
  match ast with
  | Ast.Node n ->
    (match (List.hd n.args).value with
     | Ast.Number "100mg" -> ()
     | _ -> Alcotest.fail "expected Number with unit")
  | _ -> Alcotest.fail "expected Node"

let test_parse_number_as_node_name () =
  parse_fails "42(x: 1)"
```

Register in `parser_tests`:

```ocaml
  ; "number value", `Quick, test_parse_number_value
  ; "float value", `Quick, test_parse_float_value
  ; "negative value", `Quick, test_parse_negative_value
  ; "number in list", `Quick, test_parse_number_in_list
  ; "number with unit", `Quick, test_parse_number_with_unit
  ; "error: number as node name", `Quick, test_parse_number_as_node_name
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dune test`
Expected: FAIL — parser doesn't handle `NUMBER` token in `parse_value`.

- [ ] **Step 3: Add NUMBER handling to parser**

In `lib/parser.ml`, update `parse_value` — add after the `Lexer.STRING s` arm:

```ocaml
  | Lexer.NUMBER s -> advance st; Number s
```

Also update the inline value match inside the list-parsing branch (around line 49-52). Add after the `Lexer.STRING s` arm inside the list:

```ocaml
          | Lexer.NUMBER s -> advance st; Number s
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dune test`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/parser.ml test/test_compose_dsl.ml
git commit -m "feat: handle NUMBER token in parser value positions"
```

---

## Task 4: Update printer

**Files:**
- Modify: `lib/printer.ml:3-8` (value_to_string function)
- Test: `test/test_compose_dsl.ml`

- [ ] **Step 1: Write failing printer test**

Add to `test/test_compose_dsl.ml` after `test_print_comment`:

```ocaml
let test_print_number_arg () =
  let ast = parse_ok "resize(width: 1920, height: 1080)" in
  let s = Printer.to_string ast in
  Alcotest.(check string) "number args"
    {|Node("resize", [width: Number(1920), height: Number(1080)], [])|} s

let test_print_negative_number () =
  let ast = parse_ok "adjust(offset: -3.14)" in
  let s = Printer.to_string ast in
  Alcotest.(check string) "negative number"
    {|Node("adjust", [offset: Number(-3.14)], [])|} s

let test_print_number_with_unit () =
  let ast = parse_ok "dose(amount: 100mg)" in
  let s = Printer.to_string ast in
  Alcotest.(check string) "number with unit"
    {|Node("dose", [amount: Number(100mg)], [])|} s
```

Register in `printer_tests`:

```ocaml
  ; "number arg", `Quick, test_print_number_arg
  ; "negative number", `Quick, test_print_negative_number
  ; "number with unit", `Quick, test_print_number_with_unit
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dune test`
Expected: FAIL — non-exhaustive match in `value_to_string`.

- [ ] **Step 3: Add Number arm to printer**

In `lib/printer.ml`, add to `value_to_string` after the `Ident` arm:

```ocaml
  | Number s -> Printf.sprintf "Number(%s)" s
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dune test`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/printer.ml test/test_compose_dsl.ml
git commit -m "feat: print Number values without quoting"
```

---

## Task 5: Update EBNF grammar in README

**Files:**
- Modify: `README.md:36-43`

- [ ] **Step 1: Update the EBNF grammar**

Replace the `value` production and add `number` after `string`:

```ebnf
value    = string
         | number
         | ident
         | "[" , [ value , { "," , value } ] , "]"
         ;
```

Add `number` production after `string`:

```ebnf
string   = '"' , { any char - '"' } , '"' ;

number   = [ "-" ] , digit , { digit } , [ "." , digit , { digit } ] , { letter } ;
```

- [ ] **Step 2: Run full test suite to confirm nothing broke**

Run: `dune test`
Expected: All tests PASS.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add number production to EBNF grammar"
```
