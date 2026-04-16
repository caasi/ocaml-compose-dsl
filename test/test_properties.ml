(* Generated from constraints/*.md — property-based tests via QCheck *)

open Compose_dsl

(* === Generators === *)

let keywords = ["let"; "in"; "loop"]
let epistemic = ["branch"; "merge"; "leaf"; "check"; "gather"]
let reserved = keywords @ epistemic @ ["done"]

(* Non-empty lowercase ASCII identifier, excluding reserved words *)
let gen_ident =
  let open QCheck.Gen in
  let alpha = oneof (List.init 26 (fun i -> return (Char.chr (Char.code 'a' + i)))) in
  string_size ~gen:alpha (1 -- 12)

let gen_safe_ident =
  QCheck.Gen.( gen_ident >>= fun s ->
    if List.mem s reserved then return ("x" ^ s) else return s )

let arb_ident =
  QCheck.make ~print:Fun.id gen_safe_ident

(* 3 distinct safe identifiers *)
let gen_three_idents =
  let open QCheck.Gen in
  gen_safe_ident >>= fun a ->
  gen_safe_ident >>= fun b ->
  gen_safe_ident >>= fun c ->
  let b = if b = a then b ^ "b" else b in
  let c = if c = a || c = b then c ^ "c" else c in
  return (a, b, c)

let arb_three_idents =
  QCheck.make ~print:(fun (a, b, c) -> Printf.sprintf "(%s, %s, %s)" a b c) gen_three_idents

(* Helper: parse single statement *)
let parse1 s = match Parse_errors.parse s with [e] -> e | _ -> failwith "expected 1 stmt"
let reduce1 s = Reducer.reduce (parse1 s)
let check1 s = Checker.check (reduce1 s)

(* === RULE-001: Operator precedence and associativity === *)

(* Property: >>> has lowest precedence — a >>> b *** c always produces Seq at top *)
let prop_001_seq_lowest_prec =
  QCheck.Test.make ~count:200
    ~name:"RULE-001: >>> has lowest precedence vs ***"
    arb_three_idents
    (fun (a, b, c) ->
       let input = Printf.sprintf "%s >>> %s *** %s" a b c in
       match (parse1 input).desc with
       | Ast.Seq (_, { desc = Ast.Par _; _ }) -> true
       | _ -> false)

(* Property: ||| has lower precedence than *** *)
let prop_001_alt_lower_than_par =
  QCheck.Test.make ~count:200
    ~name:"RULE-001: ||| has lower precedence than ***"
    arb_three_idents
    (fun (a, b, c) ->
       let input = Printf.sprintf "%s ||| %s *** %s" a b c in
       match (parse1 input).desc with
       | Ast.Alt (_, { desc = Ast.Par _; _ }) -> true
       | _ -> false)

(* Property: >>> is right-associative *)
let prop_001_seq_right_assoc =
  QCheck.Test.make ~count:200
    ~name:"RULE-001: >>> is right-associative"
    arb_three_idents
    (fun (a, b, c) ->
       let input = Printf.sprintf "%s >>> %s >>> %s" a b c in
       match (parse1 input).desc with
       | Ast.Seq (_, { desc = Ast.Seq _; _ }) -> true
       | _ -> false)

(* Property: deterministic — same input, same AST *)
let prop_001_deterministic =
  QCheck.Test.make ~count:200
    ~name:"RULE-001: parsing is deterministic"
    arb_three_idents
    (fun (a, b, c) ->
       let input = Printf.sprintf "%s >>> %s ||| %s" a b c in
       let s1 = Printer.to_string (parse1 input) in
       let s2 = Printer.to_string (parse1 input) in
       s1 = s2)

(* === RULE-002: Keyword disambiguation === *)

(* Generator: keyword prefix + non-empty suffix *)
let gen_keyword_prefixed_ident =
  let open QCheck.Gen in
  oneof (List.map return keywords) >>= fun kw ->
  gen_ident >>= fun suffix ->
  let suffix = if String.length suffix = 0 then "x" else suffix in
  return (kw ^ suffix)

let arb_keyword_prefixed =
  QCheck.make ~print:Fun.id gen_keyword_prefixed_ident

(* Property: keyword + suffix is always IDENT, never keyword token *)
let prop_002_no_false_keyword =
  QCheck.Test.make ~count:300
    ~name:"RULE-002: keyword prefix + suffix is IDENT"
    arb_keyword_prefixed
    (fun s ->
       let tokens = Lexer.tokenize s in
       match (List.hd tokens).token with
       | Lexer.IDENT name -> name = s
       | _ -> false)

(* Property: standalone keywords are correctly identified *)
let prop_002_standalone_keywords =
  QCheck.Test.make ~count:50
    ~name:"RULE-002: standalone keywords are keyword tokens"
    QCheck.(make (Gen.oneof_list ["let"; "in"; "loop"]))
    (fun kw ->
       let tokens = Lexer.tokenize kw in
       match kw, (List.hd tokens).token with
       | "let", Lexer.LET -> true
       | "in", Lexer.IN -> true
       | "loop", Lexer.LOOP -> true
       | _ -> false)

(* === RULE-003: Question/Alt pairing === *)

(* Property: <a>? >>> (<b> ||| <c>) always produces 0 warnings *)
let prop_003_question_with_alt_ok =
  QCheck.Test.make ~count:200
    ~name:"RULE-003: question with downstream alt produces 0 warnings"
    arb_three_idents
    (fun (a, b, c) ->
       let input = Printf.sprintf "%s? >>> (%s ||| %s)" a b c in
       let result = check1 input in
       List.length result.Checker.warnings = 0)

(* Property: <a>? >>> <b> >>> <c> (no |||) always produces 1 warning *)
let prop_003_question_without_alt_warns =
  QCheck.Test.make ~count:200
    ~name:"RULE-003: question without alt produces 1 warning"
    arb_three_idents
    (fun (a, b, c) ->
       let input = Printf.sprintf "%s? >>> %s >>> %s" a b c in
       let result = check1 input in
       List.length result.Checker.warnings = 1)

(* Property: upstream ||| does not satisfy the pairing *)
let prop_003_upstream_alt_no_match =
  QCheck.Test.make ~count:200
    ~name:"RULE-003: upstream ||| does not satisfy question"
    arb_three_idents
    (fun (a, b, c) ->
       let input = Printf.sprintf "(%s ||| %s) >>> %s? >>> done" a b c in
       let result = check1 input in
       List.length result.Checker.warnings = 1)

(* === RULE-004: Epistemic pairing === *)

(* Property: branch >>> <mid> >>> merge → 0 warnings *)
let prop_004_branch_merge_ok =
  QCheck.Test.make ~count:200
    ~name:"RULE-004: branch with merge produces 0 warnings"
    arb_ident
    (fun mid ->
       let input = Printf.sprintf "branch >>> %s >>> merge" mid in
       let result = check1 input in
       List.length result.Checker.warnings = 0)

(* Property: branch >>> <mid> (no merge) → 1 warning mentioning "branch" *)
let prop_004_branch_without_merge_warns =
  QCheck.Test.make ~count:200
    ~name:"RULE-004: branch without merge produces 1 warning"
    arb_ident
    (fun mid ->
       let input = Printf.sprintf "branch >>> %s" mid in
       let result = check1 input in
       List.length result.Checker.warnings = 1
       && List.exists (fun (w : Checker.warning) ->
            Helpers.contains w.message "branch") result.Checker.warnings)

(* Property: leaf >>> <mid> >>> check → 0 warnings *)
let prop_004_leaf_check_ok =
  QCheck.Test.make ~count:200
    ~name:"RULE-004: leaf with check produces 0 warnings"
    arb_ident
    (fun mid ->
       let input = Printf.sprintf "leaf >>> %s >>> check" mid in
       let result = check1 input in
       List.length result.Checker.warnings = 0)

(* Property: leaf >>> <mid> (no check) → 1 warning mentioning "leaf" *)
let prop_004_leaf_without_check_warns =
  QCheck.Test.make ~count:200
    ~name:"RULE-004: leaf without check produces 1 warning"
    arb_ident
    (fun mid ->
       let input = Printf.sprintf "leaf >>> %s" mid in
       let result = check1 input in
       List.length result.Checker.warnings = 1
       && List.exists (fun (w : Checker.warning) ->
            Helpers.contains w.message "leaf") result.Checker.warnings)

(* Property: merge alone (no branch) → 0 warnings — asymmetric *)
let prop_004_merge_alone_ok =
  QCheck.Test.make ~count:200
    ~name:"RULE-004: merge without branch produces 0 warnings (asymmetric)"
    arb_ident
    (fun mid ->
       let input = Printf.sprintf "merge >>> %s" mid in
       let result = check1 input in
       List.length result.Checker.warnings = 0)

(* Property: check alone (no leaf) → 0 warnings — asymmetric *)
let prop_004_check_alone_ok =
  QCheck.Test.make ~count:200
    ~name:"RULE-004: check without leaf produces 0 warnings (asymmetric)"
    arb_ident
    (fun mid ->
       let input = Printf.sprintf "check >>> %s" mid in
       let result = check1 input in
       List.length result.Checker.warnings = 0)

(* === RULE-005: Reducer beta-reduction === *)

(* Property: let f = <a> >>> <b> in f → Seq(Var(a), Var(b)) *)
let prop_005_let_simple_subst =
  QCheck.Test.make ~count:200
    ~name:"RULE-005: let f = a >>> b in f reduces to Seq(a, b)"
    arb_three_idents
    (fun (a, b, _) ->
       let input = Printf.sprintf "let f = %s >>> %s in f" a b in
       let reduced = reduce1 input in
       let expected = Printf.sprintf {|Seq(Var("%s"), Var("%s"))|} a b in
       Printer.to_string reduced = expected)

(* Property: identity lambda — let id = \x -> x in id(<a>) → Var(<a>) *)
let prop_005_identity_lambda =
  QCheck.Test.make ~count:200
    ~name:"RULE-005: identity lambda (\\x -> x) applied returns argument"
    arb_ident
    (fun a ->
       let input = Printf.sprintf {|let id = \x -> x in id(%s)|} a in
       let reduced = reduce1 input in
       let expected = Printf.sprintf {|Var("%s")|} a in
       Printer.to_string reduced = expected)

(* Property: reduction is deterministic *)
let prop_005_deterministic =
  QCheck.Test.make ~count:200
    ~name:"RULE-005: reduction is deterministic"
    arb_three_idents
    (fun (a, b, _) ->
       let input = Printf.sprintf "let f = %s >>> %s in f" a b in
       let r1 = Printer.to_string (reduce1 input) in
       let r2 = Printer.to_string (reduce1 input) in
       r1 = r2)

(* Property: reduction is idempotent — reducing already-reduced expr gives same *)
let prop_005_idempotent =
  QCheck.Test.make ~count:200
    ~name:"RULE-005: reduction is idempotent"
    arb_three_idents
    (fun (a, b, _) ->
       let input = Printf.sprintf "%s >>> %s" a b in
       let r1 = reduce1 input in
       let r2 = Reducer.reduce r1 in
       Printer.to_string r1 = Printer.to_string r2)

(* Property: free variables survive reduction *)
let prop_005_free_var_survives =
  QCheck.Test.make ~count:200
    ~name:"RULE-005: free variables survive reduction as Var"
    arb_ident
    (fun a ->
       let input = a in
       let reduced = reduce1 input in
       match reduced.desc with
       | Ast.Var name -> name = a
       | _ -> false)

(* === RULE-006: Literate fence extraction === *)

(* Generator: safe arrow block content (simple ident seq) *)
let gen_arrow_content =
  let open QCheck.Gen in
  gen_safe_ident >>= fun a ->
  gen_safe_ident >>= fun b ->
  return (Printf.sprintf "%s >>> %s" a b)

let arb_arrow_content =
  QCheck.make ~print:Fun.id gen_arrow_content

(* Property: ```arrow fence always extracts 1 block *)
let prop_006_arrow_fence_extracts =
  QCheck.Test.make ~count:200
    ~name:"RULE-006: ```arrow fence extracts exactly 1 block"
    arb_arrow_content
    (fun content ->
       let md = Printf.sprintf "# Doc\n\n```arrow\n%s\n```\n" content in
       let blocks = Markdown.extract md in
       List.length blocks = 1)

(* Property: ```arr fence also extracts 1 block *)
let prop_006_arr_fence_extracts =
  QCheck.Test.make ~count:200
    ~name:"RULE-006: ```arr fence extracts exactly 1 block"
    arb_arrow_content
    (fun content ->
       let md = Printf.sprintf "# Doc\n\n```arr\n%s\n```\n" content in
       let blocks = Markdown.extract md in
       List.length blocks = 1)

(* Property: ~~~arrow (tilde) fence extracts 0 blocks *)
let prop_006_tilde_fence_rejected =
  QCheck.Test.make ~count:200
    ~name:"RULE-006: ~~~arrow tilde fence extracts 0 blocks"
    arb_arrow_content
    (fun content ->
       let md = Printf.sprintf "~~~arrow\n%s\n~~~\n" content in
       let blocks = Markdown.extract md in
       List.length blocks = 0)

(* Property: extracted content matches original *)
let prop_006_content_preserved =
  QCheck.Test.make ~count:200
    ~name:"RULE-006: extracted content matches original"
    arb_arrow_content
    (fun content ->
       let md = Printf.sprintf "```arrow\n%s\n```\n" content in
       let blocks = Markdown.extract md in
       match blocks with
       | [b] -> b.Markdown.content = content ^ "\n"
       | _ -> false)

(* Generator: non-arrow language tag *)
let gen_other_lang =
  QCheck.Gen.oneof_list ["python"; "javascript"; "ocaml"; "rust"; "go"; "arrows"; "arrow-diagram"]

let arb_other_lang =
  QCheck.make ~print:Fun.id gen_other_lang

(* Property: non-arrow fence extracts 0 blocks *)
let prop_006_non_arrow_rejected =
  QCheck.Test.make ~count:100
    ~name:"RULE-006: non-arrow/arr fences extract 0 blocks"
    QCheck.(pair arb_other_lang arb_arrow_content)
    (fun (lang, content) ->
       let md = Printf.sprintf "```%s\n%s\n```\n" lang content in
       let blocks = Markdown.extract md in
       List.length blocks = 0)

(* === Test registration === *)

let tests =
  List.map QCheck_alcotest.to_alcotest
    [ (* RULE-001: Operator precedence *)
      prop_001_seq_lowest_prec
    ; prop_001_alt_lower_than_par
    ; prop_001_seq_right_assoc
    ; prop_001_deterministic
      (* RULE-002: Keyword disambiguation *)
    ; prop_002_no_false_keyword
    ; prop_002_standalone_keywords
      (* RULE-003: Question/Alt pairing *)
    ; prop_003_question_with_alt_ok
    ; prop_003_question_without_alt_warns
    ; prop_003_upstream_alt_no_match
      (* RULE-004: Epistemic pairing *)
    ; prop_004_branch_merge_ok
    ; prop_004_branch_without_merge_warns
    ; prop_004_leaf_check_ok
    ; prop_004_leaf_without_check_warns
    ; prop_004_merge_alone_ok
    ; prop_004_check_alone_ok
      (* RULE-005: Reducer beta-reduction *)
    ; prop_005_let_simple_subst
    ; prop_005_identity_lambda
    ; prop_005_deterministic
    ; prop_005_idempotent
    ; prop_005_free_var_survives
      (* RULE-006: Literate fence extraction *)
    ; prop_006_arrow_fence_extracts
    ; prop_006_arr_fence_extracts
    ; prop_006_tilde_fence_rejected
    ; prop_006_content_preserved
    ; prop_006_non_arrow_rejected
    ]
