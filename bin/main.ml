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

let () =
  let input =
    if Array.length Sys.argv > 1 then read_file Sys.argv.(1)
    else read_all_stdin ()
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
