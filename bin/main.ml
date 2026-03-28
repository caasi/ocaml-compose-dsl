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
  ocaml-compose-dsl [options] [<file>]
  cat <file> | ocaml-compose-dsl [options]

Options:
  -l, --literate  Extract and check ```arrow/```arr code blocks from Markdown
  -h, --help      Show this help message
  -v, --version   Show version

Reads from file argument or stdin.
Exits 0 with AST output (constructor-style format) on valid input, 1 with error messages.|}
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
       && a <> "--literate" && a <> "-l"
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
  match Compose_dsl.Parse_errors.parse source with
  | exception Compose_dsl.Lexer.Lex_error (pos, msg) ->
    Printf.eprintf "lex error at %d:%d: %s\n" (tl pos.line) pos.col msg;
    exit 1
  | exception Compose_dsl.Parse_errors.Parse_error (pos, msg) ->
    Printf.eprintf "parse error at %d:%d: %s\n" (tl pos.line) pos.col msg;
    exit 1
  | exception Compose_dsl.Ast.Duplicate_param (pos, msg) ->
    Printf.eprintf "parse error at %d:%d: %s\n" (tl pos.line) pos.col msg;
    exit 1
  | prog ->
      let prog = match Compose_dsl.Reducer.reduce_program prog with
        | reduced -> reduced
        | exception Compose_dsl.Reducer.Reduce_error (pos, msg) ->
          Printf.eprintf "reduce error at %d:%d: %s\n" (tl pos.line) pos.col msg;
          exit 1
      in
      let result = Compose_dsl.Checker.check_program prog in
      List.iter
        (fun (w : Compose_dsl.Checker.warning) ->
          Printf.eprintf "warning at %d:%d: %s\n" (tl w.loc.start.line) w.loc.start.col w.message)
        result.warnings;
      print_endline (Compose_dsl.Printer.program_to_string prog);
      exit 0
