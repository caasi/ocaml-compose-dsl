open Ast

exception Reduce_error of pos * string

module StringSet = Set.Make(String)

let fresh_counter = ref 0

let fresh_name base =
  incr fresh_counter;
  Printf.sprintf "%s$%d" base !fresh_counter

(* Collect free variables in an expression *)
let rec free_vars (e : expr) : StringSet.t =
  match e.desc with
  | Var v -> StringSet.singleton v
  | Node _ | Question _ -> StringSet.empty
  | Seq (a, b) | Par (a, b) | Fanout (a, b) | Alt (a, b) ->
    StringSet.union (free_vars a) (free_vars b)
  | Loop body | Group body -> free_vars body
  | Lambda (params, body) ->
    let fv = free_vars body in
    List.fold_left (fun s p -> StringSet.remove p s) fv params
  | App (fn, args) ->
    List.fold_left (fun s a -> StringSet.union s (free_vars a))
      (free_vars fn) args
  | Let (n, v, b) ->
    StringSet.union (free_vars v) (StringSet.remove n (free_vars b))

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
  | Var v when v = name ->
    (* Preserve type annotation from the original Var expression *)
    (match e.type_ann with
     | None -> replacement
     | Some _ -> { replacement with type_ann = e.type_ann })
  | Var _ -> e
  | Node _ | Question _ -> e
  | Seq (a, b) -> { e with desc = Seq (substitute name replacement a, substitute name replacement b) }
  | Par (a, b) -> { e with desc = Par (substitute name replacement a, substitute name replacement b) }
  | Fanout (a, b) -> { e with desc = Fanout (substitute name replacement a, substitute name replacement b) }
  | Alt (a, b) -> { e with desc = Alt (substitute name replacement a, substitute name replacement b) }
  | Loop body -> { e with desc = Loop (substitute name replacement body) }
  | Group inner -> { e with desc = Group (substitute name replacement inner) }
  | Lambda (params, body) ->
    if List.mem name params then e
    else
      (* Alpha-rename any param that would capture free vars in replacement *)
      let repl_fv = free_vars replacement in
      let params', body' = List.fold_left (fun (ps, b) p ->
        if StringSet.mem p repl_fv then
          let p' = fresh_name p in
          (p' :: ps, substitute p { e with desc = Var p'; type_ann = None } b)
        else (p :: ps, b)
      ) ([], body) params in
      let params' = List.rev params' in
      { e with desc = Lambda (params', substitute name replacement body') }
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
