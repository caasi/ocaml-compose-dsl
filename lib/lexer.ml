open Ast

(* Re-export Parser.token constructors so existing code using Lexer.IDENT etc. still works *)
type token = Parser.token =
  | STRING of string
  | SEQ
  | SEMICOLON
  | RPAREN
  | RBRACKET
  | QUESTION
  | PAR
  | NUMBER of string
  | LPAREN
  | LOOP
  | LET
  | LBRACKET
  | IN
  | IDENT of string
  | FANOUT
  | EQUALS
  | EOF
  | DOUBLE_COLON
  | COMMENT of string
  | COMMA
  | COLON
  | BACKSLASH
  | ARROW
  | ALT

type located = { token : token; loc : loc }

exception Lex_error of pos * string

(* --- UTF-8 pre-validation --- *)

let validate_utf8 input =
  let len = String.length input in
  let i = ref 0 in
  let line = ref 1 in
  let col = ref 1 in
  while !i < len do
    let d = String.get_utf_8_uchar input !i in
    if not (Uchar.utf_decode_is_valid d) then
      raise (Lex_error ({ line = !line; col = !col }, "invalid UTF-8 byte sequence"));
    let n = Uchar.utf_decode_length d in
    let u = Uchar.utf_decode_uchar d in
    if Uchar.equal u (Uchar.of_char '\n') then
      (incr line; col := 1)
    else
      incr col;
    i := !i + n
  done

(* --- Sedlex character class definitions --- *)

let special_ascii = [%sedlex.regexp?
  '(' | ')' | '[' | ']' | ':' | '<' | '>' | ',' | '*' | '|' | '&'
  | '"' | '.' | '!' | '#' | '$' | '%' | '^' | '+' | '=' | '{' | '}'
  | ';' | '\'' | '`' | '~' | '/' | '\\' | '?' | '@']

let white_space = [%sedlex.regexp? ' ' | '\t' | '\n' | '\r' | 0x0b | 0x0c]

(* ident_start: excludes digits, hyphen, specials, whitespace *)
let ident_start = [%sedlex.regexp?
  Sub(any, (special_ascii | white_space | '0'..'9' | '-'))]

(* ident_cont: like ident_start but allows digits; excludes hyphen.
   Hyphens in identifiers are handled by a separate sedlex rule
   (hyphenated ident) so the DFA correctly backtracks before '->'. *)
let ident_cont = [%sedlex.regexp?
  Sub(any, (special_ascii | white_space | '-'))]

let digit = [%sedlex.regexp? '0'..'9']

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

(* Scan matched whitespace lexeme for newlines, updating line/col state. *)
let update_newlines st =
  let lexeme = Sedlexing.lexeme st.buf in
  let start_cp = Sedlexing.lexeme_start st.buf in
  Array.iteri (fun i uc ->
    if Uchar.to_int uc = 0x0a then begin
      st.line <- st.line + 1;
      st.line_start_codepoint <- start_cp + i + 1
    end
  ) lexeme

let to_lexing_position (pos : Ast.pos) : Lexing.position =
  { pos_fname = "";
    pos_lnum = pos.line;
    pos_bol = 0;
    pos_cnum = pos.col - 1 }

(* --- Helpers --- *)

(* Strip "--" prefix and leading whitespace from comment lexeme *)
let strip_comment_prefix s =
  let len = String.length s in
  let i = ref 2 in
  while !i < len && (s.[!i] = ' ' || s.[!i] = '\t') do incr i done;
  String.sub s !i (len - !i)

let finalize_keyword s =
  match s with
  | "let" -> Parser.LET
  | "loop" -> Parser.LOOP
  | "in" -> Parser.IN
  | _ -> Parser.IDENT s

(* --- Main token function (pull-based for Menhir) --- *)

(* token skips comments (for Menhir pull-based parser).
   read_token returns all tokens including COMMENT (for batch tokenize). *)
let rec token st =
  let (tok, _, _) as result = read_token st in
  match tok with
  | Parser.COMMENT _ -> token st
  | _ -> result

and read_token st =
  let buf = st.buf in
  match%sedlex buf with
  (* Multi-char operators — must precede single-char rules *)
  | ">>>" ->
    let s = current_pos st in (Parser.SEQ, s, end_pos st)
  | "***" ->
    let s = current_pos st in (Parser.PAR, s, end_pos st)
  | "&&&" ->
    let s = current_pos st in (Parser.FANOUT, s, end_pos st)
  | "|||" ->
    let s = current_pos st in (Parser.ALT, s, end_pos st)
  | "->" ->
    let s = current_pos st in (Parser.ARROW, s, end_pos st)
  | "::" ->
    let s = current_pos st in (Parser.DOUBLE_COLON, s, end_pos st)
  (* Comment: -- until end of line *)
  | "--", Star (Compl '\n') ->
    let sp = current_pos st in
    let text = strip_comment_prefix (Sedlexing.Utf8.lexeme buf) in
    (Parser.COMMENT text, sp, end_pos st)
  (* Single-char tokens *)
  | '(' -> let s = current_pos st in (Parser.LPAREN, s, end_pos st)
  | ')' -> let s = current_pos st in (Parser.RPAREN, s, end_pos st)
  | '[' -> let s = current_pos st in (Parser.LBRACKET, s, end_pos st)
  | ']' -> let s = current_pos st in (Parser.RBRACKET, s, end_pos st)
  | ':' -> let s = current_pos st in (Parser.COLON, s, end_pos st)
  | ',' -> let s = current_pos st in (Parser.COMMA, s, end_pos st)
  | '=' -> let s = current_pos st in (Parser.EQUALS, s, end_pos st)
  | '?' -> let s = current_pos st in (Parser.QUESTION, s, end_pos st)
  | '\\' -> let s = current_pos st in (Parser.BACKSLASH, s, end_pos st)
  | ';' -> let s = current_pos st in (Parser.SEMICOLON, s, end_pos st)
  (* String literal *)
  | '"', Star (Compl ('"' | '\n')), '"' ->
    let sp = current_pos st in
    let raw = Sedlexing.Utf8.lexeme buf in
    let body = String.sub raw 1 (String.length raw - 2) in
    (Parser.STRING body, sp, end_pos st)
  (* Unterminated string: opening quote with no closing quote before newline/eof *)
  | '"', Star (Compl ('"' | '\n')) ->
    raise (Lex_error (current_pos st, "unterminated string"))
  (* Float with optional unit suffix *)
  | Opt '-', Plus digit, '.', Plus digit, Opt (ident_start, Star ident_cont) ->
    let sp = current_pos st in
    (Parser.NUMBER (Sedlexing.Utf8.lexeme buf), sp, end_pos st)
  (* Integer with optional unit suffix *)
  | Opt '-', Plus digit, Opt (ident_start, Star ident_cont) ->
    let sp = current_pos st in
    (Parser.NUMBER (Sedlexing.Utf8.lexeme buf), sp, end_pos st)
  (* Number error: trailing dot with no fractional digits *)
  | Opt '-', Plus digit, '.' ->
    raise (Lex_error (current_pos st, "expected digit after '.'"))
  (* Hyphenated identifier: e.g. my-node, a-b-c, a_名前-test.
     The DFA backtracks correctly for my-node->B: the second '-' starts
     a new Plus iteration, but '>' is not ident_cont, so the DFA rolls
     back to the accepting state at "my-node". *)
  | ident_start, Star ident_cont, Plus ('-', Plus ident_cont) ->
    let sp = current_pos st in
    let s = Sedlexing.Utf8.lexeme buf in
    (finalize_keyword s, sp, end_pos st)
  (* Simple identifier *)
  | ident_start, Star ident_cont ->
    let sp = current_pos st in
    let s = Sedlexing.Utf8.lexeme buf in
    (finalize_keyword s, sp, end_pos st)
  (* Whitespace: skip, tracking newlines *)
  | Plus white_space ->
    update_newlines st;
    read_token st
  (* End of input *)
  | eof ->
    let sp = current_pos st in (Parser.EOF, sp, sp)
  (* Unexpected character *)
  | any ->
    let sp = current_pos st in
    let s = Sedlexing.Utf8.lexeme buf in
    raise (Lex_error (sp, Printf.sprintf "unexpected character '%s'" s))
  (* Safety net — should be unreachable after eof + any *)
  | _ ->
    raise (Lex_error (current_pos st, "internal lexer error"))

(* --- Batch tokenize (preserves old API for tests) --- *)

let tokenize input =
  validate_utf8 input;
  let buf = Sedlexing.Utf8.from_string input in
  let st = create_state buf in
  let tokens = ref [] in
  let rec go () =
    let (tok, sp, ep) = read_token st in
    tokens := { token = tok; loc = { start = sp; end_ = ep } } :: !tokens;
    match tok with
    | Parser.EOF -> ()
    | _ -> go ()
  in
  go ();
  List.rev !tokens
