open Compose_dsl

(* === Property-based tests (QCheck) === *)

(* Generator: non-empty lowercase ASCII identifier *)
let gen_ident =
  let open QCheck.Gen in
  let alpha = oneof (List.init 26 (fun i -> return (Char.chr (Char.code 'a' + i)))) in
  string_size ~gen:alpha (1 -- 12)

let arb_ident =
  QCheck.make ~print:Fun.id gen_ident

(* Smoke test: any single identifier roundtrips through parse >>> print *)
let prop_ident_roundtrip =
  QCheck.Test.make ~count:200
    ~name:"ident roundtrip through parse >>> print"
    arb_ident
    (fun s ->
       let ast = Parse_errors.parse s in
       match ast with
       | [{ desc = Ast.Var name; _ }] -> name = s
       | _ -> false)

let tests =
  List.map QCheck_alcotest.to_alcotest
    [ prop_ident_roundtrip
    ]
