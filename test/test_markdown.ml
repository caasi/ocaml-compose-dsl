open Compose_dsl

let test_md_extract_single_block () =
  let input = "# Title\n\n```arrow\na >>> b\n```\n\nSome text\n" in
  let blocks = Markdown.extract input in
  Alcotest.(check int) "one block" 1 (List.length blocks);
  let b = List.hd blocks in
  Alcotest.(check string) "content" "a >>> b\n" b.Markdown.content;
  Alcotest.(check int) "markdown_start" 4 b.Markdown.markdown_start

let test_md_extract_multiple_blocks () =
  let input = "# Title\n\n```arrow\na >>> b\n```\n\nText\n\n```arr\nc >>> d\n```\n" in
  let blocks = Markdown.extract input in
  Alcotest.(check int) "two blocks" 2 (List.length blocks);
  let b1 = List.nth blocks 0 in
  let b2 = List.nth blocks 1 in
  Alcotest.(check string) "block1 content" "a >>> b\n" b1.Markdown.content;
  Alcotest.(check int) "block1 start" 4 b1.Markdown.markdown_start;
  Alcotest.(check string) "block2 content" "c >>> d\n" b2.Markdown.content;
  Alcotest.(check int) "block2 start" 10 b2.Markdown.markdown_start

let test_md_extract_no_blocks () =
  let input = "# Title\n\nJust text\n\n```python\nprint('hi')\n```\n" in
  let blocks = Markdown.extract input in
  Alcotest.(check int) "no blocks" 0 (List.length blocks)

let test_md_extract_tilde_ignored () =
  let input = "~~~arrow\na >>> b\n~~~\n" in
  let blocks = Markdown.extract input in
  Alcotest.(check int) "no blocks" 0 (List.length blocks)

let test_md_extract_indented_fence () =
  let input = "   ```arrow\na >>> b\n   ```\n" in
  let blocks = Markdown.extract input in
  Alcotest.(check int) "one block" 1 (List.length blocks);
  Alcotest.(check string) "content" "a >>> b\n" (List.hd blocks).Markdown.content

let test_md_extract_4space_not_fence () =
  let input = "    ```arrow\na >>> b\n    ```\n" in
  let blocks = Markdown.extract input in
  Alcotest.(check int) "no blocks" 0 (List.length blocks)

let test_md_extract_prefix_rejected () =
  let input = "```arrows\na >>> b\n```\n```arrow-diagram\nc >>> d\n```\n" in
  let blocks = Markdown.extract input in
  Alcotest.(check int) "no blocks" 0 (List.length blocks)

let test_md_extract_4backtick_ignored () =
  let input = "````arrow\na >>> b\n````\n" in
  let blocks = Markdown.extract input in
  Alcotest.(check int) "no blocks" 0 (List.length blocks)

let test_md_extract_trailing_whitespace () =
  let input = "```arrow  \na >>> b\n```\n" in
  let blocks = Markdown.extract input in
  Alcotest.(check int) "one block" 1 (List.length blocks)

let test_md_extract_extra_text_rejected () =
  let input = "```arrow some-label\na >>> b\n```\n" in
  let blocks = Markdown.extract input in
  Alcotest.(check int) "no blocks" 0 (List.length blocks)

let test_md_extract_arr_info_string () =
  let input = "```arr\na >>> b\n```\n" in
  let blocks = Markdown.extract input in
  Alcotest.(check int) "one block" 1 (List.length blocks);
  Alcotest.(check string) "content" "a >>> b\n" (List.hd blocks).Markdown.content

let test_md_extract_unclosed_block () =
  let input = "```arrow\na >>> b\n" in
  let blocks = Markdown.extract input in
  Alcotest.(check int) "one block" 1 (List.length blocks);
  Alcotest.(check string) "content" "a >>> b\n" (List.hd blocks).Markdown.content

let test_md_extract_crlf () =
  let input = "```arrow\r\na >>> b\r\n```\r\n" in
  let blocks = Markdown.extract input in
  Alcotest.(check int) "one block" 1 (List.length blocks);
  Alcotest.(check string) "content" "a >>> b\n" (List.hd blocks).Markdown.content;
  Alcotest.(check int) "markdown_start" 2 (List.hd blocks).Markdown.markdown_start

let test_md_combine_single () =
  let blocks = [{ Markdown.content = "a >>> b\n"; markdown_start = 10 }] in
  let source, table = Markdown.combine blocks in
  Alcotest.(check string) "source" "a >>> b\n" source;
  Alcotest.(check int) "table length" 1 (List.length table);
  let (cs, ms) = List.hd table in
  Alcotest.(check int) "combined_start" 1 cs;
  Alcotest.(check int) "markdown_start" 10 ms

let test_md_combine_multiple () =
  let blocks =
    [ { Markdown.content = "a >>> b\n"; markdown_start = 10 }
    ; { Markdown.content = "c >>> d\ne >>> f\n"; markdown_start = 30 }
    ] in
  let source, table = Markdown.combine blocks in
  Alcotest.(check string) "source" "a >>> b\n\nc >>> d\ne >>> f\n" source;
  Alcotest.(check int) "table length" 2 (List.length table);
  let (cs1, ms1) = List.nth table 0 in
  let (cs2, ms2) = List.nth table 1 in
  Alcotest.(check int) "block1 combined_start" 1 cs1;
  Alcotest.(check int) "block1 markdown_start" 10 ms1;
  Alcotest.(check int) "block2 combined_start" 3 cs2;
  Alcotest.(check int) "block2 markdown_start" 30 ms2

let test_md_combine_empty () =
  let source, table = Markdown.combine [] in
  Alcotest.(check string) "source" "" source;
  Alcotest.(check int) "table length" 0 (List.length table)

let test_md_translate_single () =
  let table = [(1, 10)] in
  Alcotest.(check int) "line 1" 10 (Markdown.translate_line table 1);
  Alcotest.(check int) "line 3" 12 (Markdown.translate_line table 3)

let test_md_translate_multiple () =
  let table = [(1, 10); (3, 30)] in
  Alcotest.(check int) "line 1" 10 (Markdown.translate_line table 1);
  Alcotest.(check int) "line 2" 11 (Markdown.translate_line table 2);
  Alcotest.(check int) "line 3" 30 (Markdown.translate_line table 3);
  Alcotest.(check int) "line 5" 32 (Markdown.translate_line table 5)

let test_md_translate_empty () =
  Alcotest.(check int) "passthrough" 42 (Markdown.translate_line [] 42)

let tests =
  [ "single block", `Quick, test_md_extract_single_block
  ; "multiple blocks", `Quick, test_md_extract_multiple_blocks
  ; "no blocks", `Quick, test_md_extract_no_blocks
  ; "tilde ignored", `Quick, test_md_extract_tilde_ignored
  ; "indented fence", `Quick, test_md_extract_indented_fence
  ; "4-space not fence", `Quick, test_md_extract_4space_not_fence
  ; "prefix rejected", `Quick, test_md_extract_prefix_rejected
  ; "4+ backtick ignored", `Quick, test_md_extract_4backtick_ignored
  ; "trailing whitespace", `Quick, test_md_extract_trailing_whitespace
  ; "extra text rejected", `Quick, test_md_extract_extra_text_rejected
  ; "arr info string", `Quick, test_md_extract_arr_info_string
  ; "unclosed block", `Quick, test_md_extract_unclosed_block
  ; "crlf line endings", `Quick, test_md_extract_crlf
  ; "combine single", `Quick, test_md_combine_single
  ; "combine multiple", `Quick, test_md_combine_multiple
  ; "combine empty", `Quick, test_md_combine_empty
  ; "translate single", `Quick, test_md_translate_single
  ; "translate multiple", `Quick, test_md_translate_multiple
  ; "translate empty", `Quick, test_md_translate_empty
  ]

let test_md_literate_end_to_end () =
  let input = "# Doc\n\n```arrow\nlet f = a >>> b in f\n```\n\nText\n" in
  let blocks = Markdown.extract input in
  let source, _table = Markdown.combine blocks in
  let ast = Helpers.parse_ok source in
  let _ast = Reducer.reduce ast in
  ()

let test_md_literate_error_line_translation () =
  let input = "# Doc\n\n```arrow\n!!!\n```\n" in
  let blocks = Markdown.extract input in
  let source, table = Markdown.combine blocks in
  match Lexer.tokenize source with
  | exception Lexer.Lex_error (pos, _msg) ->
    let translated = Markdown.translate_line table pos.line in
    Alcotest.(check int) "error at markdown line 4" 4 translated
  | _ -> Alcotest.fail "expected lex error"

let integration_tests =
  [ "literate end-to-end", `Quick, test_md_literate_end_to_end
  ; "error line translation", `Quick, test_md_literate_error_line_translation
  ]
