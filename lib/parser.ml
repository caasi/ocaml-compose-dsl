open Ast

exception Parse_error of Lexer.pos * string

type state = { mutable tokens : Lexer.located list }

let make tokens = { tokens }

let current st =
  match st.tokens with
  | [] -> failwith "unexpected end of token stream"
  | t :: _ -> t

let advance st =
  match st.tokens with
  | [] -> failwith "unexpected end of token stream"
  | _ :: rest -> st.tokens <- rest

let expect st tok_match msg =
  let t = current st in
  if tok_match t.token then advance st
  else raise (Parse_error (t.pos, msg))

let eat_comments st =
  let comments = ref [] in
  let rec go () =
    match (current st).token with
    | Lexer.COMMENT s -> comments := s :: !comments; advance st; go ()
    | _ -> ()
  in
  go ();
  List.rev !comments

let parse_value st =
  let t = current st in
  match t.token with
  | Lexer.STRING s -> advance st; String s
  | Lexer.IDENT s -> advance st; Ident s
  | Lexer.LBRACKET ->
    advance st;
    let values = ref [] in
    let rec go () =
      let t = current st in
      match t.token with
      | Lexer.RBRACKET -> advance st
      | _ ->
        let v =
          let t = current st in
          match t.token with
          | Lexer.STRING s -> advance st; String s
          | Lexer.IDENT s -> advance st; Ident s
          | _ -> raise (Parse_error (t.pos, "expected value in list"))
        in
        values := v :: !values;
        let t = current st in
        (match t.token with
         | Lexer.COMMA -> advance st; go ()
         | Lexer.RBRACKET -> advance st
         | _ -> raise (Parse_error (t.pos, "expected ',' or ']'")))
    in
    go ();
    List (List.rev !values)
  | _ -> raise (Parse_error (t.pos, "expected value"))

let parse_args st =
  let args = ref [] in
  let rec go () =
    let t = current st in
    match t.token with
    | Lexer.RPAREN -> ()
    | Lexer.IDENT key ->
      advance st;
      expect st (fun t -> t = Lexer.COLON) "expected ':'";
      let value = parse_value st in
      args := { key; value } :: !args;
      let t = current st in
      (match t.token with
       | Lexer.COMMA -> advance st; go ()
       | Lexer.RPAREN -> ()
       | _ -> raise (Parse_error (t.pos, "expected ',' or ')'")))
    | _ -> raise (Parse_error (t.pos, "expected argument name or ')'"))
  in
  go ();
  List.rev !args

let rec parse_seq_expr st =
  let lhs = parse_alt_expr st in
  let comments = eat_comments st in
  let lhs =
    match lhs with
    | Node n -> Node { n with comments = n.comments @ comments }
    | _ -> lhs
  in
  let t = current st in
  match t.token with
  | Lexer.SEQ -> advance st; Seq (lhs, parse_seq_expr st)
  | _ -> lhs

and parse_alt_expr st =
  let lhs = parse_par_expr st in
  let comments = eat_comments st in
  let lhs =
    match lhs with
    | Node n -> Node { n with comments = n.comments @ comments }
    | _ -> lhs
  in
  let t = current st in
  match t.token with
  | Lexer.ALT -> advance st; Alt (lhs, parse_alt_expr st)
  | _ -> lhs

and parse_par_expr st =
  let lhs = parse_term st in
  let comments = eat_comments st in
  let lhs =
    match lhs with
    | Node n -> Node { n with comments = n.comments @ comments }
    | _ -> lhs
  in
  let t = current st in
  match t.token with
  | Lexer.PAR -> advance st; Par (lhs, parse_par_expr st)
  | Lexer.FANOUT -> advance st; Fanout (lhs, parse_par_expr st)
  | _ -> lhs

and parse_term st =
  let _ = eat_comments st in
  let t = current st in
  match t.token with
  | Lexer.IDENT name ->
    advance st;
    let t = current st in
    (match t.token with
     | Lexer.LPAREN ->
       advance st;
       let args = parse_args st in
       expect st (fun t -> t = Lexer.RPAREN) "expected ')'";
       let comments = eat_comments st in
       Node { name; args; comments }
     | _ ->
       let comments = eat_comments st in
       Node { name; args = []; comments })
  | Lexer.LOOP ->
    advance st;
    expect st (fun t -> t = Lexer.LPAREN) "expected '(' after 'loop'";
    let body = parse_seq_expr st in
    expect st (fun t -> t = Lexer.RPAREN) "expected ')' to close 'loop'";
    Loop body
  | Lexer.LPAREN ->
    advance st;
    let inner = parse_seq_expr st in
    expect st (fun t -> t = Lexer.RPAREN) "expected ')'";
    Group inner
  | _ -> raise (Parse_error (t.pos, "expected node, '(' or 'loop'"))

let parse tokens =
  let st = make tokens in
  let expr = parse_seq_expr st in
  let t = current st in
  (match t.token with
   | Lexer.EOF -> ()
   | _ -> raise (Parse_error (t.pos, "expected end of input")));
  expr
