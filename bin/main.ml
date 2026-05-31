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
  -l, --literate         Extract and check ```arrow/```arr code blocks from Markdown
  --emit <target>        Emit output in the given format (valid: workflow)
  -o, --output <file>    Write emitted output to <file> instead of stdout
  -h, --help             Show this help message
  -v, --version          Show version

Reads from file argument or stdin.
Exits 0 with AST output (constructor-style format) on valid input, 1 with error messages.|}
    Version.value

let version_text = Printf.sprintf "ocaml-compose-dsl %s" Version.value

(* Defined first — both the dangling-value guard and consumed_indices use it. *)
let value_flags = ["--emit"; "-o"; "--output"]

(* Returns the value after `flag`, or None. Scans only 1..len-2 so a trailing
   flag (with nothing following it) returns None — the dangling-value guard
   catches that case. *)
let flag_value flag =
  let v = ref None in
  for i = 1 to Array.length Sys.argv - 2 do
    if Sys.argv.(i) = flag then v := Some Sys.argv.(i + 1)
  done;
  !v

let emit_target = flag_value "--emit"
let output_path =
  match flag_value "-o" with Some p -> Some p | None -> flag_value "--output"

(* Reject a dangling value-flag (e.g. `--emit` with no following token): flag_value
   only scans 1..len-2, so without this guard a trailing --emit would be silently
   ignored and fall back to default AST printing. *)
let () =
  let n = Array.length Sys.argv in
  if n >= 2 && List.mem Sys.argv.(n - 1) value_flags then begin
    Printf.eprintf "missing value for %s\n" Sys.argv.(n - 1); exit 1
  end

(* Indices consumed by value-flag + value-token pairs: both the flag token at i
   and its value token at i+1 are marked. first_positional_arg and
   first_unknown_flag skip these indices so they are invisible to positional/
   unknown detection. *)
let consumed_indices =
  let s = Hashtbl.create 8 in
  for i = 1 to Array.length Sys.argv - 1 do
    if List.mem Sys.argv.(i) value_flags && i + 1 < Array.length Sys.argv then begin
      Hashtbl.replace s i ();       (* the flag itself *)
      Hashtbl.replace s (i + 1) ()  (* its value token *)
    end
  done;
  s

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
       && not (Hashtbl.mem consumed_indices i)
       && String.length a > 0
       && a.[0] = '-'
       && a <> "--help" && a <> "-h"
       && a <> "--version" && a <> "-v"
       && a <> "--literate" && a <> "-l"
       && a <> "--emit"
       && a <> "-o" && a <> "--output"
    then result := Some a
  done;
  !result

let first_positional_arg () =
  let result = ref None in
  for i = 1 to Array.length Sys.argv - 1 do
    let a = Sys.argv.(i) in
    if !result = None
       && not (Hashtbl.mem consumed_indices i)
       && (String.length a = 0 || a.[0] <> '-') then
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
      (match emit_target with
       | None ->
         let output = Compose_dsl.Printer.program_to_string prog in
         if output <> "" then print_endline output
       | Some "workflow" ->
         let module C = Compose_dsl.Wf_context in
         (* Node comments come from the Arrow source (`source`); the file header/description
            come from -- comments (standard mode) or the surrounding Markdown prose (literate
            mode — `input` is the ORIGINAL text, before combine() discarded the prose). *)
         let comments = C.comments_of_source source in
         let name = C.derive_name ~path:(first_positional_arg ()) in
         let header, description =
           if literate then
             let prose = C.markdown_prose input in
             prose, (match prose with d :: _ -> Some d | [] -> None)
           else
             C.leading_block comments,
             Some (C.derive_description (List.map snd comments)
                     ~fallback:("Generated from " ^ name)
                   )
         in
         (match Compose_dsl.Wf_lower.lower
                  ~name
                  ~comments ~header ?description prog with
          | exception Compose_dsl.Wf_ir.Emit_error (pos, msg) ->
            Printf.eprintf "emit error at %d:%d: %s\n" (tl pos.line) pos.col msg; exit 1
          | ir ->
            List.iter (fun id -> Printf.eprintf
              "warning: '%s' implies user interaction; workflows run autonomously and do not pause\n" id)
              (Compose_dsl.Wf_lower.interactive_idents ir);
            let js = Compose_dsl.Wf_emit.to_string ir in
            (match output_path with
             | Some p ->
               (match
                  let oc = open_out p in
                  Fun.protect ~finally:(fun () -> close_out oc)
                    (fun () -> output_string oc js)
                with
                | exception Sys_error msg ->
                  Printf.eprintf "error writing %s: %s\n" p msg; exit 1
                | () -> ())
             | None -> print_string js))
       | Some other ->
         Printf.eprintf "unknown --emit target: %s (valid: workflow)\n" other; exit 1);
      exit 0
