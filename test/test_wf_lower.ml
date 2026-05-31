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

let tests =
  [ Alcotest.test_case "bare node" `Quick test_bare_node
  ; Alcotest.test_case "named args" `Quick test_named_args
  ; Alcotest.test_case "type-ann hint" `Quick test_type_ann_hint
  ; Alcotest.test_case "empty program" `Quick test_empty_program
  ; Alcotest.test_case "prompt: ident" `Quick test_prompt_ident ]
