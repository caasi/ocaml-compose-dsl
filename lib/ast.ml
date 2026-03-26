type pos = { line : int; col : int }
type loc = { start : pos; end_ : pos }

type value =
  | String of string
  | Ident of string
  | Number of string
  | List of value list

type arg = { key : string; value : value }

type node = { name : string; args : arg list; comments : string list }

type type_ann = { input : string; output : string }

type expr = { loc : loc; desc : expr_desc; type_ann : type_ann option }
and expr_desc =
  | Node of node
  | StringLit of string             (** string literal as expression *)
  | Seq of expr * expr              (** [>>>] *)
  | Par of expr * expr              (** [***] *)
  | Fanout of expr * expr           (** [&&&] *)
  | Alt of expr * expr              (** [|||] *)
  | Loop of expr
  | Group of expr
  | Question of expr                (** [?] — parser restricts to Node/StringLit *)
  | Lambda of string list * expr    (** [\x, y -> body] *)
  | Var of string                   (** [variable reference] *)
  | App of expr * expr list         (** [f(arg1, arg2)] *)
  | Let of string * expr * expr     (** [let x = expr] followed by rest of program *)
