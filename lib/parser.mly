%{
open Ast

let mk_expr (startpos, endpos) desc : expr =
  let pos_of (p : Lexing.position) : Ast.pos =
    { line = p.pos_lnum; col = p.pos_cnum - p.pos_bol + 1 }
  in
  { loc = { start = pos_of startpos; end_ = pos_of endpos };
    desc;
    type_ann = None }
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
  | e=seq_expr  { e }
;

seq_expr:
  | e=term  { e }
;

term:
  | name=IDENT
    { mk_expr ($startpos, $endpos) (Var name) }
;
