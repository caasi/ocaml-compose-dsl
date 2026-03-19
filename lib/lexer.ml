type token =
  | IDENT of string
  | STRING of string
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

let is_ident_start c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_'

let is_ident_char c = is_ident_start c || (c >= '0' && c <= '9') || c = '-'

let tokenize input =
  let len = String.length input in
  let line = ref 1 in
  let col = ref 1 in
  let i = ref 0 in
  let tokens = Buffer.create 64 |> ignore; ref [] in
  let pos () = { line = !line; col = !col } in
  let advance () =
    if !i < len && input.[!i] = '\n' then (incr line; col := 1)
    else incr col;
    incr i
  in
  let peek2 () = if !i + 1 < len then Some input.[!i + 1] else None in
  let skip_whitespace () =
    while !i < len && (input.[!i] = ' ' || input.[!i] = '\t' || input.[!i] = '\n' || input.[!i] = '\r') do
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
        end else
          raise (Lex_error (p, Printf.sprintf "unexpected character '%c'" c))
      | '"' -> tokens := read_string () :: !tokens
      | c when is_ident_start c -> tokens := read_ident () :: !tokens
      | c -> raise (Lex_error (p, Printf.sprintf "unexpected character '%c'" c))
  done;
  let p = pos () in
  List.rev ({ token = EOF; pos = p } :: !tokens)
