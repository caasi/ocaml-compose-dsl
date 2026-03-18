# CLI `--help` and `--version` Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `--help` / `-h` and `--version` / `-v` flags to the CLI with hand-written argument handling and build-time version injection.

**Architecture:** A dune rule generates `version.ml` from `dune-project`'s version field. `main.ml` scans all of `Sys.argv` for known flags before falling through to existing stdin/file logic. Unknown flags print an error with usage.

**Tech Stack:** OCaml, dune build system

**Spec:** `docs/superpowers/specs/2026-03-19-cli-help-version-design.md`

---

## Chunk 1: Version injection and help/version output

### Task 1: Add dune rule for version.ml

**Files:**
- Modify: `bin/dune`

- [ ] **Step 1: Add version generation rule to bin/dune**

```dune
(executable
 (name main)
 (public_name ocaml-compose-dsl)
 (package ocaml-compose-dsl)
 (libraries compose_dsl))

(rule
 (target version.ml)
 (action (write-file version.ml "let value = \"%{version:ocaml-compose-dsl}\"")))
```

- [ ] **Step 2: Verify it builds**

Run: `dune build`
Expected: success, no errors

- [ ] **Step 3: Commit**

```bash
git add bin/dune
git commit -m "build: add dune rule to generate version.ml from dune-project"
```

### Task 2: Add argument handling to main.ml

**Files:**
- Modify: `bin/main.ml`

- [ ] **Step 1: Rewrite main.ml with flag scanning**

```ocaml
let read_all_stdin () =
  let buf = Buffer.create 4096 in
  (try
     while true do
       Buffer.add_char buf (input_char stdin)
     done
   with End_of_file -> ());
  Buffer.contents buf

let read_file path =
  let ic = open_in path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  s

let usage_text =
  Printf.sprintf
    {|ocaml-compose-dsl %s
A structural checker for Arrow-style DSL pipelines.

Usage:
  ocaml-compose-dsl [<file>]
  cat <file> | ocaml-compose-dsl
  ocaml-compose-dsl --help
  ocaml-compose-dsl --version

Options:
  -h, --help     Show this help message
  -v, --version  Show version

Reads from file argument or stdin.
Exits 0 with "OK" on valid input, 1 with error messages.|}
    Version.value

let version_text = Printf.sprintf "ocaml-compose-dsl %s" Version.value

let argv_has flag =
  let found = ref false in
  for i = 1 to Array.length Sys.argv - 1 do
    if Sys.argv.(i) = flag then found := true
  done;
  !found

let first_unknown_flag () =
  let result = ref None in
  for i = 1 to Array.length Sys.argv - 1 do
    let a = Sys.argv.(i) in
    if !result = None
       && String.length a > 0
       && a.[0] = '-'
       && a <> "--help" && a <> "-h"
       && a <> "--version" && a <> "-v"
    then result := Some a
  done;
  !result

let first_positional_arg () =
  let result = ref None in
  for i = 1 to Array.length Sys.argv - 1 do
    let a = Sys.argv.(i) in
    if !result = None && (String.length a = 0 || a.[0] <> '-') then
      result := Some a
  done;
  !result

let () =
  if argv_has "--help" || argv_has "-h" then (
    print_endline usage_text;
    exit 0);
  if argv_has "--version" || argv_has "-v" then (
    print_endline version_text;
    exit 0);
  (match first_unknown_flag () with
   | Some flag ->
     Printf.eprintf "unknown option: %s\n%s\n" flag usage_text;
     exit 1
   | None -> ());
  let input =
    match first_positional_arg () with
    | Some path -> read_file path
    | None -> read_all_stdin ()
  in
  match Compose_dsl.Lexer.tokenize input with
  | exception Compose_dsl.Lexer.Lex_error (pos, msg) ->
    Printf.eprintf "lex error at %d:%d: %s\n" pos.line pos.col msg;
    exit 1
  | tokens ->
    match Compose_dsl.Parser.parse tokens with
    | exception Compose_dsl.Parser.Parse_error (pos, msg) ->
      Printf.eprintf "parse error at %d:%d: %s\n" pos.line pos.col msg;
      exit 1
    | ast ->
      let errors = Compose_dsl.Checker.check ast in
      if errors = [] then (
        print_endline "OK";
        exit 0)
      else (
        List.iter
          (fun (e : Compose_dsl.Checker.error) ->
            Printf.eprintf "check error: %s\n" e.message)
          errors;
        exit 1)
```

- [ ] **Step 2: Verify it builds**

Run: `dune build`
Expected: success

- [ ] **Step 3: Verify existing tests still pass**

Run: `dune test`
Expected: all tests pass

- [ ] **Step 4: Commit**

```bash
git add bin/main.ml
git commit -m "feat: add --help and --version flags to CLI"
```

## Chunk 2: Manual verification and docs

### Task 3: Manual smoke test

- [ ] **Step 1: Test --help**

Run: `dune exec ocaml-compose-dsl -- --help`
Expected: prints usage text with version number, exits 0

- [ ] **Step 2: Test -h**

Run: `dune exec ocaml-compose-dsl -- -h`
Expected: same as --help

- [ ] **Step 3: Test --version**

Run: `dune exec ocaml-compose-dsl -- --version`
Expected: prints `ocaml-compose-dsl 0.1.0`

- [ ] **Step 4: Test -v**

Run: `dune exec ocaml-compose-dsl -- -v`
Expected: same as --version

- [ ] **Step 5: Test unknown flag**

Run: `dune exec ocaml-compose-dsl -- --foo 2>&1; echo "exit: $?"`
Expected: prints `unknown option: --foo` followed by usage text to stderr, exits 1

- [ ] **Step 6: Test flag after filename**

Run: `dune exec ocaml-compose-dsl -- somefile.arr --help`
Expected: prints help (flag wins regardless of position)

- [ ] **Step 7: Test stdin still works**

Run: `echo 'a >>> b' | dune exec ocaml-compose-dsl`
Expected: prints `OK`

- [ ] **Step 8: Test file reading still works**

Run: create a temp file with `a >>> b`, run `dune exec ocaml-compose-dsl -- /tmp/test.arr`
Expected: prints `OK`

### Task 4: Update README usage section

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add --help and --version to README Usage section**

Update the Usage section in `README.md` to mention the new flags:

```markdown
## Usage

```sh
# From file
ocaml-compose-dsl pipeline.arr

# From stdin
echo 'a >>> b' | ocaml-compose-dsl

# Help and version
ocaml-compose-dsl --help
ocaml-compose-dsl --version
```
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add --help and --version to README usage section"
```
