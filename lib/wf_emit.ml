open Wf_ir

let str = PPrint.string
let (^^) = PPrint.(^^)
let nl = PPrint.hardline
let lines docs = PPrint.separate nl docs

(* JS single-quoted string literal — escapes \, ', newline. *)
let js_string s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '\'';
  String.iter (fun c -> match c with
    | '\\' -> Buffer.add_string b "\\\\"
    | '\'' -> Buffer.add_string b "\\'"
    | '\n' -> Buffer.add_string b "\\n"
    | c -> Buffer.add_char b c) s;
  Buffer.add_char b '\'';
  Buffer.contents b

(* Escape text for a `…` template literal: backslash, backtick, and ${ . *)
let js_template_body s =
  let b = Buffer.create (String.length s) in
  let n = String.length s in
  let i = ref 0 in
  while !i < n do
    (match s.[!i] with
     | '\\' -> Buffer.add_string b "\\\\"
     | '`'  -> Buffer.add_string b "\\`"
     | '$' when !i + 1 < n && s.[!i + 1] = '{' -> Buffer.add_string b "\\${"; incr i
     | c    -> Buffer.add_char b c);
    incr i
  done;
  Buffer.contents b

(* The prompt as a JS template literal, with optional out-hint + ## Input.
   Interpolations (${…}) are intentionally NOT escaped — they are emitter-controlled. *)
let prompt_expr (a : agent_spec) ~(prev : (string * shape) option) =
  let hint = match a.out_hint with Some o -> Printf.sprintf "\\n\\nReturn a %s." o | None -> "" in
  let input = match prev with
    | None -> ""
    | Some (expr, Scalar) -> Printf.sprintf "\\n\\n## Input\\n${%s}" expr
    | Some (expr, Array)  -> Printf.sprintf "\\n\\n## Input\\n${JSON.stringify(%s)}" expr in
  "`" ^ js_template_body a.prompt ^ hint ^ input ^ "`"

let opts (a : agent_spec) =
  let parts = [Printf.sprintf "label: %s" (js_string a.label)]
    @ (match a.agent_type with Some t -> [Printf.sprintf "agentType: %s" (js_string t)] | None -> [])
    @ (match a.phase with Some p -> [Printf.sprintf "phase: %s" (js_string p)] | None -> []) in
  "{ " ^ String.concat ", " parts ^ " }"

(* Resettable counter — reset at the top of to_string so golden output is deterministic. *)
let fresh_counter = ref 0
let fresh () = incr fresh_counter; !fresh_counter

(* A fresh, valid JS identifier. DSL labels may be hyphenated/Unicode/duplicated
   (a >>> a), so NEVER use the raw label as a const name — only inside opts.label. *)
let sanitize s =
  String.map (fun c -> if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
                          || (c >= '0' && c <= '9') || c = '_' then c else '_') s
let fresh_var label =
  let s = sanitize label in
  let s = if s = "" || not ((s.[0] >= 'a' && s.[0] <= 'z') || (s.[0] >= 'A' && s.[0] <= 'Z') || s.[0] = '_')
          then "n_" ^ s else s in
  Printf.sprintf "%s_%d" s (fresh ())

(* returns (document, var_name, shape). The var/shape feed the next node's prev. *)
let rec emit_node ~prev (n : wf_node) : PPrint.document * string * shape =
  match n with
  | Agent a ->
    let var = fresh_var a.label in
    let comment = match a.comment with Some c -> str ("// " ^ c) ^^ nl | None -> PPrint.empty in
    (* phase is carried in opts (opts.phase), not a separate phase() statement *)
    let call = str (Printf.sprintf "const %s = await agent(%s, %s)" var (prompt_expr a ~prev) (opts a)) in
    (comment ^^ call, var, Scalar)
  | Seq ns -> emit_seq ~prev ns
  | Parallel ns ->
    (* Each branch root receives the SAME prev (the parallel's input), per the B1 contract. *)
    let thunk n =
      match n with
      | Agent a -> str (Printf.sprintf "() => agent(%s, %s)" (prompt_expr a ~prev) (opts a))
      | (Seq _ | Parallel _) ->
        (* A Seq/Parallel branch (e.g. (a >>> b) &&& c) hoists into an inline async IIFE thunk. *)
        let (d, last, _) = emit_node ~prev n in
        str "() => (async () => {" ^^ nl
        ^^ PPrint.nest 2 (d ^^ nl ^^ str (Printf.sprintf "return %s" last)) ^^ nl
        ^^ str "})()"
      | Verify _ | Synthesize _ ->
        failwith "unreachable: check/merge in a branch is rejected by Wf_lower (Task 7)"
    in
    let var = Printf.sprintf "par%d" (fresh ()) in
    let arr = PPrint.separate (str "," ^^ nl) (List.map thunk ns) in
    let d = str (Printf.sprintf "const %s = (await parallel([" var)
            ^^ nl ^^ PPrint.nest 2 arr ^^ nl ^^ str "])).filter(Boolean)" in
    (d, var, Array)
  | _ -> failwith "Verify/Synthesize: Task 10"

and emit_seq ~prev = function
  | [] -> (PPrint.empty, "undefined", Scalar)
  | [n] -> emit_node ~prev n
  | n :: rest ->
    let (d1, v, sh) = emit_node ~prev n in
    let (d2, v2, sh2) = emit_seq ~prev:(Some (v, sh)) rest in
    (d1 ^^ nl ^^ d2, v2, sh2)

let to_string (t : t) =
  fresh_counter := 0;   (* deterministic var names per render → stable golden output *)
  let header = List.map (fun h -> str ("// " ^ h)) t.header in
  let meta = lines [
    str "export const meta = {";
    str (Printf.sprintf "  name: %s," (js_string t.name));
    str (Printf.sprintf "  description: %s," (js_string t.description));
    str "  phases: [{ title: 'Run' }],";   (* refined in Task 10 *)
    str "}" ] in
  let (body, last, _) = emit_node ~prev:None t.root in
  let doc = lines (header @ [meta; str ""; body; str (Printf.sprintf "return %s" last)]) ^^ nl in
  let buf = Buffer.create 1024 in
  PPrint.ToBuffer.pretty 1.0 100 buf doc;
  Buffer.contents buf
