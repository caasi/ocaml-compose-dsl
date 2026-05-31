open Ast

let err pos msg = raise (Wf_ir.Emit_error (pos, msg))

let rec value_to_text = function
  | String s -> s
  | Ident s -> s
  | Number s -> s
  | List vs -> "[" ^ String.concat ", " (List.map value_to_text vs) ^ "]"

(* Pull prompt:/agent: out; fold the remaining named args into a Parameters line. *)
let agent_spec_of_app (e : expr) (callee_name : string) (args : call_arg list) =
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
  { Wf_ir.label = callee_name; prompt = base ^ params_line;
    agent_type = !agent_type; out_hint; comment = None; phase = None }

(* Lower a single expression to a wf_node (epistemic + structure added in later tasks). *)
let lower_expr (e : expr) : Wf_ir.wf_node =
  match e.desc with
  | Var name ->
    Wf_ir.Agent (agent_spec_of_app e name [])
  | App ({ desc = Var name; _ }, args) ->
    Wf_ir.Agent (agent_spec_of_app e name args)
  | Unit -> err e.loc.start "empty pipeline: nothing to emit"
  | _ -> err e.loc.start "unsupported construct (todo: later tasks)"

(* Optional args added now (even though comments/header/description are wired in
   Task 11/13), so later tasks never change this signature and break earlier callers. *)
let lower ?(comments = []) ?(header = []) ?description ~name (prog : Ast.program) : Wf_ir.t =
  ignore comments;  (* consumed in Task 11 for node-comment attachment *)
  let root = match prog with
    | [] -> err { line = 1; col = 1 } "empty pipeline: nothing to emit"
    | [e] -> lower_expr e
    | _ -> err (List.hd prog).loc.start
               "multi-statement programs not supported by --emit workflow (v1)"
  in
  let description = match description with Some d -> d | None -> "Generated from " ^ name in
  { name; description; header; root }
