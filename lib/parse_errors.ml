open Ast

exception Parse_error of pos * string

let parse input =
  Lexer.validate_utf8 input;
  let buf = Sedlexing.Utf8.from_string input in
  let st = Lexer.create_state buf in
  let lexbuf = Lexing.from_string "" in
  let module I = Parser.MenhirInterpreter in
  let lexer_fn _lb =
    let (tok, s, e) = Lexer.token st in
    lexbuf.lex_start_p <- Lexer.to_lexing_position s;
    lexbuf.lex_curr_p <- Lexer.to_lexing_position e;
    tok
  in
  let supplier = I.lexer_lexbuf_to_supplier lexer_fn lexbuf in
  let checkpoint = Parser.Incremental.program lexbuf.lex_curr_p in
  let succeed v = v in
  let fail checkpoint =
    let state =
      match checkpoint with
      | I.HandlingError env -> I.current_state_number env
      | _ -> -1
    in
    let msg =
      try Parser_messages.message state
      with Not_found -> "syntax error"
    in
    let pos = Lexer.current_pos st in
    raise (Parse_error (pos, String.trim msg))
  in
  I.loop_handle succeed fail supplier checkpoint
