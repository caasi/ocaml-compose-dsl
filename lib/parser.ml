open Ast

exception Parse_error of pos * string

module StringSet = Set.Make(String)

type state = {
  mutable tokens : Lexer.located list;
  mutable last_loc : loc;
  mutable scope : StringSet.t;
}

let dummy_loc = { start = { line = 1; col = 1 }; end_ = { line = 1; col = 1 } }

let make tokens = { tokens; last_loc = dummy_loc; scope = StringSet.empty }

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
    | Lambda _ | Var _ | App _ | Let _ -> e

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

and parse_lambda st start_loc =
  (* BACKSLASH already consumed *)
  let params = ref [] in
  let rec read_params () =
    let t = current st in
    match t.token with
    | Lexer.IDENT name ->
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
  let old_scope = st.scope in
  st.scope <- List.fold_left (fun s p -> StringSet.add p s) st.scope param_list;
  let body = parse_seq_expr st in
  st.scope <- old_scope;
  mk_expr { start = start_loc; end_ = body.loc.end_ } (Lambda (param_list, body))

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
    let in_scope = StringSet.mem name st.scope in
    let t_next = current st in
    (match t_next.token with
     | Lexer.LPAREN ->
       advance st;
       let t_peek = current st in
       (* Disambiguation: IDENT COLON → named args, else → positional *)
       let is_named = match t_peek.token with
         | Lexer.IDENT _ ->
           (match st.tokens with
            | _ :: { Lexer.token = Lexer.COLON; _ } :: _ -> true
            | _ -> false)
         | Lexer.RPAREN -> not in_scope  (* empty parens: out-of-scope → named (Node), in-scope → positional (App) *)
         | _ -> false
       in
       if is_named then begin
         if in_scope then
           raise (Parse_error (t.loc.start, Printf.sprintf "cannot pass named args to variable '%s'" name));
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
       end else begin
         (* Positional args — lambda application *)
         let args = ref [] in
         let rec read_positional () =
           let t_check = current st in
           match t_check.token with
           | Lexer.RPAREN -> ()
           | _ ->
             args := parse_seq_expr st :: !args;
             let t_check2 = current st in
             (match t_check2.token with
              | Lexer.COMMA -> advance st; read_positional ()
              | Lexer.RPAREN -> ()
              | _ -> raise (Parse_error (t_check2.loc.start, "expected ',' or ')'")))
         in
         read_positional ();
         expect st (fun tok -> tok = Lexer.RPAREN) "expected ')'";
         let fn_expr = if in_scope
           then mk_expr t.loc (Var name)
           else mk_expr t.loc (Node { name; args = []; comments = [] })
         in
         mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (App (fn_expr, List.rev !args))
       end
     | _ ->
       if in_scope then begin
         let ident_end = st.last_loc.end_ in
         let _ = eat_comments st in
         mk_expr { start = t.loc.start; end_ = ident_end } (Var name)
       end else begin
         let ident_end = st.last_loc.end_ in
         let comments = eat_comments st in
         let n = { name; args = []; comments } in
         let t2 = current st in
         (match t2.token with
          | Lexer.QUESTION ->
            advance st;
            mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (Question (QNode n))
          | _ ->
            mk_expr { start = t.loc.start; end_ = ident_end } (Node n))
       end)
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
  | _ -> raise (Parse_error (t.loc.start, "expected node, string with '?', '(' or 'loop'"))

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
      if StringSet.mem name st.scope then
        Printf.eprintf "warning at %d:%d: '%s' shadows previous binding\n"
          t_name.loc.start.line t_name.loc.start.col name;
      let old_scope = st.scope in
      let value = parse_seq_expr st in
      (* Name is in scope for subsequent bindings and body *)
      st.scope <- StringSet.add name old_scope;
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

let parse tokens =
  let st = make tokens in
  let expr = parse_seq_expr st in
  let t = current st in
  (match t.token with
   | Lexer.EOF -> ()
   | _ -> raise (Parse_error (t.loc.start, "expected end of input")));
  expr
