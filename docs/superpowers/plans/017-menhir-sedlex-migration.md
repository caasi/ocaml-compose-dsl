# Menhir + Sedlex Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace hand-written lexer and parser with sedlex PPX lexer and Menhir grammar file to eliminate EBNF-implementation divergence.

**Architecture:** The pipeline shape (String → Lexer → Parser → AST → Reducer → Checker) is preserved. The lexer becomes a sedlex PPX file; the parser becomes a `.mly` grammar file. Token types move from `Lexer` module to Menhir-generated `Parser` module. The lexer shifts from batch (produces `token list`) to pull-based (parser calls lexer on demand). Menhir entry point is `Parser.program` (generated from `%start program`). The `--table` backend is used for `.messages` error reporting support.

**Tech Stack:** OCaml 5.1, Menhir (parser generator, `--table` backend), sedlex (PPX lexer generator), dune 3.0

**Spec:** `docs/superpowers/specs/2026-03-28-menhir-sedlex-migration-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `dune-project` | Modify | Add `(using menhir 2.1)`, add `menhir`/`sedlex` deps to packages |
| `lib/dune` | Modify | Add libraries, PPX preprocess, menhir stanza |
| `lib/lexer.ml` | Rewrite | Sedlex PPX lexer with location adapter |
| `lib/parser.mly` | Create | Menhir grammar (replaces `lib/parser.ml`) |
| `lib/parser.ml` | Delete | Replaced by Menhir-generated code |
| `lib/compose_dsl.ml` | Modify | Adapt to new parser/lexer API |
| `bin/main.ml` | Modify | Adapt error handling to new exception types |
| `test/helpers.ml` | Modify | Update `parse_ok`, `parse_fails`, `reduce_ok` to new API |
| `test/test_lexer.ml` | Modify | Update token references (`Lexer.X` → `Parser.X` if needed) |
| `test/test_parser.ml` | Modify | Update ~17 direct `Lexer.tokenize |> Parser.parse_program` calls, error exception types |
| `test/test_integration.ml` | Modify | Update 4 direct `Lexer.tokenize` + `Parser.parse_program` call sites |

---

## Key Design Decisions

**Entry point name:** Menhir generates `Parser.program` from `%start program`. All callers must use `Parser.program`, not the old `Parser.parse_program`.

**Menhir adapter pattern:** With `--table`, Menhir generates a traditional `(Lexing.lexbuf -> token) * Lexing.lexbuf -> ast` interface. The adapter uses a dummy `Lexing.lexbuf` since sedlex manages its own buffer:

```ocaml
let parse input =
  let buf = Sedlexing.Utf8.from_string input in
  let st = Lexer.create_state buf in
  let lexbuf = Lexing.from_string "" in  (* dummy, not used by sedlex *)
  Parser.program (fun _lb ->
    let (tok, s, e) = Lexer.token st in
    lexbuf.lex_start_p <- Lexer.to_lexing_position s;
    lexbuf.lex_curr_p <- Lexer.to_lexing_position e;
    tok
  ) lexbuf
```

**Ident vs `->` conflict with sedlex:** Sedlex uses longest-match, so `ident_start, Star ident_char` could match past `-` into `->`. The ident_char class **excludes `-`** when followed by `>`. However, sedlex doesn't support lookahead. The approach is: keep `-` in `ident_char`, but after matching an ident, check if the lexeme ends with `-` and the next character is `>`. If so, rollback one character and re-match. **Fallback:** If sedlex's behavior doesn't cooperate, exclude `-` from `ident_char` entirely and handle hyphenated identifiers via a post-match concatenation loop (match ident, if next char is `-` and next-next is not `>`, append and continue).

**Error message tests temporarily weakened:** These tests assert on specific `Parser.Parse_error` messages. They are weakened to just check `Parser.Error` in Task 4, then restored in Task 6 with Menhir `.messages`:
- `test_parse_error_unclosed_paren` (asserts error mentions `)`)
- `test_parse_trailing_comma_args` (asserts `trailing comma`)
- `test_parse_let_error_no_body` (asserts `in`)
- `test_parse_let_old_syntax_error` (asserts `Hint:`)
- `test_parse_in_as_term_error` (asserts `reserved keyword`)
- `test_parse_type_ann_incomplete_error` (asserts `->`)
- `test_parse_type_ann_missing_output_error` (asserts `->`)
- `test_parse_lambda_duplicate_params` (asserts `duplicate` — this one stays via semantic action, not `.messages`)

**Direct `Lexer.tokenize |> Parser.parse_program` calls in tests** (must all be updated):
- `test/helpers.ml`: `parse_ok` (line 3-5), `reduce_ok` (line 43-46)
- `test/test_parser.ml`: lines 478, 491, 504, 517, 529, 537, 544, 600, 608, 614, 621, 634, 641, 649, 655, 661, 665
- `test/test_integration.ml`: lines 7-8, 15-16, 91-92

---

## Task 1: Build System Setup

**Files:**
- Modify: `dune-project`
- Modify: `lib/dune`

- [ ] **Step 1: Install opam packages**

```bash
opam install menhir sedlex
```

- [ ] **Step 2: Add Menhir plugin to `dune-project`**

Add `(using menhir 2.1)` after the `(lang dune 3.0)` line. Add `menhir` and `sedlex` to the `ocaml-compose-dsl-lib` package depends:

```diff
 (lang dune 3.0)
+(using menhir 2.1)

 ...

 (package
  (name ocaml-compose-dsl-lib)
  (synopsis "Library for ocaml-compose-dsl")
  (depends
   (ocaml (>= 5.1))
   dune
+  menhir
+  sedlex
   (alcotest :with-test)))
```

- [ ] **Step 3: Update `lib/dune`**

Replace the current `lib/dune` contents with:

```sexp
(library
 (name compose_dsl)
 (public_name ocaml-compose-dsl-lib)
 (libraries menhirLib sedlex)
 (preprocess (pps sedlex.ppx)))

(menhir
 (modules parser)
 (flags --table))
```

The `--table` flag enables Menhir's table backend (required for `.messages` error reporting in Task 6).

- [ ] **Step 4: Verify the build system accepts the config**

Don't expect a successful build yet (parser.mly doesn't exist), but verify dune doesn't reject the config:

```bash
dune build 2>&1 | head --lines=20
```

Expected: error about missing `parser.mly`, NOT about invalid dune config.

- [ ] **Step 5: Commit**

```bash
git add dune-project lib/dune
git commit -m "build: add menhir and sedlex dependencies"
```

---

## Task 2: Menhir Grammar Skeleton (All Tokens)

**Files:**
- Create: `lib/parser.mly`
- Delete: `lib/parser.ml`

Create a `.mly` with ALL token declarations and a minimal grammar. This ensures the `Parser` module defines all token constructors that the sedlex lexer (Task 3) will reference.

- [ ] **Step 1: Remove old `lib/parser.ml`**

```bash
git rm lib/parser.ml
```

- [ ] **Step 2: Create `lib/parser.mly` with all tokens**

The skeleton must declare every `%token` that the final grammar will use, so that `Parser.SEQ`, `Parser.IDENT`, etc. all exist for the lexer module.

```menhir
%{
open Ast

let mk_expr (startpos, endpos) desc : expr =
  let pos_of (p : Lexing.position) : Ast.pos =
    { line = p.pos_lnum; col = p.pos_cnum - p.pos_bol + 1 }
  in
  { loc = { start = pos_of startpos; end_ = pos_of endpos };
    desc;
    type_ann = None }
%}

%token <string> IDENT STRING NUMBER COMMENT
%token SEQ PAR FANOUT ALT ARROW DOUBLE_COLON
%token LET IN LOOP
%token LPAREN RPAREN LBRACKET RBRACKET
%token COMMA COLON EQUALS BACKSLASH QUESTION
%token EOF

%start <Ast.expr> program

%%

program:
  | e=program_inner EOF  { e }
;

program_inner:
  | e=seq_expr  { e }
;

seq_expr:
  | e=term  { e }
;

term:
  | name=IDENT
    { mk_expr ($startpos, $endpos) (Var name) }
;
```

- [ ] **Step 3: Verify the build compiles**

```bash
dune build
```

Expected: compiles successfully. Tests will fail (parser only accepts bare IDENT), but the `Parser` module exists with all token constructors.

- [ ] **Step 4: Commit**

```bash
git add lib/parser.mly
git commit -m "build: add Menhir grammar skeleton with all token declarations"
```

---

## Task 3: Sedlex Lexer

**Files:**
- Rewrite: `lib/lexer.ml`

Replace the hand-written lexer with a sedlex PPX lexer. The new lexer uses `Parser.token` constructors from the Menhir-generated module, preserves codepoint-based location tracking, and maintains the `tokenize` function for test compatibility.

- [ ] **Step 1: Write the sedlex lexer**

Rewrite `lib/lexer.ml` entirely. Key design:

```ocaml
open Ast

exception Lex_error of pos * string

(* Re-export token type for backward compat in tests *)
type token = Parser.token

(* Preserved for test compatibility *)
type located = { token : token; loc : loc }

(* --- Sedlex character class definitions --- *)
(* ident_start: any codepoint EXCEPT digits, whitespace, ASCII specials, and '-' *)
let ident_start = [%sedlex.regexp?
  Sub(any,
    ('0'..'9'
    | Chars "()[]:<>,>*|&\".!#$%^+={};<>'`~/\\?@ \t\n\r\x0b\x0c-"))]

(* ident_char: same as ident_start but allows digits and '-' *)
let ident_char = [%sedlex.regexp?
  Sub(any,
    (Chars "()[]:<>,>*|&\".!#$%^+={};<>'`~/\\?@ \t\n\r\x0b\x0c"))]

let digit = [%sedlex.regexp? '0'..'9']
let white_space = [%sedlex.regexp? ' ' | '\t' | '\n' | '\r' | '\x0b' | '\x0c']

(* --- Location tracking (codepoint-based) --- *)

type lexer_state = {
  buf : Sedlexing.lexbuf;
  mutable line : int;
  mutable line_start_codepoint : int;
}

let create_state buf = {
  buf;
  line = 1;
  line_start_codepoint = 0;
}

let current_pos st =
  let cp_offset = Sedlexing.lexeme_start st.buf in
  { line = st.line; col = cp_offset - st.line_start_codepoint + 1 }

let end_pos st =
  let cp_offset = Sedlexing.lexeme_end st.buf in
  { line = st.line; col = cp_offset - st.line_start_codepoint + 1 }

(* Scan lexeme for newlines, updating line/col state.
   Must be called BEFORE end_pos for tokens spanning newlines. *)
let update_newlines st =
  let lexeme = Sedlexing.lexeme st.buf in
  let start_cp = Sedlexing.lexeme_start st.buf in
  Array.iteri (fun i cp ->
    if Uchar.to_int cp = Char.code '\n' then begin
      st.line <- st.line + 1;
      st.line_start_codepoint <- start_cp + i + 1
    end
  ) lexeme

let to_lexing_position (pos : Ast.pos) : Lexing.position =
  { pos_fname = "";
    pos_lnum = pos.line;
    pos_bol = 0;
    pos_cnum = pos.col - 1 }

(* Strip leading whitespace after -- *)
let strip_comment_prefix s =
  let len = String.length s in
  let i = ref 2 in
  while !i < len && (s.[!i] = ' ' || s.[!i] = '\t') do incr i done;
  String.sub s !i (len - !i)

(* --- Main token function --- *)

let rec token st =
  let buf = st.buf in
  let start = current_pos st in
  match%sedlex buf with
  | ">>>"  -> (Parser.SEQ, start, end_pos st)
  | "***"  -> (Parser.PAR, start, end_pos st)
  | "&&&"  -> (Parser.FANOUT, start, end_pos st)
  | "|||"  -> (Parser.ALT, start, end_pos st)
  | "->"   -> (Parser.ARROW, start, end_pos st)
  | "::"   -> (Parser.DOUBLE_COLON, start, end_pos st)
  | "--", Star (Compl '\n') ->
    let s = Sedlexing.Utf8.lexeme buf in
    let body = strip_comment_prefix s in
    (Parser.COMMENT body, start, end_pos st)
  | '('  -> (Parser.LPAREN, start, end_pos st)
  | ')'  -> (Parser.RPAREN, start, end_pos st)
  | '['  -> (Parser.LBRACKET, start, end_pos st)
  | ']'  -> (Parser.RBRACKET, start, end_pos st)
  | ':'  -> (Parser.COLON, start, end_pos st)
  | ','  -> (Parser.COMMA, start, end_pos st)
  | '='  -> (Parser.EQUALS, start, end_pos st)
  | '?'  -> (Parser.QUESTION, start, end_pos st)
  | '\\' -> (Parser.BACKSLASH, start, end_pos st)
  | '"', Star (Compl '"'), '"' ->
    let s = Sedlexing.Utf8.lexeme buf in
    (* Strip surrounding quotes *)
    let body = String.sub s 1 (String.length s - 2) in
    (Parser.STRING body, start, end_pos st)
  | '"', Star (Compl ('"' | '\n')) ->
    (* Unterminated string: opening quote with no closing quote before newline/eof *)
    raise (Lex_error (start, "unterminated string"))
  | Opt '-', Plus digit, Opt ('.', Plus digit), Opt (ident_start, Star ident_char) ->
    (Parser.NUMBER (Sedlexing.Utf8.lexeme buf), start, end_pos st)
  | ident_start, Star ident_char ->
    let s = Sedlexing.Utf8.lexeme buf in
    let tok = match s with
      | "let" -> Parser.LET
      | "loop" -> Parser.LOOP
      | "in" -> Parser.IN
      | _ -> Parser.IDENT s
    in
    (tok, start, end_pos st)
  | Plus white_space ->
    update_newlines st;
    token st
  | eof -> (Parser.EOF, start, start)
  | any ->
    let s = Sedlexing.Utf8.lexeme buf in
    raise (Lex_error (start, Printf.sprintf "unexpected character '%s'" s))
  | _ ->
    raise (Lex_error (start, "invalid UTF-8 byte sequence"))

(* --- Batch tokenize for backward compat / tests --- *)

let tokenize input =
  let buf = Sedlexing.Utf8.from_string input in
  let st = create_state buf in
  let tokens = ref [] in
  let rec go () =
    let (tok, start_pos, end_p) = token st in
    tokens := { token = tok; loc = { start = start_pos; end_ = end_p } } :: !tokens;
    match tok with
    | Parser.EOF -> ()
    | _ -> go ()
  in
  go ();
  List.rev !tokens
```

**Critical implementation notes:**

1. **`ident_start` excludes `'0'..'9'`** (all digits), NOT `ascii_hex_digit`. Using `ascii_hex_digit` would wrongly exclude `a-f`/`A-F` from identifiers.

2. **Keyword handling** uses the ident-then-match approach: sedlex matches `ident_start, Star ident_char` as the longest match, then a post-match `match s with "let" | "loop" | "in" -> ...` converts keywords. This matches the current lexer's `read_ident` strategy and correctly handles `"letter"` (→ IDENT) vs `"let"` (→ LET).

3. **`->` vs hyphenated idents**: If sedlex's longest match for `ident_char` consumes past `-` into `->` (e.g., matching `my-node->` as one ident), the fallback is:
   - After matching an ident, check if the lexeme contains `->` as a substring.
   - If so, split: emit the part before `->` as IDENT, then rollback the buffer to re-lex `->` as ARROW.
   - Alternatively, exclude `-` from `ident_char` and handle hyphenated idents via a loop: match ident, if next char is `-` and char after is not `>`, consume `-` and append the next ident segment.

4. **Newline tracking**: `update_newlines` scans the lexeme array (Uchar array from sedlex) using `Array.iteri`. The codepoint index `i` within the lexeme plus `Sedlexing.lexeme_start` gives the absolute codepoint offset of each newline. `line_start_codepoint` is set to `start_cp + i + 1` (the codepoint after the newline). This is called only in the whitespace branch, since no other token spans newlines (strings are single-line in this DSL).

5. **Unterminated string detection**: The rule `'"', Star (Compl ('"' | '\n'))` matches an opening quote followed by non-quote, non-newline chars without a closing quote. It must be placed AFTER the complete string rule.

- [ ] **Step 2: Verify the lexer compiles**

```bash
dune build
```

Expected: compiles. Tests won't all pass yet.

- [ ] **Step 3: Run lexer tests**

```bash
dune exec test/main.exe -- test Lexer
```

Expected: most tests pass. Token constructor re-exports (`type token = Parser.token`) should let `Lexer.IDENT`, `Lexer.SEQ` etc. continue to work in pattern matches. If OCaml doesn't propagate constructors through type aliases, all test token references must be updated to `Parser.X`.

- [ ] **Step 4: Fix lexer test failures iteratively**

Common issues:
- Sedlex character class needs adjustment (especially ident boundaries)
- Location tracking off-by-one (codepoint vs byte confusion)
- `-` in ident vs `->` priority (see fallback in note 3)
- Comment whitespace stripping
- Error message string differences (e.g., `'@'` vs `@` in unexpected character)

- [ ] **Step 5: Verify all lexer tests pass**

```bash
dune exec test/main.exe -- test Lexer
```

Expected: all 55 lexer tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/lexer.ml
git commit -m "feat: replace hand-written lexer with sedlex PPX"
```

---

## Task 4: Full Menhir Grammar

**Files:**
- Modify: `lib/parser.mly`
- Modify: `test/helpers.ml`
- Modify: `test/test_parser.ml`
- Modify: `test/test_integration.ml`

Expand the skeleton grammar to the full language and update all test call sites.

- [ ] **Step 1: Write the full grammar**

Replace the skeleton `lib/parser.mly` with the complete grammar. The full `.mly` content is in the spec (lines 93-184), with these additions:

**Header section:**

```menhir
%{
open Ast

let mk_expr (startpos, endpos) desc : expr =
  let pos_of (p : Lexing.position) : Ast.pos =
    { line = p.pos_lnum; col = p.pos_cnum - p.pos_bol + 1 }
  in
  { loc = { start = pos_of startpos; end_ = pos_of endpos };
    desc;
    type_ann = None }

exception Duplicate_param of Ast.pos * string
%}
```

**Lambda duplicate param check** (in the `term` rule's lambda branch):

```menhir
  | BACKSLASH params=lambda_params ARROW body=seq_expr
    { let seen = Hashtbl.create 4 in
      List.iter (fun p ->
        if Hashtbl.mem seen p then
          raise (Duplicate_param (pos_of $startpos, Printf.sprintf "duplicate parameter '%s' in lambda" p));
        Hashtbl.replace seen p ()
      ) params;
      mk_expr $loc (Lambda (params, body)) }
```

**Complete production list** (from spec, all fixes applied):
- `program` / `program_inner` split (avoids EOF in groups)
- `loption(call_args)` for empty arg lists (`noop()`)
- Inlined `arg_key` into `call_arg` (avoids reduce/reduce conflict)
- `($loc(name))` properly parenthesized

- [ ] **Step 2: Verify it compiles without conflicts**

```bash
dune build 2>&1
```

Expected: compiles with zero conflicts. If conflicts:

```bash
menhir --explain lib/parser.mly
cat lib/parser.conflicts
```

- [ ] **Step 3: Update `test/helpers.ml`**

Update ALL functions that call `Lexer.tokenize` + `Parser.parse_program`:

```ocaml
open Compose_dsl

let parse_ok input =
  let buf = Sedlexing.Utf8.from_string input in
  let st = Lexer.create_state buf in
  let lexbuf = Lexing.from_string "" in
  Parser.program (fun _lb ->
    let (tok, s, e) = Lexer.token st in
    lexbuf.lex_start_p <- Lexer.to_lexing_position s;
    lexbuf.lex_curr_p <- Lexer.to_lexing_position e;
    tok
  ) lexbuf

let desc_of input = (parse_ok input).desc

let parse_fails input =
  match parse_ok input with
  | _ -> Alcotest.fail "expected parse error"
  | exception Parser.Error -> ()
  | exception Lexer.Lex_error _ -> ()
  | exception Parser.Duplicate_param _ -> ()

(* ... check_ok, check_ok_with_warnings, contains remain unchanged ... *)

let reduce_ok input =
  let ast = parse_ok input in
  Reducer.reduce ast

let reduce_fails input =
  match reduce_ok input with
  | _ -> Alcotest.fail "expected reduce error"
  | exception Reducer.Reduce_error _ -> ()
```

- [ ] **Step 4: Update direct calls in `test/test_parser.ml`**

~17 tests bypass `parse_ok` and call `Lexer.tokenize |> Parser.parse_program` directly. These are mostly error-case tests. Update each one:

**Pattern:** Replace:
```ocaml
match Lexer.tokenize "input" |> Parser.parse_program with
| _ -> Alcotest.fail "..."
| exception Parser.Parse_error (_, msg) -> ...
```

With:
```ocaml
match parse_ok "input" with
| _ -> Alcotest.fail "..."
| exception Parser.Error -> ...
```

**Tests that assert on error message content** (temporarily weakened — tracked for Task 6):
- `test_parse_error_unclosed_paren` → just check `Parser.Error`
- `test_parse_trailing_comma_args` → just check `Parser.Error`
- `test_parse_let_error_no_body` → just check `Parser.Error`
- `test_parse_let_old_syntax_error` → just check `Parser.Error`
- `test_parse_in_as_term_error` → just check `Parser.Error`
- `test_parse_type_ann_incomplete_error` → just check `Parser.Error`
- `test_parse_type_ann_missing_output_error` → just check `Parser.Error`

**Test that keeps its message assertion** (via semantic action exception):
- `test_parse_lambda_duplicate_params` → catch `Parser.Duplicate_param (_, msg)`, assert `contains msg "duplicate"`

- [ ] **Step 5: Update `test/test_integration.ml`**

Update 4 call sites (lines 7-8, 15-16, 91-92 and any others using `Lexer.tokenize` + `Parser.parse_program`) to use `parse_ok` instead.

- [ ] **Step 6: Run all tests**

```bash
dune test
```

Iterate on failures. Expected categories:
- **Location mismatches**: Menhir `$loc` computes positions via `Lexing.position`. Ensure the sedlex adapter populates `lexbuf.lex_start_p` / `lex_curr_p` correctly so `$loc` produces the right values.
- **Comment tests**: Should pass — comments are skipped by the lexer, and existing tests only assert on AST structure, not comment content.
- **`let` in lambda body / positional arg**: `\x -> let y = x in y` should still be a parse error because lambda body is `seq_expr` which doesn't include `let`. `f(let x = a in x)` should fail because positional `call_arg` goes to `seq_expr`. But `f((let x = a in x))` should succeed because the parens trigger `program_inner`. Verify these edge cases.

- [ ] **Step 7: Verify all tests pass**

```bash
dune test
```

Expected: all suites pass (Lexer, Parser, Edge cases, Checker, Printer, Reducer, Integration, Mixed args, Markdown, Markdown integration).

- [ ] **Step 8: Commit**

```bash
git add lib/parser.mly test/helpers.ml test/test_parser.ml test/test_integration.ml
git commit -m "feat: replace hand-written parser with Menhir grammar"
```

---

## Task 5: Integration Wiring

**Files:**
- Modify: `lib/compose_dsl.ml`
- Modify: `bin/main.ml`

Wire the new parser and lexer into the main executable.

- [ ] **Step 1: Verify `lib/compose_dsl.ml` compiles**

The module re-exports should work since Menhir generates `Parser` module:

```ocaml
module Ast = Ast
module Lexer = Lexer
module Parser = Parser  (* now Menhir-generated *)
module Checker = Checker
module Printer = Printer
module Reducer = Reducer
module Markdown = Markdown
```

Verify: `dune build`

- [ ] **Step 2: Update `bin/main.ml`**

Replace the lexer+parser invocation (current lines 93-101) with:

```ocaml
  let buf = Sedlexing.Utf8.from_string source in
  let st = Compose_dsl.Lexer.create_state buf in
  let lexbuf = Lexing.from_string "" in
  let parse () =
    Compose_dsl.Parser.program (fun _lb ->
      let (tok, s, e) = Compose_dsl.Lexer.token st in
      lexbuf.lex_start_p <- Compose_dsl.Lexer.to_lexing_position s;
      lexbuf.lex_curr_p <- Compose_dsl.Lexer.to_lexing_position e;
      tok
    ) lexbuf
  in
  match parse () with
  | exception Compose_dsl.Lexer.Lex_error (pos, msg) ->
    Printf.eprintf "lex error at %d:%d: %s\n" (tl pos.line) pos.col msg;
    exit 1
  | exception Compose_dsl.Parser.Error ->
    let pos = Compose_dsl.Lexer.current_pos st in
    Printf.eprintf "parse error at %d:%d: syntax error\n" (tl pos.line) pos.col;
    exit 1
  | exception Compose_dsl.Parser.Duplicate_param (pos, msg) ->
    Printf.eprintf "parse error at %d:%d: %s\n" (tl pos.line) pos.col msg;
    exit 1
  | ast -> ...
```

- [ ] **Step 3: Run full test suite**

```bash
dune test
```

Expected: all tests pass.

- [ ] **Step 4: Verify CLI works end-to-end**

```bash
echo 'a >>> b' | dune exec ocaml-compose-dsl
echo 'let f = \x -> x >>> a in f(b)' | dune exec ocaml-compose-dsl
dune exec ocaml-compose-dsl -- --literate CLAUDE.md
```

Expected: valid AST output for each.

- [ ] **Step 5: Commit**

```bash
git add lib/compose_dsl.ml bin/main.ml
git commit -m "feat: wire sedlex+menhir into main executable"
```

---

## Task 6: Menhir Error Messages

**Files:**
- Create: `lib/parser.messages`
- Modify: `lib/dune`
- Modify: `test/test_parser.ml`

Restore custom error messages lost in the migration.

- [ ] **Step 1: Generate error state template**

```bash
menhir --list-errors lib/parser.mly > lib/parser.messages
```

This produces all reachable error states.

- [ ] **Step 2: Add custom messages**

Edit `lib/parser.messages` to add messages for key error states:

| Error state | Message |
|------------|---------|
| After `IDENT LPAREN call_args COMMA` expecting more args, got `RPAREN` | `unexpected trailing comma in argument list` |
| In `call_args`/`term` expecting `,` or `)` | `expected ',' or ')'` |
| After `LET IDENT EQUALS seq_expr` expecting `IN` | `expected 'in' after let binding value` |
| `IN` in `term` position | `'in' is a reserved keyword and cannot be used as an identifier` |
| In `term` position, unexpected token | `expected identifier, string, '(', 'loop', or '\' (lambda)` |
| After `LPAREN program_inner` expecting `)` | `expected ')'` |
| After `LOOP LPAREN seq_expr` expecting `)` | `expected ')' to close 'loop'` |
| After `DOUBLE_COLON IDENT` expecting `ARROW` | `expected '->' in type annotation` |
| After `DOUBLE_COLON IDENT ARROW` expecting `IDENT` | `expected type name after '->'` |

- [ ] **Step 3: Wire `.messages` into build**

Update `lib/dune`:

```sexp
(menhir
 (modules parser)
 (flags --table --compile-errors lib/parser.messages))
```

Verify: `dune build`

- [ ] **Step 4: Restore error message assertions in tests**

Re-strengthen the 7 weakened tests. Menhir with `--compile-errors` generates a `parser_messages.ml` (or embeds messages). The error extraction pattern depends on the Menhir API:

```ocaml
(* Extract message from Menhir error state *)
| exception Parser.Error ->
  (* With --compile-errors, the error message is accessible via
     the generated message function. The exact API depends on
     Menhir version and integration approach. *)
  ...
```

Each test restores its original assertion (e.g., `contains msg ")"`, `contains msg "trailing comma"`).

- [ ] **Step 5: Run tests**

```bash
dune test
```

Expected: all tests pass with restored error message assertions.

- [ ] **Step 6: Commit**

```bash
git add lib/parser.messages lib/dune test/test_parser.ml
git commit -m "feat: add Menhir custom error messages"
```

---

## Task 7: New Regression Tests

**Files:**
- Modify: `test/test_parser.ml`

Add tests from the spec to cover migration edge cases.

- [ ] **Step 1: Verify `noop()` test exists and passes**

Already exists: `test_parse_node_empty_parens` at `test/test_parser.ml:16-19`.

```bash
dune exec test/main.exe -- test Parser 2
```

Expected: PASS.

- [ ] **Step 2: Add `(let x = a in x)` test**

```ocaml
let test_parse_group_with_let () =
  let ast = parse_ok "(let x = a in x)" in
  match ast.desc with
  | Ast.Group { desc = Ast.Let ("x", { desc = Ast.Var "a"; _ }, { desc = Ast.Var "x"; _ }); _ } -> ()
  | _ -> Alcotest.fail "expected Group(Let(x, a, x))"
```

Add to `tests` list.

- [ ] **Step 3: Verify `let` is still invalid in lambda body and positional args**

Verify these existing tests pass:
- `test_parse_let_in_lambda_body_error` — `\x -> let y = x in y` → error
- `test_parse_let_in_positional_arg_error` — `f(let x = a in x)` → error

```bash
dune exec test/main.exe -- test "Edge cases" 9
dune exec test/main.exe -- test "Edge cases" 10
```

Expected: both PASS.

- [ ] **Step 4: Run full test suite**

```bash
dune test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add test/test_parser.ml
git commit -m "test: add group-with-let regression test for Menhir migration"
```

---

## Task 8: Cleanup and Final Verification

**Files:**
- Possibly modify: various

- [ ] **Step 1: Run full test suite**

```bash
dune test
```

Expected: 0 failures.

- [ ] **Step 2: Verify opam file regeneration**

```bash
dune build
git diff *.opam
```

Stage and commit if opam files changed (they should now include menhir/sedlex deps).

- [ ] **Step 3: Verify `.mly` productions match README EBNF**

Manual check:

| EBNF | `.mly` |
|------|--------|
| `program` | `program` + `program_inner` |
| `pipeline` | (elided, `seq_expr` used directly) |
| `seq_expr` | `seq_expr` |
| `alt_expr` | `alt_expr` |
| `par_expr` | `par_expr` |
| `typed_term` | `typed_term` |
| `type_expr` | (inlined into `typed_term`) |
| `term` | `term` |
| `lambda` | (inlined into `term`) |
| `call_args` | `call_args` |
| `call_arg` | `call_arg` |
| `arg_key` | (inlined into `call_arg`) |
| `value` | `value` |
| `lambda_params` | `lambda_params` |

- [ ] **Step 4: Verify CLI end-to-end**

```bash
echo 'a >>> b' | dune exec ocaml-compose-dsl
echo 'noop()' | dune exec ocaml-compose-dsl
echo '(let x = a in x)' | dune exec ocaml-compose-dsl
echo 'let f = \x -> x >>> a in f(b)' | dune exec ocaml-compose-dsl
dune exec ocaml-compose-dsl -- --literate CLAUDE.md
dune exec ocaml-compose-dsl -- --literate README.md
```

Expected: valid AST output for all.

- [ ] **Step 5: Commit any remaining changes**

```bash
git add --all
git commit -m "chore: cleanup after menhir+sedlex migration"
```
