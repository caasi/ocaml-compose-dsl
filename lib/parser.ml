open Ast

exception Parse_error of pos * string

type state = {
  mutable tokens : Lexer.located list;
  mutable last_loc : loc;
}

let dummy_loc = { start = { line = 1; col = 1 }; end_ = { line = 1; col = 1 } }

let make tokens = { tokens; last_loc = dummy_loc }

let mk_expr loc desc : expr = { loc; desc; type_ann = None }

let current st =
  match st.tokens with
  | [] -> failwith "unexpected end of token stream"
  | t :: _ -> t

let advance st =
  match st.tokens with
  | [] -> failwith "unexpected end of token stream"
  | t :: rest ->
    st.last_loc <- t.loc;
    st.tokens <- rest

let expect st tok_match msg =
  let t = current st in
  if tok_match t.token then advance st
  else raise (Parse_error (t.loc.start, msg))

let eat_comments st =
  let comments = ref [] in
  let rec go () =
    match (current st).token with
    | Lexer.COMMENT s -> comments := s :: !comments; advance st; go ()
    | _ -> ()
  in
  go ();
  List.rev !comments

let rec parse_value st =
  let t = current st in
  match t.token with
  | Lexer.STRING s -> advance st; String s
  | Lexer.IDENT s -> advance st; Ident s
  | Lexer.NUMBER s -> advance st; Number s
  | Lexer.LBRACKET ->
    advance st;
    let values = ref [] in
    let rec go () =
      let t = current st in
      match t.token with
      | Lexer.RBRACKET -> advance st
      | _ ->
        values := parse_value st :: !values;
        let t = current st in
        (match t.token with
         | Lexer.COMMA -> advance st; go ()
         | Lexer.RBRACKET -> advance st
         | _ -> raise (Parse_error (t.loc.start, "expected ',' or ']'")))
    in
    go ();
    List (List.rev !values)
  | _ -> raise (Parse_error (t.loc.start, "expected value"))

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
       | _ -> raise (Parse_error (t.loc.start, "expected ',' or ')'")))
    | _ -> raise (Parse_error (t.loc.start, "expected argument name or ')'"))
  in
  go ();
  List.rev !args

let rec attach_comments_right (e : expr) comments =
  if comments = [] then e
  else match e.desc with
    | Node n -> { e with desc = Node { n with comments = n.comments @ comments } }
    | Seq (a, b) -> { e with desc = Seq (a, attach_comments_right b comments) }
    | Par (a, b) -> { e with desc = Par (a, attach_comments_right b comments) }
    | Fanout (a, b) -> { e with desc = Fanout (a, attach_comments_right b comments) }
    | Alt (a, b) -> { e with desc = Alt (a, attach_comments_right b comments) }
    | Group inner -> { e with desc = Group (attach_comments_right inner comments) }
    | Loop inner -> { e with desc = Loop (attach_comments_right inner comments) }
    | Question (QNode n) -> { e with desc = Question (QNode { n with comments = n.comments @ comments }) }
    | Question (QString _) -> e

let parse_type_ann st =
  let t = current st in
  match t.token with
  | Lexer.DOUBLE_COLON ->
    advance st;
    let t_in = current st in
    (match t_in.token with
     | Lexer.IDENT input ->
       advance st;
       expect st (fun tok -> tok = Lexer.ARROW) "expected '->' in type annotation";
       let t_out = current st in
       (match t_out.token with
        | Lexer.IDENT output ->
          advance st;
          Some { input; output }
        | _ -> raise (Parse_error (t_out.loc.start, "expected type name after '->'")))
     | _ -> raise (Parse_error (t_in.loc.start, "expected type name after '::'")))
  | _ -> None

let rec parse_seq_expr st =
  let lhs = parse_alt_expr st in
  let comments = eat_comments st in
  let lhs = attach_comments_right lhs comments in
  let t = current st in
  match t.token with
  | Lexer.SEQ -> advance st; let rhs = parse_seq_expr st in
    mk_expr { start = lhs.loc.start; end_ = rhs.loc.end_ } (Seq (lhs, rhs))
  | _ -> lhs

and parse_alt_expr st =
  let lhs = parse_par_expr st in
  let comments = eat_comments st in
  let lhs = attach_comments_right lhs comments in
  let t = current st in
  match t.token with
  | Lexer.ALT -> advance st; let rhs = parse_alt_expr st in
    mk_expr { start = lhs.loc.start; end_ = rhs.loc.end_ } (Alt (lhs, rhs))
  | _ -> lhs

and parse_par_expr st =
  let lhs = parse_term st in
  let type_ann = parse_type_ann st in
  let lhs = match type_ann with
    | None -> lhs
    | Some _ -> { lhs with type_ann; loc = { lhs.loc with end_ = st.last_loc.end_ } }
  in
  let comments = eat_comments st in
  let lhs = attach_comments_right lhs comments in
  let t = current st in
  match t.token with
  | Lexer.PAR -> advance st; let rhs = parse_par_expr st in
    mk_expr { start = lhs.loc.start; end_ = rhs.loc.end_ } (Par (lhs, rhs))
  | Lexer.FANOUT -> advance st; let rhs = parse_par_expr st in
    mk_expr { start = lhs.loc.start; end_ = rhs.loc.end_ } (Fanout (lhs, rhs))
  | _ -> lhs

and parse_term st =
  let _ = eat_comments st in
  let t = current st in
  match t.token with
  | Lexer.STRING s ->
    advance st;
    let _ = eat_comments st in
    let t2 = current st in
    (match t2.token with
     | Lexer.QUESTION ->
       advance st;
       mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (Question (QString s))
     | _ -> raise (Parse_error (t.loc.start, "bare string is not a valid term; did you mean to add '?'?")))
  | Lexer.IDENT name ->
    advance st;
    let t_next = current st in
    (match t_next.token with
     | Lexer.LPAREN ->
       advance st;
       let args = parse_args st in
       expect st (fun tok -> tok = Lexer.RPAREN) "expected ')'";
       let rparen_end = st.last_loc.end_ in
       let comments = eat_comments st in
       let n = { name; args; comments } in
       let t2 = current st in
       (match t2.token with
        | Lexer.QUESTION ->
          advance st;
          mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (Question (QNode n))
        | _ ->
          mk_expr { start = t.loc.start; end_ = rparen_end } (Node n))
     | _ ->
       let ident_end = st.last_loc.end_ in
       let comments = eat_comments st in
       let n = { name; args = []; comments } in
       let t2 = current st in
       (match t2.token with
        | Lexer.QUESTION ->
          advance st;
          mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (Question (QNode n))
        | _ ->
          mk_expr { start = t.loc.start; end_ = ident_end } (Node n)))
  | Lexer.LOOP ->
    advance st;
    expect st (fun tok -> tok = Lexer.LPAREN) "expected '(' after 'loop'";
    let body = parse_seq_expr st in
    expect st (fun tok -> tok = Lexer.RPAREN) "expected ')' to close 'loop'";
    mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (Loop body)
  | Lexer.LPAREN ->
    advance st;
    let inner = parse_seq_expr st in
    expect st (fun tok -> tok = Lexer.RPAREN) "expected ')'";
    mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (Group inner)
  | _ -> raise (Parse_error (t.loc.start, "expected node, string with '?', '(' or 'loop'"))

let parse tokens =
  let st = make tokens in
  let expr = parse_seq_expr st in
  let t = current st in
  (match t.token with
   | Lexer.EOF -> ()
   | _ -> raise (Parse_error (t.loc.start, "expected end of input")));
  expr
