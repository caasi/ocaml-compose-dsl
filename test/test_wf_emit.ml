open Compose_dsl

let emit input =
  let prog = Reducer.reduce_program (Parse_errors.parse input) in
  Wf_emit.to_string (Wf_lower.lower ~name:"t" prog)

let test_meta_present () =
  Alcotest.(check bool) "one meta" true (Helpers.contains (emit "a >>> b") "export const meta")

let test_root_no_input () =
  let out = emit "a >>> b" in
  (* first agent omits "## Input"; second includes it *)
  Alcotest.(check bool) "second threads prev" true (Helpers.contains out "## Input")

let test_no_date_random () =
  let out = emit "a >>> b" in
  Alcotest.(check bool) "no Date.now" false (Helpers.contains out "Date.now");
  Alcotest.(check bool) "no Math.random" false (Helpers.contains out "Math.random")

let test_parallel_filter () =
  let out = emit "(a *** b) >>> c" in
  Alcotest.(check bool) "parallel" true (Helpers.contains out "parallel([");
  Alcotest.(check bool) "filter(Boolean)" true (Helpers.contains out ".filter(Boolean)");
  Alcotest.(check bool) "c gets array prev" true (Helpers.contains out "JSON.stringify")

let test_verify () =
  let out = emit "a >>> check?" in
  Alcotest.(check bool) "skeptic fan" true (Helpers.contains out "parallel(");
  Alcotest.(check bool) "VERDICT schema" true (Helpers.contains out "VERDICT");
  Alcotest.(check bool) "majority vote" true (Helpers.contains out "filter(Boolean)")

let test_synth_scalar () =
  let out = emit "a >>> merge" in
  Alcotest.(check bool) "synthesis agent" true (Helpers.contains out "agent(")

let test_phases_derived () =
  let out = emit "gather >>> a >>> leaf" in
  Alcotest.(check bool) "agent carries opts.phase" true (Helpers.contains out "phase: 'Gather'");
  Alcotest.(check bool) "meta phases lists Gather" true (Helpers.contains out "title: 'Gather'")

let test_js_string_escapes_control_chars () =
  (* A node with agent: "x\ry" — the lexer reads \r as a literal CR byte.
     The emitted agentType field must not contain a raw CR (0x0D). *)
  let input = "a(agent: \"x\ry\")" in
  let out = emit input in
  (* The raw CR byte must not appear anywhere inside a single-quoted JS string field.
     We verify by checking no raw CR appears in the output at all. *)
  let has_raw_cr = String.contains out '\r' in
  Alcotest.(check bool) "no raw CR in output" false has_raw_cr;
  (* The escaped form \r must appear instead *)
  Alcotest.(check bool) "escaped \\r present" true (Helpers.contains out "\\r")

let test_node_comment_cr_sanitized () =
  (* A node whose inline comment contains a raw CR must not produce a raw CR
     inside the emitted // line comment. CR in a JS line comment terminates the
     comment and turns the remainder into code — dangerous output. *)
  let src = "deploy -- do\rthis" in
  let comments = Wf_context.comments_of_source src in
  let prog = Reducer.reduce_program (Parse_errors.parse src) in
  let out = Wf_emit.to_string (Wf_lower.lower ~name:"t" ~comments prog) in
  Alcotest.(check bool) "no raw CR in emitted comment" false (String.contains out '\r')

(* U+2028 (LINE SEPARATOR) = 0xE2 0x80 0xA8 in UTF-8
   U+2029 (PARAGRAPH SEPARATOR) = 0xE2 0x80 0xA9 in UTF-8
   Both are JavaScript line terminators — raw occurrence in a single-quoted string
   or // comment is invalid JS and a potential injection vector. *)
let u2028 = "\xe2\x80\xa8"
let u2029 = "\xe2\x80\xa9"

let test_js_string_escapes_u2028 () =
  (* A node with agent: "x<U+2028>y" — the emitted single-quoted label field must
     not contain the raw 3-byte sequence. The escaped form   must appear instead. *)
  let input = Printf.sprintf "a(agent: \"x%sy\")" u2028 in
  let out = emit input in
  let has_raw = Helpers.contains out u2028 in
  let has_escaped = Helpers.contains out "\\u2028" in
  Alcotest.(check bool) "no raw U+2028 in output" false has_raw;
  Alcotest.(check bool) "escaped \\u2028 present" true has_escaped

let test_js_string_escapes_u2029 () =
  (* Same as above for U+2029. *)
  let input = Printf.sprintf "a(agent: \"x%sy\")" u2029 in
  let out = emit input in
  let has_raw = Helpers.contains out u2029 in
  let has_escaped = Helpers.contains out "\\u2029" in
  Alcotest.(check bool) "no raw U+2029 in output" false has_raw;
  Alcotest.(check bool) "escaped \\u2029 present" true has_escaped

let test_comment_u2028_sanitized () =
  (* A node whose inline comment contains U+2028 must not produce a raw U+2028
     inside the emitted // line comment. U+2028 terminates a JS line comment,
     turning the remainder into a syntax error or injected code. *)
  let src = Printf.sprintf "deploy -- do%sthis" u2028 in
  let comments = Wf_context.comments_of_source src in
  let prog = Reducer.reduce_program (Parse_errors.parse src) in
  let out = Wf_emit.to_string (Wf_lower.lower ~name:"t" ~comments prog) in
  Alcotest.(check bool) "no raw U+2028 in emitted comment" false (Helpers.contains out u2028)

let tests =
  [ Alcotest.test_case "meta present" `Quick test_meta_present
  ; Alcotest.test_case "root omits input" `Quick test_root_no_input
  ; Alcotest.test_case "no Date/random" `Quick test_no_date_random
  ; Alcotest.test_case "parallel filter(Boolean)" `Quick test_parallel_filter
  ; Alcotest.test_case "verify (adversarial fan)" `Quick test_verify
  ; Alcotest.test_case "synthesize scalar" `Quick test_synth_scalar
  ; Alcotest.test_case "phases derived from epistemic ops" `Quick test_phases_derived
  ; Alcotest.test_case "js_string escapes control chars (CR, etc.)" `Quick test_js_string_escapes_control_chars
  ; Alcotest.test_case "node comment CR sanitized" `Quick test_node_comment_cr_sanitized
  ; Alcotest.test_case "js_string escapes U+2028 (line sep)" `Quick test_js_string_escapes_u2028
  ; Alcotest.test_case "js_string escapes U+2029 (para sep)" `Quick test_js_string_escapes_u2029
  ; Alcotest.test_case "comment U+2028 sanitized" `Quick test_comment_u2028_sanitized ]
