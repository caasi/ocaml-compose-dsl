open Ast

let err pos msg = raise (Wf_ir.Emit_error (pos, msg))

let rec value_to_text = function
  | String s -> s
  | Ident s -> s
  | Number s -> s
  | List vs -> "[" ^ String.concat ", " (List.map value_to_text vs) ^ "]"

(* Pull prompt:/agent: out; fold the remaining named args into a Parameters line.
   ~line is the source line of the node (from expr.loc.start.line), used for
   comment attachment when a comments list is provided. *)
let agent_spec_of_app ~line ~comments (e : expr) (callee_name : string) (args : call_arg list) =
  let prompt = ref None and agent_type = ref None and params = ref [] in
  List.iter (function
    | Named { key = "prompt"; value = (String s | Ident s) } -> prompt := Some s
    | Named { key = "prompt"; value } ->
        err e.loc.start
          (Printf.sprintf "prompt: value must be a string or ident, got %s" (value_to_text value))
    | Named { key = "agent"; value = (String s | Ident s) } -> agent_type := Some s
    | Named { key; value } -> params := (key ^ "=" ^ value_to_text value) :: !params
    | Positional _ -> err e.loc.start
        "higher-order application (positional args) not supported by --emit workflow (v1)")
    args;
  let base = match !prompt with Some p -> p | None -> callee_name in
  let params_line =
    match List.rev !params with [] -> "" | ps -> "\n\nParameters: " ^ String.concat ", " ps in
  let out_hint = match e.type_ann with Some { output; _ } -> Some output | None -> None in
  (* Best-effort: attach the comment on the same line as the node, or the
     immediately-preceding line (leading comment style).  Same-line wins if both exist. *)
  let comment =
    match List.assoc_opt line comments with
    | Some _ as c -> c
    | None -> List.assoc_opt (line - 1) comments
  in
  { Wf_ir.label = callee_name; prompt = base ^ params_line;
    agent_type = !agent_type; out_hint; comment; phase = None }

(* Map an epistemic operator name to its IR node, or None if it's a plain agent.
   Not self-recursive and does not call lower_expr/flatten_seq/flatten_par, so plain let. *)
let epistemic_node ~comments (e : expr) (name : string) (args : call_arg list) : Wf_ir.wf_node option =
  let line = e.loc.start.line in
  let spec () = agent_spec_of_app ~line ~comments e name args in
  match name with
  | "merge"  -> Some (Wf_ir.Synthesize (spec ()))
  | "check"  -> Some (Wf_ir.Verify { spec = spec (); skeptics = 3 })
  | "leaf"   -> Some (Wf_ir.Agent { (spec ()) with phase = Some "Leaf" })
  | "gather" -> Some (Wf_ir.Agent { (spec ()) with phase = Some "Gather" })
  | "branch" -> Some (Wf_ir.Agent { (spec ()) with phase = Some "Branch" })
  | _ -> None

(* Lower a single expression to a wf_node.
   ~comments is the recovered (line, text) list from Wf_context.comments_of_source. *)
let rec lower_expr ~comments (e : expr) : Wf_ir.wf_node =
  match e.desc with
  | Question inner ->
    (match inner.desc with
     | Var "check" ->
       let line = inner.loc.start.line in
       Wf_ir.Verify { spec = agent_spec_of_app ~line ~comments inner "check" []; skeptics = 3 }
     | App ({ desc = Var "check"; _ }, args) ->
       let line = inner.loc.start.line in
       Wf_ir.Verify { spec = agent_spec_of_app ~line ~comments inner "check" args; skeptics = 3 }
     | _ -> err e.loc.start "'?' is only supported on 'check' by --emit workflow (v1)")
  | Var name ->
    let line = e.loc.start.line in
    (match epistemic_node ~comments e name [] with
     | Some n -> n
     | None -> Wf_ir.Agent (agent_spec_of_app ~line ~comments e name []))
  | App ({ desc = Var name; _ }, args) ->
    let line = e.loc.start.line in
    (match epistemic_node ~comments e name args with
     | Some n -> n
     | None -> Wf_ir.Agent (agent_spec_of_app ~line ~comments e name args))
  | Group inner -> lower_expr ~comments inner
  | Seq _ ->
    (match flatten_seq ~comments e with
     | [] -> err e.loc.start "empty pipeline: nothing to emit"
     | nodes -> Wf_ir.Seq nodes)
  | Par _ | Fanout _ ->
    let branches = flatten_par ~comments e in
    if List.exists contains_verify_or_synth branches then
      err e.loc.start
        "check/merge inside a '***'/'&&&' parallel branch is not supported by --emit workflow (v1)";
    Wf_ir.Parallel branches
  | Alt _ -> err e.loc.start "'|||' (alternation) not supported by --emit workflow (v1)"
  | Loop _ -> err e.loc.start "'loop' not supported by --emit workflow (v1)"
  | Unit -> err e.loc.start "empty pipeline: nothing to emit"
  | _ -> err e.loc.start "unsupported construct: --emit workflow (v1) supports named nodes, >>>, ***, &&&, and the epistemic operators (gather/branch/leaf/merge/check)"

and flatten_seq ~comments (e : expr) : Wf_ir.wf_node list =
  match e.desc with
  | Seq (a, b) -> flatten_seq ~comments a @ flatten_seq ~comments b
  | Group inner -> flatten_seq ~comments inner
  | Unit -> []                       (* identity: drop from the chain *)
  | _ -> [lower_expr ~comments e]

and flatten_par ~comments (e : expr) : Wf_ir.wf_node list =
  match e.desc with
  | Par (a, b) | Fanout (a, b) -> flatten_par ~comments a @ flatten_par ~comments b
  | Group inner -> flatten_par ~comments inner
  | _ -> [lower_expr ~comments e]

(* Recursively check whether a wf_node subtree contains Verify or Synthesize. *)
and contains_verify_or_synth = function
  | Wf_ir.Verify _ | Wf_ir.Synthesize _ -> true
  | Wf_ir.Agent _ -> false
  | Wf_ir.Seq ns | Wf_ir.Parallel ns -> List.exists contains_verify_or_synth ns

(* Reject Verify/Synthesize at root position (they need an upstream result). *)
let reject_root_verify_synth pos = function
  | Wf_ir.Verify _ | Wf_ir.Synthesize _ ->
    err pos "check/merge needs an upstream result to verify/fuse"
  | _ -> ()

(* Optional args added now (even though header/description are wired in Task 13),
   so later tasks never change this signature and break earlier callers.
   ~comments: (line, text) list from Wf_context.comments_of_source — threaded
   through lower_expr for best-effort node comment attachment. *)
let lower ?(comments = []) ?(header = []) ?description ~name (prog : Ast.program) : Wf_ir.t =
  let root = match prog with
    | [] -> err { line = 1; col = 1 } "empty pipeline: nothing to emit"
    | [e] -> lower_expr ~comments e
    | _ -> err (List.hd prog).loc.start
               "multi-statement programs not supported by --emit workflow (v1)"
  in
  (* Reject check/merge at root position — they have no upstream. *)
  let first_pos = (List.hd prog).loc.start in
  (match root with
   | Wf_ir.Seq (first :: _) -> reject_root_verify_synth first_pos first
   | other -> reject_root_verify_synth first_pos other);
  let description = match description with Some d -> d | None -> "Generated from " ^ name in
  { name; description; header; root }

(* Interactive-ident advisory (Task 12) *)
let interactive_set = ["ask_questions"; "present_design"; "propose"; "review"; "ask"; "confirm"; "approve"; "feedback"]

let interactive_idents (t : Wf_ir.t) : string list =
  let found = ref [] in
  let note l =
    if List.mem l interactive_set && not (List.mem l !found)
    then found := !found @ [l]
  in
  let rec go = function
    | Wf_ir.Agent a -> note a.label
    | Wf_ir.Synthesize a -> note a.label
    | Wf_ir.Verify { spec; _ } -> note spec.label
    | Wf_ir.Seq ns | Wf_ir.Parallel ns -> List.iter go ns
  in
  go t.root; !found
