type pos = { line : int; col : int }
type loc = { start : pos; end_ : pos }

type value =
  | String of string
  | Ident of string
  | Number of string
  | List of value list

type arg = { key : string; value : value }

type type_ann = { input : string; output : string }

type expr = { loc : loc; desc : expr_desc; type_ann : type_ann option }
and expr_desc =
  | Unit                             (** () — unit value *)
  | Var of string                   (** variable reference, bound or free *)
  | StringLit of string             (** string literal as expression *)
  | Seq of expr * expr              (** [>>>] *)
  | Par of expr * expr              (** [***] *)
  | Fanout of expr * expr           (** [&&&] *)
  | Alt of expr * expr              (** [|||] *)
  | Loop of expr
  | Group of expr
  | Question of expr                (** [?] — parser allows on Var, StringLit, App, Unit *)
  | Lambda of string list * expr    (** [\x, y -> body] *)
  | App of expr * call_arg list     (** unified application, mixed named/positional *)
  | Let of string * expr * expr     (** [let x = expr] followed by rest of program *)

and call_arg =
  | Named of arg                    (** key: value — static configuration *)
  | Positional of expr              (** pipeline expression *)

exception Duplicate_param of pos * string
