type token =
  | IDENT of string
  | STRING of string
  | NUMBER of string
  | LPAREN
  | RPAREN
  | LBRACKET
  | RBRACKET
  | COLON
  | COMMA
  | SEQ (** [>>>] *)
  | PAR (** [***] *)
  | ALT (** [|||] *)
  | FANOUT (** [&&&] *)
  | LOOP
  | QUESTION
  | DOUBLE_COLON (** [::] *)
  | ARROW (** [->] *)
  | BACKSLASH (** [\] *)
  | LET (** [let] keyword *)
  | EQUALS (** [=] *)
  | COMMENT of string
  | EOF

open Ast
type located = { token : token; loc : loc }

exception Lex_error of pos * string

let is_special_ascii c =
  c = '(' || c = ')' || c = '[' || c = ']' || c = ':' || c = ','
  || c = '>' || c = '*' || c = '|' || c = '&' || c = '"' || c = '.'
  || c = '!' || c = '#' || c = '$' || c = '%' || c = '^' || c = '+'
  || c = '=' || c = '{' || c = '}' || c = '<' || c = ';' || c = '\''
  || c = '`' || c = '~' || c = '/' || c = '?' || c = '@' || c = '\\'
  || c = ' ' || c = '\t' || c = '\n' || c = '\r' || c = '\x0b' || c = '\x0c'

let is_ident_start c =
  not (is_special_ascii c) && not (c >= '0' && c <= '9') && c <> '-'

let is_ident_char c =
  not (is_special_ascii c)

let tokenize input =
  let len = String.length input in
  let line = ref 1 in
  let col = ref 1 in
  let i = ref 0 in
  let tokens = Buffer.create 64 |> ignore; ref [] in
  let pos () = { line = !line; col = !col } in
  let advance () =
    if !i < len then begin
      let d = String.get_utf_8_uchar input !i in
      if Uchar.utf_decode_is_valid d then begin
        let n = Uchar.utf_decode_length d in
        let u = Uchar.utf_decode_uchar d in
        if Uchar.equal u (Uchar.of_char '\n') then
          (incr line; col := 1)
        else
          incr col;
        i := !i + n
      end else
        raise (Lex_error (pos (), "invalid UTF-8 byte sequence"))
    end
  in
  let peek_byte () = if !i + 1 < len then Some input.[!i + 1] else None in
  let skip_whitespace () =
    while !i < len && (input.[!i] = ' ' || input.[!i] = '\t' || input.[!i] = '\n' || input.[!i] = '\r' || input.[!i] = '\x0b' || input.[!i] = '\x0c') do
      advance ()
    done
  in
  let read_string () =
    let p = pos () in
    advance (); (* skip opening quote *)
    let start = !i in
    while !i < len && input.[!i] <> '"' do
      advance ()
    done;
    if !i >= len then raise (Lex_error (p, "unterminated string"));
    let s = String.sub input start (!i - start) in
    advance (); (* skip closing quote *)
    { token = STRING s; loc = { start = p; end_ = pos () } }
  in
  let read_ident () =
    let p = pos () in
    let start = !i in
    while !i < len && is_ident_char input.[!i]
          && not (input.[!i] = '-' && !i + 1 < len && input.[!i + 1] = '>') do
      advance ()
    done;
    let s = String.sub input start (!i - start) in
    let tok = match s with
      | "loop" -> LOOP
      | "let" -> LET
      | _ -> IDENT s
    in
    { token = tok; loc = { start = p; end_ = pos () } }
  in
  let read_comment () =
    let p = pos () in
    advance (); advance (); (* skip -- *)
    (* skip leading whitespace *)
    while !i < len && (input.[!i] = ' ' || input.[!i] = '\t') do
      advance ()
    done;
    let start = !i in
    while !i < len && input.[!i] <> '\n' do
      advance ()
    done;
    let s = String.sub input start (!i - start) in
    { token = COMMENT s; loc = { start = p; end_ = pos () } }
  in
  let read_number () =
    let p = pos () in
    let start = !i in
    if !i < len && input.[!i] = '-' then advance ();
    while !i < len && input.[!i] >= '0' && input.[!i] <= '9' do
      advance ()
    done;
    if !i < len && input.[!i] = '.' then begin
      advance ();
      let frac_start = !i in
      while !i < len && input.[!i] >= '0' && input.[!i] <= '9' do
        advance ()
      done;
      if !i = frac_start then
        raise (Lex_error (p, "expected digit after '.'"))
    end;
    if !i < len && is_ident_start input.[!i] then begin
      advance ();
      while !i < len && is_ident_char input.[!i] do
        advance ()
      done
    end;
    let s = String.sub input start (!i - start) in
    { token = NUMBER s; loc = { start = p; end_ = pos () } }
  in
  while !i < len do
    skip_whitespace ();
    if !i >= len then ()
    else
      let p = pos () in
      (* NOTE: byte-level dispatch. All operators/delimiters are ASCII, so
         matching on the raw byte is safe — UTF-8 continuation bytes (0x80-0xBF)
         never collide with ASCII. For valid UTF-8 input, the cursor is always
         on a codepoint boundary, so lead bytes (0xC0-0xFF) fall through to
         the ident branch where advance() handles them as multi-byte sequences.
         Malformed continuation bytes at unexpected positions are caught by
         advance()'s UTF-8 validation. *)
      let c = input.[!i] in
      match c with
      | '(' -> advance (); tokens := { token = LPAREN; loc = { start = p; end_ = pos () } } :: !tokens
      | ')' -> advance (); tokens := { token = RPAREN; loc = { start = p; end_ = pos () } } :: !tokens
      | '[' -> advance (); tokens := { token = LBRACKET; loc = { start = p; end_ = pos () } } :: !tokens
      | ']' -> advance (); tokens := { token = RBRACKET; loc = { start = p; end_ = pos () } } :: !tokens
      | ':' ->
        if peek_byte () = Some ':' then begin
          advance (); advance ();
          tokens := { token = DOUBLE_COLON; loc = { start = p; end_ = pos () } } :: !tokens
        end else begin
          advance ();
          tokens := { token = COLON; loc = { start = p; end_ = pos () } } :: !tokens
        end
      | ',' -> advance (); tokens := { token = COMMA; loc = { start = p; end_ = pos () } } :: !tokens
      | '>' ->
        if peek_byte () = Some '>' && !i + 2 < len && input.[!i + 2] = '>' then begin
          advance (); advance (); advance ();
          tokens := { token = SEQ; loc = { start = p; end_ = pos () } } :: !tokens
        end else
          raise (Lex_error (p, Printf.sprintf "unexpected character '%c'" c))
      | '*' ->
        if peek_byte () = Some '*' && !i + 2 < len && input.[!i + 2] = '*' then begin
          advance (); advance (); advance ();
          tokens := { token = PAR; loc = { start = p; end_ = pos () } } :: !tokens
        end else
          raise (Lex_error (p, Printf.sprintf "unexpected character '%c'" c))
      | '|' ->
        if peek_byte () = Some '|' && !i + 2 < len && input.[!i + 2] = '|' then begin
          advance (); advance (); advance ();
          tokens := { token = ALT; loc = { start = p; end_ = pos () } } :: !tokens
        end else
          raise (Lex_error (p, Printf.sprintf "unexpected character '%c'" c))
      | '&' ->
        if peek_byte () = Some '&' && !i + 2 < len && input.[!i + 2] = '&' then begin
          advance (); advance (); advance ();
          tokens := { token = FANOUT; loc = { start = p; end_ = pos () } } :: !tokens
        end else
          raise (Lex_error (p, Printf.sprintf "unexpected character '%c'" c))
      | '-' ->
        if peek_byte () = Some '-' then begin
          tokens := read_comment () :: !tokens
        end else begin
          match peek_byte () with
          | Some c2 when c2 >= '0' && c2 <= '9' ->
            tokens := read_number () :: !tokens
          | Some '>' ->
            advance (); advance ();
            tokens := { token = ARROW; loc = { start = p; end_ = pos () } } :: !tokens
          | _ ->
            raise (Lex_error (p, Printf.sprintf "unexpected character '%c'" c))
        end
      | '"' -> tokens := read_string () :: !tokens
      | '?' -> advance (); tokens := { token = QUESTION; loc = { start = p; end_ = pos () } } :: !tokens
      | '\\' -> advance (); tokens := { token = BACKSLASH; loc = { start = p; end_ = pos () } } :: !tokens
      | '=' -> advance (); tokens := { token = EQUALS; loc = { start = p; end_ = pos () } } :: !tokens
      | c when c >= '0' && c <= '9' -> tokens := read_number () :: !tokens
      | c when is_ident_start c -> tokens := read_ident () :: !tokens
      | c -> raise (Lex_error (p, Printf.sprintf "unexpected character '%c'" c))
  done;
  let p = pos () in
  List.rev ({ token = EOF; loc = { start = p; end_ = p } } :: !tokens)
