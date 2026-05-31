open Compose_dsl

(* Read a file by relative path — cwd is _build/default/test/ at test run time *)
let read_file path =
  let ic = open_in path in
  let n = in_channel_length ic in
  let s = Bytes.create n in
  really_input ic s 0 n;
  close_in ic;
  Bytes.to_string s

let emit_file path =
  let src = read_file path in
  let prog = Reducer.reduce_program (Parse_errors.parse src) in
  let name = Filename.remove_extension (Filename.basename path) in
  (* Recover comments and derive header/description, matching CLI behaviour *)
  let comments = Wf_context.comments_of_source src in
  let header = Wf_context.leading_block comments in
  let description =
    Some (Wf_context.derive_description (List.map snd comments)
           ~fallback:("Generated from " ^ name)) in
  Wf_emit.to_string (Wf_lower.lower ~name ~comments ~header ?description prog)

let test_brainstorming () =
  let expected = read_file "brainstorming.js" in
  let actual   = emit_file "brainstorming.arr" in
  Alcotest.(check string) "brainstorming golden" expected actual

let test_release () =
  let expected = read_file "release.js" in
  let actual   = emit_file "release.arr" in
  Alcotest.(check string) "release golden" expected actual

let tests =
  [ Alcotest.test_case "brainstorming" `Quick test_brainstorming
  ; Alcotest.test_case "release"       `Quick test_release
  ]
