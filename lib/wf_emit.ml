open Wf_ir

let str = PPrint.string
let (^^) = PPrint.(^^)
let nl = PPrint.hardline
let lines docs = PPrint.separate nl docs

(* Detect the 3-byte UTF-8 sequence for U+2028 (LINE SEPARATOR, 0xE2 0x80 0xA8)
   or U+2029 (PARAGRAPH SEPARATOR, 0xE2 0x80 0xA9) starting at index i in s.
   Both are JavaScript source line terminators and must be escaped in JS strings
   and line comments. *)
let is_ls_ps s i len =
  i + 2 < len
  && Char.code s.[i]   = 0xE2
  && Char.code s.[i+1] = 0x80
  && (Char.code s.[i+2] = 0xA8 || Char.code s.[i+2] = 0xA9)

(* JS single-quoted string literal — escapes \, ', ASCII control chars, and
   Unicode line separators U+2028/U+2029 (JS line terminators). *)
let js_string s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '\'';
  let n = String.length s in
  let i = ref 0 in
  while !i < n do
    if is_ls_ps s !i n then begin
      (* U+2028 → \u2028, U+2029 → \u2029 *)
      let code = if Char.code s.[!i + 2] = 0xA8 then "\\u2028" else "\\u2029" in
      Buffer.add_string b code;
      i := !i + 3
    end else begin
      (match s.[!i] with
       | '\\' -> Buffer.add_string b "\\\\"
       | '\'' -> Buffer.add_string b "\\'"
       | '\n' -> Buffer.add_string b "\\n"
       | '\r' -> Buffer.add_string b "\\r"
       | '\t' -> Buffer.add_string b "\\t"
       | '\x08' -> Buffer.add_string b "\\b"
       | '\x0C' -> Buffer.add_string b "\\f"
       | c when Char.code c < 0x20 ->
         Buffer.add_string b (Printf.sprintf "\\x%02x" (Char.code c))
       | c -> Buffer.add_char b c);
      incr i
    end
  done;
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

(* Replace any control characters (CR, LF, and all bytes < 0x20) or Unicode
   line separators U+2028/U+2029 in a comment line with a space, so the text is
   safe to embed in a // JS line comment (U+2028/U+2029 terminate JS line comments
   just like a newline would). *)
let sanitize_comment_line s =
  let b = Buffer.create (String.length s) in
  let n = String.length s in
  let i = ref 0 in
  while !i < n do
    if is_ls_ps s !i n then begin
      Buffer.add_char b ' ';
      i := !i + 3
    end else begin
      (let c = s.[!i] in
       if Char.code c < 0x20 then Buffer.add_char b ' '
       else Buffer.add_char b c);
      incr i
    end
  done;
  Buffer.contents b

(* Optional comment document: "// <sanitized text>\n" or empty. *)
let comment_doc = function
  | Some c -> str ("// " ^ sanitize_comment_line c) ^^ nl
  | None -> PPrint.empty

(* returns (document, var_name, shape). The var/shape feed the next node's prev. *)
let rec emit_node ~prev (n : wf_node) : PPrint.document * string * shape =
  match n with
  | Agent a ->
    let var = fresh_var a.label in
    (* phase is carried in opts (opts.phase), not a separate phase() statement *)
    let call = str (Printf.sprintf "const %s = await agent(%s, %s)" var (prompt_expr a ~prev) (opts a)) in
    (comment_doc a.comment ^^ call, var, Scalar)
  | Seq ns -> emit_seq ~prev ns
  | Parallel ns ->
    (* Each branch root receives the SAME prev (the parallel's input), per the B1 contract. *)
    let thunk n =
      match n with
      | Agent a ->
        let thunk_doc = str (Printf.sprintf "() => agent(%s, %s)" (prompt_expr a ~prev) (opts a)) in
        comment_doc a.comment ^^ thunk_doc
      | (Seq _ | Parallel _) ->
        (* A Seq/Parallel branch (e.g. (a >>> b) &&& c) hoists into an inline async IIFE thunk. *)
        let (d, last, _) = emit_node ~prev n in
        str "() => (async () => {"
        ^^ PPrint.nest 2 (nl ^^ d ^^ nl ^^ str (Printf.sprintf "return %s" last)) ^^ nl
        ^^ str "})()"
      | Verify _ | Synthesize _ ->
        failwith "unreachable: check/merge in a branch is rejected by Wf_lower (Task 7)"
    in
    let var = Printf.sprintf "par%d" (fresh ()) in
    let arr = PPrint.separate (str "," ^^ nl) (List.map thunk ns) in
    let d = str (Printf.sprintf "const %s = (await parallel([" var)
            ^^ PPrint.nest 2 (nl ^^ arr) ^^ nl ^^ str "])).filter(Boolean)" in
    (d, var, Array)
  | Synthesize a ->
    let p = js_template_body a.prompt in
    let hint = match a.out_hint with Some o -> Printf.sprintf "\\n\\nReturn a %s." o | None -> "" in
    let body = (match prev with
      | Some (v, Array) ->
        Printf.sprintf "%s%s\\n\\n## Inputs\\n${%s.map((r,i)=>`### ${i}\\n${r}`).join('\\n')}" p hint v
      | Some (v, Scalar) -> Printf.sprintf "%s%s\\n\\n## Input\\n${%s}" p hint v
      | None -> p ^ hint (* unreachable: root merge rejected by Wf_lower *)) in
    let var = fresh_var a.label in
    let d = str (Printf.sprintf "const %s = await agent(`%s`, %s)" var body (opts a)) in
    (comment_doc a.comment ^^ d, var, Scalar)
  | Verify { spec; skeptics } ->
    let subj = match prev with
      | Some (v, Array)  -> Printf.sprintf "JSON.stringify(%s)" v
      | Some (v, Scalar) -> v
      | None -> "''" (* unreachable: root check rejected by Wf_lower *) in
    let var = Printf.sprintf "verdicts%d" (fresh ()) in
    let passed = Printf.sprintf "passed%d" (fresh ()) in
    (* spec.label is always "check" (a fixed DSL keyword) in the current lowerer, so
       js_template_body here is defense-in-depth: if a future Verify variant ever allows
       a user-supplied label, backtick / ${ injection is already prevented. *)
    let escaped_label = js_template_body spec.label in
    let d = lines [
      str (Printf.sprintf "const %s = (await parallel(Array.from({length: %d}, (_, i) => () =>" var skeptics);
      PPrint.nest 2 (str (Printf.sprintf
        "agent(`Adversarially verify the following; try to REFUTE it, default refuted if unsure.\\n\\n## Subject\\n${%s}`, { label: `%s:skeptic-${i}`, schema: VERDICT }))))"
        subj escaped_label));
      str ".filter(Boolean)";
      str (Printf.sprintf "const %s = %s.filter(v => !v.refuted).length >= Math.ceil(%d / 2)" passed var skeptics) ] in
    (comment_doc spec.comment ^^ d, passed, Scalar)

and emit_seq ~prev = function
  | [] -> (PPrint.empty, "undefined", Scalar)
  | [n] -> emit_node ~prev n
  | n :: rest ->
    let (d1, v, sh) = emit_node ~prev n in
    let (d2, v2, sh2) = emit_seq ~prev:(Some (v, sh)) rest in
    (d1 ^^ nl ^^ d2, v2, sh2)

let rec has_verify = function
  | Verify _ -> true
  | Agent _ | Synthesize _ -> false
  | Seq ns | Parallel ns -> List.exists has_verify ns

let collect_phases (n : wf_node) : string list =
  let seen = ref [] in
  let rec go = function
    | Agent { phase = Some p; _ } -> if not (List.mem p !seen) then seen := !seen @ [p]
    | Agent _ | Verify _ | Synthesize _ -> ()
    | Seq ns | Parallel ns -> List.iter go ns
  in go n;
  match !seen with [] -> ["Run"] | ps -> ps

let to_string (t : t) =
  fresh_counter := 0;   (* deterministic var names per render → stable golden output *)
  let auto_note = str "// Generated by ocaml-compose-dsl --emit workflow. Runs autonomously; steps that imply human input do not pause." in
  let header = List.map (fun h -> str ("// " ^ sanitize_comment_line h)) t.header in
  let phases = collect_phases t.root in
  let phases_str =
    "[" ^ String.concat ", " (List.map (fun p -> Printf.sprintf "{ title: %s }" (js_string p)) phases) ^ "]" in
  let meta = lines [
    str "export const meta = {";
    str (Printf.sprintf "  name: %s," (js_string t.name));
    str (Printf.sprintf "  description: %s," (js_string t.description));
    str (Printf.sprintf "  phases: %s," phases_str);
    str "}" ] in
  let verdict_const =
    if has_verify t.root then
      [str "const VERDICT = { type: 'object', properties: { refuted: { type: 'boolean' } }, required: ['refuted'] }"]
    else [] in
  let (body, last, _) = emit_node ~prev:None t.root in
  let doc = lines ([auto_note] @ header @ [meta] @ verdict_const @ [str ""; body; str (Printf.sprintf "return %s" last)]) ^^ nl in
  let buf = Buffer.create 1024 in
  PPrint.ToBuffer.pretty 1.0 100 buf doc;
  Buffer.contents buf
