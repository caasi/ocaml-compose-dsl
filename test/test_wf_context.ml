open Compose_dsl

let test_leading_comment_to_header () =
  let comments = Wf_context.comments_of_source "-- hello world\na >>> b" in
  Alcotest.(check bool) "captured" true (List.exists (fun (_,t) -> Helpers.contains t "hello") comments)

let test_description_from_first_comment () =
  Alcotest.(check string) "desc" "hello world"
    (Wf_context.derive_description ["-- hello world"] ~fallback:"x")

(* CRLF Markdown: fence line has a trailing \r which must be stripped before
   is_opening_fence is called, otherwise the fence is wrongly collected into prose. *)
let test_markdown_prose_crlf () =
  (* "intro line\r\n\r\n```arrow\r\na >>> b\r\n```\r\n" *)
  let input = "intro line\r\n\r\n```arrow\r\na >>> b\r\n```\r\n" in
  let prose = Wf_context.markdown_prose input in
  Alcotest.(check (list string)) "prose excludes fence line"
    ["intro line"] prose

let tests =
  [ Alcotest.test_case "leading comment to header" `Quick test_leading_comment_to_header
  ; Alcotest.test_case "description from first comment" `Quick test_description_from_first_comment
  ; Alcotest.test_case "markdown_prose strips CRLF before fence check" `Quick test_markdown_prose_crlf ]
