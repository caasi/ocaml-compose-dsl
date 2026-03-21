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
  | COMMENT of string
  | EOF

type pos = { line : int; col : int }

type located = { token : token; pos : pos }

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
  let peek2 () = if !i + 1 < len then Some input.[!i + 1] else None in
  let skip_whitespace () =
    while !i < len && (input.[!i] = ' ' || input.[!i] = '\t' || input.[!i] = '\n' || input.[!i] = '\r' || input.[!i] = '\x0b' || input.[!i] = '\x0c') do
      advance ()
    done
  in
  let read_string () =
    let p = pos () in
    advance (); (* skip opening quote *)
    let buf = Buffer.create 32 in
    while !i < len && input.[!i] <> '"' do
      Buffer.add_char buf input.[!i];
      advance ()
    done;
    if !i >= len then raise (Lex_error (p, "unterminated string"));
    advance (); (* skip closing quote *)
    { token = STRING (Buffer.contents buf); pos = p }
  in
  let read_ident () =
    let p = pos () in
    let start = !i in
    while !i < len && is_ident_char input.[!i] do
      advance ()
    done;
    let s = String.sub input start (!i - start) in
    let tok = if s = "loop" then LOOP else IDENT s in
    { token = tok; pos = p }
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
    { token = COMMENT s; pos = p }
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
    { token = NUMBER s; pos = p }
  in
  while !i < len do
    skip_whitespace ();
    if !i >= len then ()
    else
      let p = pos () in
      let c = input.[!i] in
      match c with
      | '(' -> tokens := { token = LPAREN; pos = p } :: !tokens; advance ()
      | ')' -> tokens := { token = RPAREN; pos = p } :: !tokens; advance ()
      | '[' -> tokens := { token = LBRACKET; pos = p } :: !tokens; advance ()
      | ']' -> tokens := { token = RBRACKET; pos = p } :: !tokens; advance ()
      | ':' -> tokens := { token = COLON; pos = p } :: !tokens; advance ()
      | ',' -> tokens := { token = COMMA; pos = p } :: !tokens; advance ()
      | '>' ->
        if peek2 () = Some '>' && !i + 2 < len && input.[!i + 2] = '>' then begin
          tokens := { token = SEQ; pos = p } :: !tokens;
          advance (); advance (); advance ()
        end else
          raise (Lex_error (p, Printf.sprintf "unexpected character '%c'" c))
      | '*' ->
        if peek2 () = Some '*' && !i + 2 < len && input.[!i + 2] = '*' then begin
          tokens := { token = PAR; pos = p } :: !tokens;
          advance (); advance (); advance ()
        end else
          raise (Lex_error (p, Printf.sprintf "unexpected character '%c'" c))
      | '|' ->
        if peek2 () = Some '|' && !i + 2 < len && input.[!i + 2] = '|' then begin
          tokens := { token = ALT; pos = p } :: !tokens;
          advance (); advance (); advance ()
        end else
          raise (Lex_error (p, Printf.sprintf "unexpected character '%c'" c))
      | '&' ->
        if peek2 () = Some '&' && !i + 2 < len && input.[!i + 2] = '&' then begin
          tokens := { token = FANOUT; pos = p } :: !tokens;
          advance (); advance (); advance ()
        end else
          raise (Lex_error (p, Printf.sprintf "unexpected character '%c'" c))
      | '-' ->
        if peek2 () = Some '-' then begin
          tokens := read_comment () :: !tokens
        end else begin
          match peek2 () with
          | Some c2 when c2 >= '0' && c2 <= '9' ->
            tokens := read_number () :: !tokens
          | _ ->
            raise (Lex_error (p, Printf.sprintf "unexpected character '%c'" c))
        end
      | '"' -> tokens := read_string () :: !tokens
      | c when c >= '0' && c <= '9' -> tokens := read_number () :: !tokens
      | c when is_ident_start c -> tokens := read_ident () :: !tokens
      | c -> raise (Lex_error (p, Printf.sprintf "unexpected character '%c'" c))
  done;
  let p = pos () in
  List.rev ({ token = EOF; pos = p } :: !tokens)
