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

let tests =
  [ Alcotest.test_case "meta present" `Quick test_meta_present
  ; Alcotest.test_case "root omits input" `Quick test_root_no_input
  ; Alcotest.test_case "no Date/random" `Quick test_no_date_random
  ; Alcotest.test_case "parallel filter(Boolean)" `Quick test_parallel_filter ]
