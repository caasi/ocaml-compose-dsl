(* Workflow IR: the bridge between the Arrow AST and the emitted JS.
   Structure only — JS syntax lives in Wf_emit. *)

(* Raised by Wf_lower on any construct unsupported by --emit workflow (v1). *)
exception Emit_error of Ast.pos * string

(* Shape of the value threaded as `prev` into a node. *)
type shape = Scalar | Array

type agent_spec = {
  label      : string;        (* node name -> opts.label *)
  prompt     : string;        (* prompt: arg, else label + folded named args *)
  agent_type : string option; (* agent: arg -> opts.agentType *)
  out_hint   : string option; (* type_ann.output -> "Return a <Out>." prompt line *)
  comment    : string option; (* recovered source comment -> // above the call *)
  phase      : string option; (* gather/branch/leaf -> opts.phase on the agent() *)
}

type wf_node =
  | Agent      of agent_spec
  | Seq        of wf_node list
  | Parallel   of wf_node list
  | Synthesize of agent_spec                            (* merge *)
  | Verify     of { spec : agent_spec; skeptics : int } (* check / check? *)

type t = {
  name        : string;
  description : string;
  header      : string list;
  root        : wf_node;
}
