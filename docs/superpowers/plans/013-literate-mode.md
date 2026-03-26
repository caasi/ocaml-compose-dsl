# Literate Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `--literate` / `-l` CLI flag that extracts `arrow`/`arr` code blocks from Markdown input, concatenates them, and runs the existing check pipeline with line numbers mapped back to the original Markdown.

**Architecture:** New `lib/markdown.ml` module with three pure functions (`extract`, `combine`, `translate_line`). CLI gains a flag that gates a preprocessing step before the existing Lexer → Parser → Checker → Printer pipeline. No changes to the pipeline itself.

**Tech Stack:** OCaml 5.1, Dune, Alcotest

**Spec:** `docs/superpowers/specs/2026-03-26-literate-mode-design.md`

---

### Task 0: Create feature branch

- [ ] **Step 1: Create and switch to feature branch**

```bash
git checkout -b feat/literate-mode
```

---

### Task 1: Write failing tests for `Markdown.extract`

**Files:**
- Modify: `test/test_compose_dsl.ml`

- [ ] **Step 1: Add test for extracting a single arrow block**

Add after the printer test functions (around line 1310), before `printer_tests`:

Actually — add all markdown test functions at the end of the file, before the `let () =` runner block (line 1331).

```ocaml
(* === Markdown tests === *)

let test_md_extract_single_block () =
  let input = "# Title\n\n```arrow\na >>> b\n```\n\nSome text\n" in
  let blocks = Markdown.extract input in
  Alcotest.(check int) "one block" 1 (List.length blocks);
  let b = List.hd blocks in
  Alcotest.(check string) "content" "a >>> b\n" b.Markdown.content;
  Alcotest.(check int) "markdown_start" 4 b.Markdown.markdown_start
```

- [ ] **Step 2: Add test for extracting multiple blocks**

```ocaml
let test_md_extract_multiple_blocks () =
  let input = "# Title\n\n```arrow\na >>> b\n```\n\nText\n\n```arr\nc >>> d\n```\n" in
  let blocks = Markdown.extract input in
  Alcotest.(check int) "two blocks" 2 (List.length blocks);
  let b1 = List.nth blocks 0 in
  let b2 = List.nth blocks 1 in
  Alcotest.(check string) "block1 content" "a >>> b\n" b1.Markdown.content;
  Alcotest.(check int) "block1 start" 4 b1.Markdown.markdown_start;
  Alcotest.(check string) "block2 content" "c >>> d\n" b2.Markdown.content;
  Alcotest.(check int) "block2 start" 10 b2.Markdown.markdown_start
```

- [ ] **Step 3: Add test for no matching blocks**

```ocaml
let test_md_extract_no_blocks () =
  let input = "# Title\n\nJust text\n\n```python\nprint('hi')\n```\n" in
  let blocks = Markdown.extract input in
  Alcotest.(check int) "no blocks" 0 (List.length blocks)
```

- [ ] **Step 4: Add test for tilde fence ignored**

```ocaml
let test_md_extract_tilde_ignored () =
  let input = "~~~arrow\na >>> b\n~~~\n" in
  let blocks = Markdown.extract input in
  Alcotest.(check int) "no blocks" 0 (List.length blocks)
```

- [ ] **Step 5: Add test for indented fence (up to 3 spaces)**

```ocaml
let test_md_extract_indented_fence () =
  let input = "   ```arrow\na >>> b\n   ```\n" in
  let blocks = Markdown.extract input in
  Alcotest.(check int) "one block" 1 (List.length blocks);
  Alcotest.(check string) "content" "a >>> b\n" (List.hd blocks).Markdown.content
```

- [ ] **Step 6: Add test for 4-space indent rejected**

```ocaml
let test_md_extract_4space_not_fence () =
  let input = "    ```arrow\na >>> b\n    ```\n" in
  let blocks = Markdown.extract input in
  Alcotest.(check int) "no blocks" 0 (List.length blocks)
```

- [ ] **Step 7: Add test for info string prefix rejection**

```ocaml
let test_md_extract_prefix_rejected () =
  let input = "```arrows\na >>> b\n```\n```arrow-diagram\nc >>> d\n```\n" in
  let blocks = Markdown.extract input in
  Alcotest.(check int) "no blocks" 0 (List.length blocks)
```

- [ ] **Step 8: Add test for 4+ backtick fence ignored**

```ocaml
let test_md_extract_4backtick_ignored () =
  let input = "````arrow\na >>> b\n````\n" in
  let blocks = Markdown.extract input in
  Alcotest.(check int) "no blocks" 0 (List.length blocks)
```

- [ ] **Step 9: Add test for info string with trailing whitespace**

```ocaml
let test_md_extract_trailing_whitespace () =
  let input = "```arrow  \na >>> b\n```\n" in
  let blocks = Markdown.extract input in
  Alcotest.(check int) "one block" 1 (List.length blocks)
```

- [ ] **Step 10: Add test for extra text after info string rejected**

```ocaml
let test_md_extract_extra_text_rejected () =
  let input = "```arrow some-label\na >>> b\n```\n" in
  let blocks = Markdown.extract input in
  Alcotest.(check int) "no blocks" 0 (List.length blocks)
```

- [ ] **Step 11: Add standalone test for `arr` info string**

```ocaml
let test_md_extract_arr_info_string () =
  let input = "```arr\na >>> b\n```\n" in
  let blocks = Markdown.extract input in
  Alcotest.(check int) "one block" 1 (List.length blocks);
  Alcotest.(check string) "content" "a >>> b\n" (List.hd blocks).Markdown.content
```

- [ ] **Step 12: Add test for unclosed block**

```ocaml
let test_md_extract_unclosed_block () =
  let input = "```arrow\na >>> b\n" in
  let blocks = Markdown.extract input in
  Alcotest.(check int) "one block" 1 (List.length blocks);
  Alcotest.(check string) "content" "a >>> b\n" (List.hd blocks).Markdown.content
```

- [ ] **Step 13: Register the markdown extract test suite**

Add the test list and register it in the `Alcotest.run` block:

```ocaml
let markdown_tests =
  [ "single block", `Quick, test_md_extract_single_block
  ; "multiple blocks", `Quick, test_md_extract_multiple_blocks
  ; "no blocks", `Quick, test_md_extract_no_blocks
  ; "tilde ignored", `Quick, test_md_extract_tilde_ignored
  ; "indented fence", `Quick, test_md_extract_indented_fence
  ; "4-space not fence", `Quick, test_md_extract_4space_not_fence
  ; "prefix rejected", `Quick, test_md_extract_prefix_rejected
  ; "4+ backtick ignored", `Quick, test_md_extract_4backtick_ignored
  ; "trailing whitespace", `Quick, test_md_extract_trailing_whitespace
  ; "extra text rejected", `Quick, test_md_extract_extra_text_rejected
  ; "arr info string", `Quick, test_md_extract_arr_info_string
  ; "unclosed block", `Quick, test_md_extract_unclosed_block
  ]
```

Update `Alcotest.run`:

```ocaml
let () =
  Alcotest.run "compose-dsl"
    [ "Lexer", lexer_tests
    ; "Parser", parser_tests
    ; "Checker", checker_tests
    ; "Printer", printer_tests
    ; "Markdown", markdown_tests
    ]
```

- [ ] **Step 11: Run tests to verify they fail**

Run: `dune test`
Expected: Compilation error — `Markdown` module does not exist yet.

- [ ] **Step 12: Commit**

```bash
git add test/test_compose_dsl.ml
git commit -m "test: add failing tests for Markdown.extract"
```

---

### Task 2: Implement `Markdown.extract`

**Files:**
- Create: `lib/markdown.ml`
- Modify: `lib/compose_dsl.ml`

- [ ] **Step 1: Create `lib/markdown.ml` with type and `extract` function**

```ocaml
type block = {
  content : string;
  markdown_start : int;
}

let is_opening_fence line =
  let len = String.length line in
  let i = ref 0 in
  (* skip up to 3 leading spaces *)
  while !i < len && !i < 3 && line.[!i] = ' ' do incr i done;
  (* must have exactly 3 backticks *)
  if !i + 3 > len then false
  else if line.[!i] <> '`' || line.[!i+1] <> '`' || line.[!i+2] <> '`' then false
  else if !i + 3 < len && line.[!i+3] = '`' then false (* 4+ backticks *)
  else begin
    i := !i + 3;
    (* extract info string *)
    let info_start = !i in
    while !i < len && line.[!i] <> ' ' && line.[!i] <> '\t' do incr i done;
    let info = String.sub line info_start (!i - info_start) in
    (* rest must be whitespace *)
    while !i < len && (line.[!i] = ' ' || line.[!i] = '\t') do incr i done;
    !i = len && (info = "arrow" || info = "arr")
  end

let is_closing_fence line =
  let len = String.length line in
  let i = ref 0 in
  while !i < len && !i < 3 && line.[!i] = ' ' do incr i done;
  if !i + 3 > len then false
  else if line.[!i] <> '`' || line.[!i+1] <> '`' || line.[!i+2] <> '`' then false
  else if !i + 3 < len && line.[!i+3] = '`' then false
  else begin
    i := !i + 3;
    while !i < len && (line.[!i] = ' ' || line.[!i] = '\t') do incr i done;
    !i = len
  end

let extract input =
  let lines = String.split_on_char '\n' input in
  let rec scan lines line_num state acc =
    match lines, state with
    | [], `Outside -> List.rev acc
    | [], `Inside (start, buf) ->
      (* unclosed block — include what we have *)
      let content = Buffer.contents buf in
      List.rev ({ content; markdown_start = start } :: acc)
    | line :: rest, `Outside ->
      if is_opening_fence line then
        scan rest (line_num + 1) (`Inside (line_num + 1, Buffer.create 256)) acc
      else
        scan rest (line_num + 1) `Outside acc
    | line :: rest, `Inside (start, buf) ->
      if is_closing_fence line then begin
        let content = Buffer.contents buf in
        scan rest (line_num + 1) `Outside ({ content; markdown_start = start } :: acc)
      end else begin
        Buffer.add_string buf line;
        Buffer.add_char buf '\n';
        scan rest (line_num + 1) (`Inside (start, buf)) acc
      end
  in
  scan lines 1 `Outside []
```

Note: `String.split_on_char '\n'` will produce a trailing empty string if input ends with `\n`. The state machine handles this correctly — an empty line in `Outside` is just skipped, and in `Inside` it adds a blank line to the buffer.

- [ ] **Step 2: Expose in `lib/compose_dsl.ml`**

Add to `lib/compose_dsl.ml`:

```ocaml
module Markdown = Markdown
```

- [ ] **Step 3: Run tests to verify they pass**

Run: `dune test`
Expected: All 9 new Markdown tests pass, all existing tests still pass.

- [ ] **Step 4: Commit**

```bash
git add lib/markdown.ml lib/compose_dsl.ml
git commit -m "feat: implement Markdown.extract for literate mode"
```

---

### Task 3: Write failing tests for `Markdown.combine` and `Markdown.translate_line`

**Files:**
- Modify: `test/test_compose_dsl.ml`

- [ ] **Step 1: Add test for combine with single block**

```ocaml
let test_md_combine_single () =
  let blocks = [{ Markdown.content = "a >>> b\n"; markdown_start = 10 }] in
  let source, table = Markdown.combine blocks in
  Alcotest.(check string) "source" "a >>> b\n" source;
  Alcotest.(check int) "table length" 1 (List.length table);
  let (cs, ms) = List.hd table in
  Alcotest.(check int) "combined_start" 1 cs;
  Alcotest.(check int) "markdown_start" 10 ms
```

- [ ] **Step 2: Add test for combine with multiple blocks**

```ocaml
let test_md_combine_multiple () =
  let blocks =
    [ { Markdown.content = "a >>> b\n"; markdown_start = 10 }
    ; { Markdown.content = "c >>> d\ne >>> f\n"; markdown_start = 30 }
    ] in
  let source, table = Markdown.combine blocks in
  Alcotest.(check string) "source" "a >>> b\n\nc >>> d\ne >>> f\n" source;
  Alcotest.(check int) "table length" 2 (List.length table);
  let (cs1, ms1) = List.nth table 0 in
  let (cs2, ms2) = List.nth table 1 in
  Alcotest.(check int) "block1 combined_start" 1 cs1;
  Alcotest.(check int) "block1 markdown_start" 10 ms1;
  (* block1 has 1 line + 1 separator newline = block2 starts at line 3 *)
  Alcotest.(check int) "block2 combined_start" 3 cs2;
  Alcotest.(check int) "block2 markdown_start" 30 ms2
```

- [ ] **Step 3: Add test for combine with empty list**

```ocaml
let test_md_combine_empty () =
  let source, table = Markdown.combine [] in
  Alcotest.(check string) "source" "" source;
  Alcotest.(check int) "table length" 0 (List.length table)
```

- [ ] **Step 4: Add test for translate_line with single block**

```ocaml
let test_md_translate_single () =
  let table = [(1, 10)] in
  (* line 1 in combined = line 10 in markdown *)
  Alcotest.(check int) "line 1" 10 (Markdown.translate_line table 1);
  Alcotest.(check int) "line 3" 12 (Markdown.translate_line table 3)
```

- [ ] **Step 5: Add test for translate_line with multiple blocks**

```ocaml
let test_md_translate_multiple () =
  let table = [(1, 10); (3, 30)] in
  (* line 1 -> block1: 1 - 1 + 10 = 10 *)
  Alcotest.(check int) "line 1" 10 (Markdown.translate_line table 1);
  (* line 2 -> block1: 2 - 1 + 10 = 11 *)
  Alcotest.(check int) "line 2" 11 (Markdown.translate_line table 2);
  (* line 3 -> block2: 3 - 3 + 30 = 30 *)
  Alcotest.(check int) "line 3" 30 (Markdown.translate_line table 3);
  (* line 5 -> block2: 5 - 3 + 30 = 32 *)
  Alcotest.(check int) "line 5" 32 (Markdown.translate_line table 5)
```

- [ ] **Step 6: Add test for translate_line with empty table (passthrough)**

```ocaml
let test_md_translate_empty () =
  Alcotest.(check int) "passthrough" 42 (Markdown.translate_line [] 42)
```

- [ ] **Step 7: Register combine and translate tests in the suite**

Update `markdown_tests` to include:

```ocaml
let markdown_tests =
  [ "single block", `Quick, test_md_extract_single_block
  ; "multiple blocks", `Quick, test_md_extract_multiple_blocks
  ; "no blocks", `Quick, test_md_extract_no_blocks
  ; "tilde ignored", `Quick, test_md_extract_tilde_ignored
  ; "indented fence", `Quick, test_md_extract_indented_fence
  ; "4-space not fence", `Quick, test_md_extract_4space_not_fence
  ; "prefix rejected", `Quick, test_md_extract_prefix_rejected
  ; "4+ backtick ignored", `Quick, test_md_extract_4backtick_ignored
  ; "trailing whitespace", `Quick, test_md_extract_trailing_whitespace
  ; "extra text rejected", `Quick, test_md_extract_extra_text_rejected
  ; "arr info string", `Quick, test_md_extract_arr_info_string
  ; "unclosed block", `Quick, test_md_extract_unclosed_block
  ; "combine single", `Quick, test_md_combine_single
  ; "combine multiple", `Quick, test_md_combine_multiple
  ; "combine empty", `Quick, test_md_combine_empty
  ; "translate single", `Quick, test_md_translate_single
  ; "translate multiple", `Quick, test_md_translate_multiple
  ; "translate empty", `Quick, test_md_translate_empty
  ]
```

- [ ] **Step 8: Run tests to verify they fail**

Run: `dune test`
Expected: Compilation error — `Markdown.combine` and `Markdown.translate_line` do not exist yet.

- [ ] **Step 9: Commit**

```bash
git add test/test_compose_dsl.ml
git commit -m "test: add failing tests for Markdown.combine and translate_line"
```

---

### Task 4: Implement `Markdown.combine` and `Markdown.translate_line`

**Files:**
- Modify: `lib/markdown.ml`

- [ ] **Step 1: Add `combine` function**

Add to `lib/markdown.ml`:

```ocaml
let count_lines s =
  let n = ref 0 in
  String.iter (fun c -> if c = '\n' then incr n) s;
  !n

let combine blocks =
  match blocks with
  | [] -> ("", [])
  | _ ->
    let buf = Buffer.create 1024 in
    let rec build blocks current_line acc =
      match blocks with
      | [] -> (Buffer.contents buf, List.rev acc)
      | b :: rest ->
        if current_line > 1 then Buffer.add_char buf '\n';
        Buffer.add_string buf b.content;
        let entry = (current_line, b.markdown_start) in
        let lines_in_block = count_lines b.content in
        let next_line = current_line + lines_in_block + (if rest <> [] then 1 else 0) in
        build rest next_line (entry :: acc)
    in
    build blocks 1 []
```

- [ ] **Step 2: Add `translate_line` function**

```ocaml
let translate_line table line =
  match table with
  | [] -> line
  | _ ->
    let rec find = function
      | [] -> line
      | [(cs, ms)] -> line - cs + ms
      | (cs, ms) :: ((cs2, _) :: _ as rest) ->
        if line < cs2 then line - cs + ms
        else find rest
    in
    find table
```

- [ ] **Step 3: Run tests to verify they pass**

Run: `dune test`
Expected: All 18 Markdown tests pass, all existing tests still pass.

- [ ] **Step 4: Commit**

```bash
git add lib/markdown.ml
git commit -m "feat: implement Markdown.combine and translate_line"
```

---

### Task 5: Update CLI with `--literate` flag

**Files:**
- Modify: `bin/main.ml`

- [ ] **Step 1: Update `usage_text`**

Replace the current `usage_text` string in `bin/main.ml` (lines 17–34) with:

```ocaml
let usage_text =
  Printf.sprintf
    {|ocaml-compose-dsl %s
A structural checker for Arrow-style DSL pipelines.

Usage:
  ocaml-compose-dsl [options] [<file>]
  cat <file> | ocaml-compose-dsl [options]

Options:
  -l, --literate  Extract and check ```arrow/```arr code blocks from Markdown
  -h, --help      Show this help message
  -v, --version   Show version

Reads from file argument or stdin.
Exits 0 with AST output (constructor-style format) on valid input, 1 with error messages.|}
    Version.value
```

- [ ] **Step 2: Add `--literate` / `-l` to `first_unknown_flag` exclusions**

In `first_unknown_flag` (line 49–56), add to the condition:

```ocaml
    && a <> "--literate" && a <> "-l"
```

- [ ] **Step 3: Add literate mode to main flow**

Replace the main flow (lines 79–107) with:

```ocaml
  let literate = argv_has "--literate" || argv_has "-l" in
  let input =
    match first_positional_arg () with
    | Some path -> read_file path
    | None -> read_all_stdin ()
  in
  let source, offset_table =
    if literate then
      let blocks = Compose_dsl.Markdown.extract input in
      Compose_dsl.Markdown.combine blocks
    else
      input, []
  in
  let tl = Compose_dsl.Markdown.translate_line offset_table in
  match Compose_dsl.Lexer.tokenize source with
  | exception Compose_dsl.Lexer.Lex_error (pos, msg) ->
    Printf.eprintf "lex error at %d:%d: %s\n" (tl pos.line) pos.col msg;
    exit 1
  | tokens ->
    match Compose_dsl.Parser.parse tokens with
    | exception Compose_dsl.Parser.Parse_error (pos, msg) ->
      Printf.eprintf "parse error at %d:%d: %s\n" (tl pos.line) pos.col msg;
      exit 1
    | ast ->
      let result = Compose_dsl.Checker.check ast in
      List.iter
        (fun (w : Compose_dsl.Checker.warning) ->
          Printf.eprintf "warning at %d:%d: %s\n" (tl w.loc.start.line) w.loc.start.col w.message)
        result.warnings;
      if result.errors = [] then (
        print_endline (Compose_dsl.Printer.to_string ast);
        exit 0)
      else (
        List.iter
          (fun (e : Compose_dsl.Checker.error) ->
            Printf.eprintf "check error at %d:%d: %s\n" (tl e.loc.start.line) e.loc.start.col e.message)
          result.errors;
        exit 1)
```

- [ ] **Step 4: Build to verify compilation**

Run: `dune build`
Expected: Compiles without errors.

- [ ] **Step 5: Run all tests**

Run: `dune test`
Expected: All tests pass (existing + markdown).

- [ ] **Step 6: Manual smoke test**

Test with the project's own CLAUDE.md:

```bash
dune exec ocaml-compose-dsl -- --literate CLAUDE.md
```

Expected: AST output for the arrow blocks in CLAUDE.md, exit 0.

- [ ] **Step 7: Commit**

```bash
git add bin/main.ml
git commit -m "feat: add --literate / -l flag for Markdown input"
```

---

### Task 6: Add integration test for literate mode end-to-end

**Files:**
- Create: `test/fixtures/sample.md`
- Modify: `test/test_compose_dsl.ml`

- [ ] **Step 1: Create a sample Markdown fixture file**

Create `test/fixtures/sample.md`:

```markdown
# Sample

Some text.

```arrow
a >>> b
```

More text.

```arr
c >>> d
```
```

- [ ] **Step 2: Add end-to-end test for literate pipeline**

This test exercises `extract` → `combine` → `Lexer` → `Parser` → `Checker` as one pipeline:

```ocaml
let test_md_literate_end_to_end () =
  let input = "# Doc\n\n```arrow\na >>> b\n```\n\nText\n\n```arr\nc >>> d\n```\n" in
  let blocks = Markdown.extract input in
  let source, _table = Markdown.combine blocks in
  let tokens = Lexer.tokenize source in
  let _ast = Parser.parse tokens in
  (* if we get here without exception, the pipeline works *)
  ()
```

- [ ] **Step 3: Add test for error line number translation accuracy**

```ocaml
let test_md_literate_error_line_translation () =
  (* Block starts at markdown line 4, has a lex error on its first line *)
  let input = "# Doc\n\n```arrow\n!!!\n```\n" in
  let blocks = Markdown.extract input in
  let source, table = Markdown.combine blocks in
  match Lexer.tokenize source with
  | exception Lexer.Lex_error (pos, _msg) ->
    let translated = Markdown.translate_line table pos.line in
    Alcotest.(check int) "error at markdown line 4" 4 translated
  | _ -> Alcotest.fail "expected lex error"
```

- [ ] **Step 4: Register integration tests**

Add to `markdown_tests`:

```ocaml
  ; "literate end-to-end", `Quick, test_md_literate_end_to_end
  ; "error line translation", `Quick, test_md_literate_error_line_translation
```

- [ ] **Step 5: Run tests**

Run: `dune test`
Expected: All tests pass including the 2 new integration tests.

- [ ] **Step 6: Commit**

```bash
git add test/test_compose_dsl.ml test/fixtures/sample.md
git commit -m "test: add integration tests for literate mode pipeline"
```

---

### Task 7: Update documentation

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update README.md CLI usage section**

Add literate mode to the CLI usage documentation — the `--literate` flag and a usage example:

```bash
# Check arrow blocks in a Markdown file
dune exec ocaml-compose-dsl -- --literate README.md
```

- [ ] **Step 2: Update CLAUDE.md CLI Usage section**

Update the CLI Usage section to include the `--literate` flag.

- [ ] **Step 3: Update CHANGELOG.md**

Add a new entry for the literate mode feature.

- [ ] **Step 4: Commit**

```bash
git add README.md CLAUDE.md CHANGELOG.md
git commit -m "docs: document literate mode in README, CLAUDE.md, and CHANGELOG"
```
