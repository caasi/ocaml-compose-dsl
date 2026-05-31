open Compose_dsl

let lower input =
  Wf_lower.lower ~name:"t" (Reducer.reduce_program (Parse_errors.parse input))

let agent_of = function Wf_ir.Agent a -> a | _ -> Alcotest.fail "expected Agent"

let test_bare_node () =
  let a = agent_of (lower "deploy").root in
  Alcotest.(check string) "label" "deploy" a.label;
  Alcotest.(check string) "prompt" "deploy" a.prompt

let test_named_args () =
  let a = agent_of (lower {|build(prompt: "do x", agent: "Explore", profile: static)|}).root in
  Alcotest.(check bool) "prompt has override + folded arg"
    true (Helpers.contains a.prompt "do x" && Helpers.contains a.prompt "profile=static");
  Alcotest.(check (option string)) "agent_type" (Some "Explore") a.agent_type

let test_type_ann_hint () =
  let a = agent_of (lower "summarize :: Sources -> Context").root in
  Alcotest.(check bool) "out_hint set" true (a.out_hint = Some "Context")

let test_empty_program () =
  Helpers.lower_fails lower "()" "empty pipeline"

let test_prompt_ident () =
  let a = agent_of (lower "node(prompt: foo)").root in
  Alcotest.(check string) "prompt uses ident value" "foo" a.prompt

let test_seq () =
  match (lower "a >>> b >>> c").root with
  | Wf_ir.Seq [Agent a; Agent b; Agent c] ->
    Alcotest.(check string) "labels" "a,b,c"
      (String.concat "," [a.label; b.label; c.label])
  | _ -> Alcotest.fail "expected flat Seq of 3 Agents"

let test_group_transparent () =
  match (lower "(a >>> b)").root with
  | Wf_ir.Seq [Agent _; Agent _] -> ()
  | _ -> Alcotest.fail "Group should be transparent"

let test_unit_dropped_in_seq () =
  match (lower "a >>> () >>> b").root with
  | Wf_ir.Seq [Agent _; Agent _] -> ()
  | _ -> Alcotest.fail "Unit dropped from Seq"

let test_fanout () =
  match (lower "a &&& b").root with
  | Wf_ir.Parallel [Agent _; Agent _] -> ()
  | _ -> Alcotest.fail "&&& → Parallel"

let test_par_flattened () =
  match (lower "a *** b *** c").root with
  | Wf_ir.Parallel [Agent _; Agent _; Agent _] -> ()
  | _ -> Alcotest.fail "*** → flat Parallel of 3"

let tests =
  [ Alcotest.test_case "bare node" `Quick test_bare_node
  ; Alcotest.test_case "named args" `Quick test_named_args
  ; Alcotest.test_case "type-ann hint" `Quick test_type_ann_hint
  ; Alcotest.test_case "empty program" `Quick test_empty_program
  ; Alcotest.test_case "prompt: ident" `Quick test_prompt_ident
  ; Alcotest.test_case "seq flattened" `Quick test_seq
  ; Alcotest.test_case "group transparent" `Quick test_group_transparent
  ; Alcotest.test_case "unit dropped in seq" `Quick test_unit_dropped_in_seq
  ; Alcotest.test_case "fanout to Parallel" `Quick test_fanout
  ; Alcotest.test_case "par flattened to Parallel" `Quick test_par_flattened ]
