open Ast

exception Parse_error of pos * string

let reserved_keyword_hint = function
  | Parser.IN -> Some "'in' is a reserved keyword and cannot be used as an identifier"
  | Parser.LET -> Some "'let' is a reserved keyword and cannot be used as an identifier"
  | Parser.LOOP -> Some "'loop' is a reserved keyword and cannot be used as an identifier"
  | _ -> None

let parse input =
  Lexer.validate_utf8 input;
  let buf = Sedlexing.Utf8.from_string input in
  let st = Lexer.create_state buf in
  let lexbuf = Lexing.from_string "" in
  let last_token = ref Parser.EOF in
  let module I = Parser.MenhirInterpreter in
  let lexer_fn _lb =
    let (tok, s, e) = Lexer.token st in
    last_token := tok;
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
    let base_msg =
      try Parser_messages.message state
      with Not_found -> "syntax error"
    in
    let trimmed = String.trim base_msg in
    let is_generic = not (try let _ = Parser_messages.message state in true
                          with Not_found -> false) in
    let msg =
      match reserved_keyword_hint !last_token with
      | Some hint when is_generic -> hint
      | _ -> trimmed
    in
    let p = lexbuf.lex_start_p in
    let pos = { line = p.pos_lnum; col = p.pos_cnum - p.pos_bol + 1 } in
    raise (Parse_error (pos, msg))
  in
  try I.loop_handle succeed fail supplier checkpoint
  with Ast.Duplicate_param (pos, msg) -> raise (Parse_error (pos, msg))
