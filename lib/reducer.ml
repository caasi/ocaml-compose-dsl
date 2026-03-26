open Ast

exception Reduce_error of pos * string

(* Desugar Let into App(Lambda) *)
let rec desugar (e : expr) : expr =
  match e.desc with
  | Let (name, value, body) ->
    let value' = desugar value in
    let body' = desugar body in
    { e with desc = App ({ e with desc = Lambda ([name], body') }, [value']) }
  | Seq (a, b) -> { e with desc = Seq (desugar a, desugar b) }
  | Par (a, b) -> { e with desc = Par (desugar a, desugar b) }
  | Fanout (a, b) -> { e with desc = Fanout (desugar a, desugar b) }
  | Alt (a, b) -> { e with desc = Alt (desugar a, desugar b) }
  | Loop body -> { e with desc = Loop (desugar body) }
  | Group inner -> { e with desc = Group (desugar inner) }
  | Lambda (params, body) -> { e with desc = Lambda (params, desugar body) }
  | App (fn, args) -> { e with desc = App (desugar fn, List.map desugar args) }
  | Node _ | Var _ | Question _ -> e

(* Substitute Var(name) with replacement in expr *)
let rec substitute (name : string) (replacement : expr) (e : expr) : expr =
  match e.desc with
  | Var v when v = name -> replacement
  | Var _ -> e
  | Node _ | Question _ -> e
  | Seq (a, b) -> { e with desc = Seq (substitute name replacement a, substitute name replacement b) }
  | Par (a, b) -> { e with desc = Par (substitute name replacement a, substitute name replacement b) }
  | Fanout (a, b) -> { e with desc = Fanout (substitute name replacement a, substitute name replacement b) }
  | Alt (a, b) -> { e with desc = Alt (substitute name replacement a, substitute name replacement b) }
  | Loop body -> { e with desc = Loop (substitute name replacement body) }
  | Group inner -> { e with desc = Group (substitute name replacement inner) }
  | Lambda (params, body) ->
    (* Don't substitute if name is shadowed by a lambda param *)
    if List.mem name params then e
    else { e with desc = Lambda (params, substitute name replacement body) }
  | App (fn, args) ->
    { e with desc = App (substitute name replacement fn, List.map (substitute name replacement) args) }
  | Let (n, v, b) ->
    let v' = substitute name replacement v in
    if n = name then { e with desc = Let (n, v', b) }  (* shadowed *)
    else { e with desc = Let (n, v', substitute name replacement b) }

(* Beta reduce: App(Lambda(params, body), args) -> substitute params with args in body *)
let rec beta_reduce (e : expr) : expr =
  match e.desc with
  | App (fn, args) ->
    let fn' = beta_reduce fn in
    let args' = List.map beta_reduce args in
    (match fn'.desc with
     | Lambda (params, body) ->
       let n_params = List.length params in
       let n_args = List.length args' in
       if n_params <> n_args then
         raise (Reduce_error (e.loc.start,
           Printf.sprintf "arity mismatch: expected %d arguments but got %d" n_params n_args));
       let result = List.fold_left2
         (fun acc param arg -> substitute param arg acc)
         body params args'
       in
       beta_reduce result  (* reduce again in case substitution created new redexes *)
     | Node n ->
       raise (Reduce_error (e.loc.start,
         Printf.sprintf "'%s' is not a function and cannot be applied" n.name))
     | Var v ->
       raise (Reduce_error (e.loc.start,
         Printf.sprintf "undefined variable '%s'" v))
     | _ ->
       raise (Reduce_error (e.loc.start, "expression is not a function and cannot be applied")))
  | Seq (a, b) -> { e with desc = Seq (beta_reduce a, beta_reduce b) }
  | Par (a, b) -> { e with desc = Par (beta_reduce a, beta_reduce b) }
  | Fanout (a, b) -> { e with desc = Fanout (beta_reduce a, beta_reduce b) }
  | Alt (a, b) -> { e with desc = Alt (beta_reduce a, beta_reduce b) }
  | Loop body -> { e with desc = Loop (beta_reduce body) }
  | Group inner -> { e with desc = Group (beta_reduce inner) }
  | Lambda _ -> e  (* unapplied lambda -- will be caught by verify *)
  | Node _ | Var _ | Question _ | Let _ -> e

(* Verify no unreduced nodes remain *)
let rec verify (e : expr) : unit =
  match e.desc with
  | Lambda _ ->
    raise (Reduce_error (e.loc.start, "lambda expression not fully applied"))
  | Var v ->
    raise (Reduce_error (e.loc.start,
      Printf.sprintf "undefined variable '%s'" v))
  | App _ ->
    raise (Reduce_error (e.loc.start, "unreduced application"))
  | Let _ ->
    raise (Reduce_error (e.loc.start, "unreduced let binding"))
  | Seq (a, b) | Par (a, b) | Fanout (a, b) | Alt (a, b) -> verify a; verify b
  | Loop body | Group body -> verify body
  | Node _ | Question _ -> ()

let reduce (e : expr) : expr =
  let e = desugar e in
  let e = beta_reduce e in
  verify e;
  e
