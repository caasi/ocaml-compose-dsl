open Compose_dsl

let test_leading_comment_to_header () =
  let comments = Wf_context.comments_of_source "-- hello world\na >>> b" in
  Alcotest.(check bool) "captured" true (List.exists (fun (_,t) -> Helpers.contains t "hello") comments)

let test_description_from_first_comment () =
  Alcotest.(check string) "desc" "hello world"
    (Wf_context.derive_description ["-- hello world"] ~fallback:"x")

let tests =
  [ Alcotest.test_case "leading comment to header" `Quick test_leading_comment_to_header
  ; Alcotest.test_case "description from first comment" `Quick test_description_from_first_comment ]
