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
      let result = Compose_dsl.Checker.check ast in
      List.iter
        (fun (w : Compose_dsl.Checker.warning) ->
          Printf.eprintf "warning at %d:%d: %s\n" w.loc.start.line w.loc.start.col w.message)
        result.warnings;
      if result.errors = [] then (
        print_endline (Compose_dsl.Printer.to_string ast);
        exit 0)
      else (
        List.iter
          (fun (e : Compose_dsl.Checker.error) ->
            Printf.eprintf "check error at %d:%d: %s\n" e.loc.start.line e.loc.start.col e.message)
          result.errors;
        exit 1)
