open Compose_dsl
open Helpers

(* === Checker tests === *)

let test_check_question_with_alt () =
  let warnings = check_ok_with_warnings {|"ready"? >>> (go ||| stop)|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)

let test_check_question_without_alt () =
  let warnings = check_ok_with_warnings {|"ready"? >>> process >>> done|} in
  Alcotest.(check int) "one warning" 1 (List.length warnings);
  Alcotest.(check bool) "warning message" true
    (String.length (List.hd warnings).Checker.message > 0)

let test_check_question_with_intermediate_steps () =
  let warnings = check_ok_with_warnings {|"ok"? >>> log >>> transform >>> (yes ||| no)|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)

let test_check_question_alt_in_par_no_match () =
  let warnings = check_ok_with_warnings {|"ready"? >>> a *** (b ||| c)|} in
  Alcotest.(check int) "one warning" 1 (List.length warnings)

let test_check_question_in_loop () =
  let warnings = check_ok_with_warnings {|loop("pass"? >>> (exit ||| eval))|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)

let test_check_question_in_loop_no_alt () =
  let warnings = check_ok_with_warnings {|loop("pass"? >>> eval)|} in
  Alcotest.(check int) "one warning" 1 (List.length warnings)

let test_check_multiple_questions () =
  let warnings = check_ok_with_warnings {|"a"? >>> (x ||| y) >>> "b"? >>> (p ||| q)|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)

let test_check_multiple_questions_unmatched () =
  let warnings = check_ok_with_warnings {|"a"? >>> "b"? >>> (x ||| y)|} in
  Alcotest.(check int) "one warning (one unmatched)" 1 (List.length warnings)

let test_check_existing_alt_no_warning () =
  let warnings = check_ok_with_warnings {|a ||| b|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)

let test_check_question_in_group_with_alt () =
  let warnings = check_ok_with_warnings {|("ready"?) >>> (a ||| b)|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)

let test_check_question_in_fanout_branch () =
  let warnings = check_ok_with_warnings {|("ready"? >>> (a ||| b)) &&& c|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)

let test_check_question_in_fanout_branch_no_alt () =
  let warnings = check_ok_with_warnings {|("ready"? >>> process) &&& c|} in
  Alcotest.(check int) "one warning" 1 (List.length warnings)

let test_check_alt_before_question_still_warns () =
  (* ||| before ? should NOT cancel it — only downstream ||| matches *)
  let warnings = check_ok_with_warnings {|(a ||| b) >>> "ready"? >>> process|} in
  Alcotest.(check int) "one warning" 1 (List.length warnings)

let test_check_question_tail_as_alt_operand () =
  let warnings = check_ok_with_warnings {|(a >>> b >>> c?) ||| d|} in
  Alcotest.(check int) "one warning" 1 (List.length warnings);
  Alcotest.(check bool) "specific message" true
    (has_warning_containing "operand of '|||'" warnings)

let test_check_question_direct_alt_operand () =
  let warnings = check_ok_with_warnings {|c? ||| d|} in
  Alcotest.(check int) "one warning" 1 (List.length warnings);
  Alcotest.(check bool) "specific message" true
    (has_warning_containing "operand of '|||'" warnings)

let test_check_question_multiple_with_tail_alt_operand () =
  let warnings = check_ok_with_warnings {|("a"? >>> "b"?) ||| c|} in
  Alcotest.(check int) "two warnings" 2 (List.length warnings);
  Alcotest.(check bool) "has specific" true
    (has_warning_containing "operand of '|||'" warnings);
  Alcotest.(check bool) "has generic" true
    (has_warning_containing "without matching" warnings)

let test_check_question_not_at_tail_alt_operand () =
  let warnings = check_ok_with_warnings {|("ready"? >>> process) ||| fallback|} in
  Alcotest.(check int) "one warning" 1 (List.length warnings);
  Alcotest.(check bool) "generic message" true
    (has_warning_containing "without matching" warnings);
  Alcotest.(check bool) "not specific message" false
    (has_warning_containing "operand of '|||'" warnings)

let test_check_loop_plain_no_error () =
  let result = Checker.check (parse_ok "loop (a >>> b)") in
  Alcotest.(check int) "no warnings" 0 (List.length result.Checker.warnings)

let test_check_loop_unicode_no_error () =
  let result = Checker.check (parse_ok "loop (掃描 >>> 檢查)") in
  Alcotest.(check int) "no warnings" 0 (List.length result.Checker.warnings)

let test_parse_comment_on_node_question () =
  (* Comments are now dropped on Var, so just verify the structure *)
  let ast = parse_ok "validate -- important\n? >>> (a ||| b)" in
  match ast.desc with
  | Ast.Seq ({ desc = Ast.Question { desc = Ast.Var "validate"; _ }; _ }, _) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "unexpected AST: %s" (Printer.to_string ast))

let test_parse_comment_on_string_question () =
  let ast = parse_ok {|"hello" -- note
? >>> (a ||| b)|} in
  match ast.desc with
  | Ast.Seq ({ desc = Ast.Question { desc = Ast.StringLit "hello"; _ }; _ }, _) -> ()
  | _ -> Alcotest.fail (Printf.sprintf "unexpected AST: %s" (Printer.to_string ast))

(* === Checker loc tests === *)

let test_check_question_warning_loc () =
  let warnings = check_ok_with_warnings {|"ready"? >>> process >>> done|} in
  let w = List.hd warnings in
  Alcotest.(check int) "warning start line" 1 w.loc.start.line;
  Alcotest.(check int) "warning start col" 1 w.loc.start.col

let test_check_string_lit_no_error () =
  let _ = check_ok {|"hello" >>> a|} in
  ()

let test_check_string_lit_question_with_alt () =
  let warnings = check_ok_with_warnings {|"is valid"? >>> (yes ||| no)|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)

let test_check_unit_no_warnings () =
  let result = Checker.check (parse_ok "()") in
  Alcotest.(check int) "no warnings" 0 (List.length result.Checker.warnings)

let test_check_program_merges_warnings () =
  let prog = Helpers.parse_program_ok "a?; b?" in
  let reduced = Reducer.reduce_program prog in
  let result = Checker.check_program reduced in
  Alcotest.(check int) "two warnings (one per stmt)" 2
    (List.length result.Checker.warnings)

let test_check_program_no_warnings () =
  let prog = Helpers.parse_program_ok "a >>> b; c >>> d" in
  let reduced = Reducer.reduce_program prog in
  let result = Checker.check_program reduced in
  Alcotest.(check int) "no warnings" 0
    (List.length result.Checker.warnings)

let test_check_branch_with_merge () =
  let warnings = check_ok_with_warnings {|branch >>> explore >>> merge|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)

let test_check_branch_merge_with_args () =
  let warnings = check_ok_with_warnings {|branch(k: 3) >>> merge(strategy: "best")|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)

let test_check_branch_without_merge () =
  let warnings = check_ok_with_warnings {|branch >>> explore|} in
  Alcotest.(check int) "one warning" 1 (List.length warnings);
  Alcotest.(check bool) "warning message" true
    (has_warning_containing "branch" warnings);
  Alcotest.(check bool) "mentions merge" true
    (has_warning_containing "merge" warnings)

let test_check_merge_without_branch () =
  let warnings = check_ok_with_warnings {|merge >>> done|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)

let test_check_all_epistemic_no_warning () =
  let warnings = check_ok_with_warnings {|gather >>> branch >>> leaf >>> merge >>> check|} in
  Alcotest.(check int) "no warnings" 0 (List.length warnings)

let tests =
  [ "loop plain no error", `Quick, test_check_loop_plain_no_error
  ; "loop with unicode nodes", `Quick, test_check_loop_unicode_no_error
  ; "question with alt", `Quick, test_check_question_with_alt
  ; "question without alt", `Quick, test_check_question_without_alt
  ; "question with intermediate steps", `Quick, test_check_question_with_intermediate_steps
  ; "question alt in par no match", `Quick, test_check_question_alt_in_par_no_match
  ; "question in loop", `Quick, test_check_question_in_loop
  ; "question in loop no alt", `Quick, test_check_question_in_loop_no_alt
  ; "multiple questions", `Quick, test_check_multiple_questions
  ; "multiple questions unmatched", `Quick, test_check_multiple_questions_unmatched
  ; "existing alt no warning", `Quick, test_check_existing_alt_no_warning
  ; "question in group with alt", `Quick, test_check_question_in_group_with_alt
  ; "question in fanout branch", `Quick, test_check_question_in_fanout_branch
  ; "question in fanout branch no alt", `Quick, test_check_question_in_fanout_branch_no_alt
  ; "alt before question still warns", `Quick, test_check_alt_before_question_still_warns
  ; "question not at tail alt operand", `Quick, test_check_question_not_at_tail_alt_operand
  ; "question tail as alt operand", `Quick, test_check_question_tail_as_alt_operand
  ; "question direct alt operand", `Quick, test_check_question_direct_alt_operand
  ; "question multiple with tail alt operand", `Quick, test_check_question_multiple_with_tail_alt_operand
  ; "question warning loc", `Quick, test_check_question_warning_loc
  ; "string lit no error", `Quick, test_check_string_lit_no_error
  ; "string lit question with alt", `Quick, test_check_string_lit_question_with_alt
  ; "unit no warnings", `Quick, test_check_unit_no_warnings
  ; "program merges warnings", `Quick, test_check_program_merges_warnings
  ; "program no warnings", `Quick, test_check_program_no_warnings
  ; "branch with merge", `Quick, test_check_branch_with_merge
  ; "branch merge with args", `Quick, test_check_branch_merge_with_args
  ; "branch without merge", `Quick, test_check_branch_without_merge
  ; "merge without branch", `Quick, test_check_merge_without_branch
  ; "all epistemic no warning", `Quick, test_check_all_epistemic_no_warning
  ]
