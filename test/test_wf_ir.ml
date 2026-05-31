open Compose_dsl

let test_construct () =
  let a : Wf_ir.agent_spec =
    { label = "x"; prompt = "x"; agent_type = None;
      out_hint = None; comment = None; phase = None }
  in
  let t : Wf_ir.t =
    { name = "demo"; description = "d"; header = []; root = Wf_ir.Agent a }
  in
  Alcotest.(check string) "name" "demo" t.name

let test_emit_error () =
  Alcotest.check_raises "raises Emit_error"
    (Wf_ir.Emit_error ({ Ast.line = 1; col = 1 }, "boom"))
    (fun () -> raise (Wf_ir.Emit_error ({ Ast.line = 1; col = 1 }, "boom")))

let tests =
  [ Alcotest.test_case "construct IR" `Quick test_construct
  ; Alcotest.test_case "Emit_error" `Quick test_emit_error ]
