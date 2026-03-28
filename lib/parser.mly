%{
open Ast

let mk_expr (startpos, endpos) desc : expr =
  let pos_of (p : Lexing.position) : Ast.pos =
    { line = p.pos_lnum; col = p.pos_cnum - p.pos_bol + 1 }
  in
  { loc = { start = pos_of startpos; end_ = pos_of endpos };
    desc;
    type_ann = None }

let end_pos_of (p : Lexing.position) : Ast.pos =
  { line = p.pos_lnum; col = p.pos_cnum - p.pos_bol + 1 }
%}

%token <string> IDENT STRING NUMBER COMMENT
%token SEQ PAR FANOUT ALT ARROW DOUBLE_COLON
%token LET IN LOOP
%token LPAREN RPAREN LBRACKET RBRACKET
%token COMMA COLON EQUALS BACKSLASH QUESTION
%token EOF

%start <Ast.expr> program

%%

program:
  | e=program_inner EOF  { e }
;

program_inner:
  | LET name=IDENT EQUALS value=seq_expr IN rest=program_inner
    { mk_expr $loc (Let (name, value, rest)) }
  | e=seq_expr
    { e }
;

seq_expr:
  | lhs=alt_expr SEQ rhs=seq_expr   { mk_expr $loc (Seq (lhs, rhs)) }
  | BACKSLASH params=lambda_params ARROW body=seq_expr
    { let seen = Hashtbl.create 4 in
      List.iter (fun (pos, p) ->
        if Hashtbl.mem seen p then
          raise (Ast.Duplicate_param (end_pos_of pos,
            Printf.sprintf "duplicate parameter '%s' in lambda" p));
        Hashtbl.replace seen p ()
      ) params;
      mk_expr $loc (Lambda (List.map snd params, body)) }
  | e=alt_expr                       { e }
;

alt_expr:
  | lhs=par_expr ALT rhs=alt_expr   { mk_expr $loc (Alt (lhs, rhs)) }
  | e=par_expr                       { e }
;

par_expr:
  | lhs=typed_term PAR rhs=par_expr     { mk_expr $loc (Par (lhs, rhs)) }
  | lhs=typed_term FANOUT rhs=par_expr  { mk_expr $loc (Fanout (lhs, rhs)) }
  | e=typed_term                         { e }
;

typed_term:
  | e=term DOUBLE_COLON input=type_name ARROW output=type_name
    { { e with type_ann = Some { input; output };
               loc = { start = e.loc.start;
                        end_ = end_pos_of $endpos } } }
  | e=term  { e }
;

type_name:
  | name=IDENT     { name }
  | LPAREN RPAREN  { "()" }
;

term:
  | name=IDENT LPAREN args=call_args_or_unit RPAREN QUESTION
    { mk_expr $loc (Question (mk_expr ($startpos(name), $endpos($4)) (App (mk_expr ($loc(name)) (Var name), args)))) }
  | name=IDENT LPAREN args=call_args_or_unit RPAREN
    { mk_expr $loc (App (mk_expr ($loc(name)) (Var name), args)) }
  | name=IDENT QUESTION
    { mk_expr $loc (Question (mk_expr ($loc(name)) (Var name))) }
  | name=IDENT
    { mk_expr ($loc(name)) (Var name) }
  | s=STRING QUESTION
    { mk_expr $loc (Question (mk_expr ($loc(s)) (StringLit s))) }
  | s=STRING
    { mk_expr ($loc(s)) (StringLit s) }
  | LPAREN RPAREN QUESTION
    { mk_expr $loc (Question (mk_expr ($startpos, $endpos($2)) Unit)) }
  | LPAREN RPAREN
    { mk_expr $loc Unit }
  | LOOP LPAREN body=seq_expr RPAREN
    { mk_expr $loc (Loop body) }
  | LPAREN inner=program_inner RPAREN
    { mk_expr $loc (Group inner) }
;

(* Empty call args produce [Positional Unit], not [].
   Zero-arg application is eliminated: f() = f(()) *)
call_args_or_unit:
  | args=call_args  { args }
  |                 { [Positional (mk_expr $loc Unit)] }
;

lambda_params:
  | p=IDENT COMMA rest=lambda_params  { ($startpos(p), p) :: rest }
  | p=IDENT                           { [($startpos(p), p)] }
;

call_args:
  | a=call_arg COMMA rest=call_args  { a :: rest }
  | a=call_arg                       { [a] }
;

(* arg_key is inlined to avoid reduce/reduce conflict:
   Without inlining, IDENT would be ambiguous between
   arg_key (Named path) and term->Var (Positional path). *)
call_arg:
  | key=IDENT COLON v=value  { Named { key; value = v } }
  | IN COLON v=value         { Named { key = "in"; value = v } }
  | e=seq_expr               { Positional e }
;

value:
  | s=STRING                                          { String s }
  | n=NUMBER                                          { Number n }
  | i=IDENT                                           { Ident i }
  | LBRACKET vs=separated_list(COMMA, value) RBRACKET { List vs }
;
