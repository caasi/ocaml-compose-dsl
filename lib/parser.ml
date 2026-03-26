open Ast

exception Parse_error of pos * string

module StringSet = Set.Make(String)

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

let rec parse_call_arg st =
  let t = current st in
  match t.token with
  | Lexer.IDENT _ ->
    (match st.tokens with
     | _ :: { Lexer.token = Lexer.COLON; _ } :: _ ->
       let key = match t.token with Lexer.IDENT k -> k | _ -> assert false in
       advance st;
       advance st;
       let value = parse_value st in
       Named { key; value }
     | _ ->
       Positional (parse_seq_expr st))
  | _ ->
    Positional (parse_seq_expr st)

and parse_call_args st =
  let args = ref [] in
  let rec go () =
    let t = current st in
    match t.token with
    | Lexer.RPAREN -> ()
    | _ ->
      args := parse_call_arg st :: !args;
      let t2 = current st in
      (match t2.token with
       | Lexer.COMMA ->
         advance st;
         let t_after = current st in
         (match t_after.token with
          | Lexer.RPAREN ->
            raise (Parse_error (t_after.loc.start, "unexpected trailing comma in argument list"))
          | _ -> go ())
       | Lexer.RPAREN -> ()
       | _ -> raise (Parse_error (t2.loc.start, "expected ',' or ')'")))
  in
  go ();
  List.rev !args

and attach_comments_right (e : expr) comments =
  if comments = [] then e
  else match e.desc with
    | Seq (a, b) -> { e with desc = Seq (a, attach_comments_right b comments) }
    | Par (a, b) -> { e with desc = Par (a, attach_comments_right b comments) }
    | Fanout (a, b) -> { e with desc = Fanout (a, attach_comments_right b comments) }
    | Alt (a, b) -> { e with desc = Alt (a, attach_comments_right b comments) }
    | Group inner -> { e with desc = Group (attach_comments_right inner comments) }
    | Loop inner -> { e with desc = Loop (attach_comments_right inner comments) }
    | StringLit _ -> e
    | Question inner -> { e with desc = Question (attach_comments_right inner comments) }
    | Var _ | App _ | Lambda _ | Let _ -> e

and parse_type_ann st =
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

and parse_seq_expr st =
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

and parse_lambda st start_loc =
  let params = ref [] in
  let seen = ref StringSet.empty in
  let rec read_params () =
    let t = current st in
    match t.token with
    | Lexer.IDENT name ->
      if StringSet.mem name !seen then
        raise (Parse_error (t.loc.start,
          Printf.sprintf "duplicate parameter '%s' in lambda" name));
      seen := StringSet.add name !seen;
      advance st;
      params := name :: !params;
      let t2 = current st in
      (match t2.token with
       | Lexer.COMMA -> advance st; read_params ()
       | Lexer.ARROW -> advance st
       | _ -> raise (Parse_error (t2.loc.start, "expected ',' or '->' in lambda")))
    | _ -> raise (Parse_error (t.loc.start, "expected parameter name"))
  in
  read_params ();
  let param_list = List.rev !params in
  let body = parse_seq_expr st in
  mk_expr { start = start_loc; end_ = body.loc.end_ } (Lambda (param_list, body))

and parse_term st =
  let _ = eat_comments st in
  let t = current st in
  match t.token with
  | Lexer.STRING s ->
    advance st;
    let str_end = st.last_loc.end_ in
    let _ = eat_comments st in
    let t2 = current st in
    let str_expr = mk_expr { start = t.loc.start; end_ = str_end } (StringLit s) in
    (match t2.token with
     | Lexer.QUESTION ->
       advance st;
       mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (Question str_expr)
     | _ -> str_expr)
  | Lexer.IDENT name ->
    advance st;
    let t_next = current st in
    (match t_next.token with
     | Lexer.LPAREN ->
       advance st;
       let args = parse_call_args st in
       expect st (fun tok -> tok = Lexer.RPAREN) "expected ')'";
       let rparen_end = st.last_loc.end_ in
       let _ = eat_comments st in
       let app_expr = mk_expr { start = t.loc.start; end_ = rparen_end }
         (App (mk_expr t.loc (Var name), args)) in
       let t2 = current st in
       (match t2.token with
        | Lexer.QUESTION ->
          advance st;
          mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (Question app_expr)
        | _ -> app_expr)
     | _ ->
       let ident_end = st.last_loc.end_ in
       let _ = eat_comments st in
       let var_expr = mk_expr { start = t.loc.start; end_ = ident_end } (Var name) in
       let t2 = current st in
       (match t2.token with
        | Lexer.QUESTION ->
          advance st;
          mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (Question var_expr)
        | _ -> var_expr))
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
  | Lexer.BACKSLASH ->
    let start = t.loc.start in
    advance st;
    parse_lambda st start
  | _ -> raise (Parse_error (t.loc.start, "expected node, string, '(', 'loop', or '\\' (lambda)"))

let parse_program tokens =
  let st = make tokens in
  let rec read_lets () =
    let _ = eat_comments st in
    let t = current st in
    match t.token with
    | Lexer.LET ->
      advance st;
      let t_name = current st in
      let name = match t_name.token with
        | Lexer.IDENT s -> advance st; s
        | _ -> raise (Parse_error (t_name.loc.start, "expected identifier after 'let'"))
      in
      expect st (fun tok -> tok = Lexer.EQUALS) "expected '=' after let binding name";
      let value = parse_seq_expr st in
      let rest = read_lets () in
      mk_expr { start = t.loc.start; end_ = rest.loc.end_ } (Let (name, value, rest))
    | _ ->
      let expr = parse_seq_expr st in
      let t_end = current st in
      (match t_end.token with
       | Lexer.EOF -> ()
       | _ -> raise (Parse_error (t_end.loc.start, "expected end of input")));
      expr
  in
  read_lets ()
