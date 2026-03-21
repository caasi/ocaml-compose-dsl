type value =
  | String of string
  | Ident of string
  | Number of string
  | List of value list

type arg = { key : string; value : value }

type node = { name : string; args : arg list; comments : string list }

type question_term =
  | QNode of node
  | QString of string

type expr =
  | Node of node
  | Seq of expr * expr (** [>>>] *)
  | Par of expr * expr (** [***] *)
  | Fanout of expr * expr (** [&&&] *)
  | Alt of expr * expr (** [|||] *)
  | Loop of expr
  | Group of expr
  | Question of question_term
