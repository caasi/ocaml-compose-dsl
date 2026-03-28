open Compose_dsl

(* === Lexer tests === *)

(* ident = ( letter | "_" ) , { letter | digit | "-" | "_" } *)
let test_lex_ident_with_digits () =
  let tokens = Lexer.tokenize "step2" in
  match (List.hd tokens).token with
  | Lexer.IDENT "step2" -> ()
  | _ -> Alcotest.fail "expected IDENT step2"

let test_lex_ident_with_hyphen () =
  let tokens = Lexer.tokenize "my-node" in
  match (List.hd tokens).token with
  | Lexer.IDENT "my-node" -> ()
  | _ -> Alcotest.fail "expected IDENT my-node"

let test_lex_ident_with_underscore () =
  let tokens = Lexer.tokenize "_private" in
  match (List.hd tokens).token with
  | Lexer.IDENT "_private" -> ()
  | _ -> Alcotest.fail "expected IDENT _private"

(* operator = ">>>" | "***" | "|||" *)
let test_lex_all_operators () =
  let tokens = Lexer.tokenize "a >>> b *** c ||| d" in
  let toks = List.map (fun (t : Lexer.located) -> t.token) tokens in
  Alcotest.(check int) "token count" 8 (List.length toks);
  Alcotest.(check bool) "has SEQ" true (List.nth toks 1 = Lexer.SEQ);
  Alcotest.(check bool) "has PAR" true (List.nth toks 3 = Lexer.PAR);
  Alcotest.(check bool) "has ALT" true (List.nth toks 5 = Lexer.ALT)

(* string = '"' , { any char - '"' } , '"' *)
let test_lex_string () =
  let tokens = Lexer.tokenize "a(x: \"hello world\")" in
  let has_string =
    List.exists
      (fun (t : Lexer.located) ->
        match t.token with Lexer.STRING "hello world" -> true | _ -> false)
      tokens
  in
  Alcotest.(check bool) "has string" true has_string

let test_lex_unterminated_string () =
  match Lexer.tokenize "a(\"hello)" with
  | _ -> Alcotest.fail "expected lex error"
  | exception Lexer.Lex_error (_, msg) ->
    Alcotest.(check string) "error msg" "unterminated string" msg

(* comment = "--" , { any char - newline } *)
let test_lex_comment () =
  let tokens = Lexer.tokenize "a -- hello world" in
  let comment =
    List.find_map
      (fun (t : Lexer.located) ->
        match t.token with Lexer.COMMENT s -> Some s | _ -> None)
      tokens
  in
  Alcotest.(check (option string)) "comment text" (Some "hello world") comment

(* loop keyword vs ident *)
let test_lex_loop_keyword () =
  let tokens = Lexer.tokenize "loop" in
  match (List.hd tokens).token with
  | Lexer.LOOP -> ()
  | _ -> Alcotest.fail "expected LOOP token"

let test_lex_unexpected_char () =
  match Lexer.tokenize "@" with
  | _ -> Alcotest.fail "expected lex error"
  | exception Lexer.Lex_error (_, msg) ->
    Alcotest.(check string) "error msg" "unexpected character '@'" msg

let test_lex_fanout_operator () =
  let tokens = Lexer.tokenize "a &&& b" in
  let toks = List.map (fun (t : Lexer.located) -> t.token) tokens in
  Alcotest.(check int) "token count" 4 (List.length toks);
  Alcotest.(check bool) "has FANOUT" true (List.nth toks 1 = Lexer.FANOUT)

let test_lex_partial_ampersand () =
  match Lexer.tokenize "a & b" with
  | _ -> Alcotest.fail "expected lex error"
  | exception Lexer.Lex_error (_, msg) ->
    Alcotest.(check string) "error msg" "unexpected character '&'" msg

let test_lex_double_ampersand () =
  match Lexer.tokenize "a && b" with
  | _ -> Alcotest.fail "expected lex error"
  | exception Lexer.Lex_error (_, msg) ->
    Alcotest.(check string) "error msg" "unexpected character '&'" msg

let test_lex_integer () =
  let tokens = Lexer.tokenize "42" in
  match (List.hd tokens).token with
  | Lexer.NUMBER "42" -> ()
  | _ -> Alcotest.fail "expected NUMBER 42"

let test_lex_float () =
  let tokens = Lexer.tokenize "3.14" in
  match (List.hd tokens).token with
  | Lexer.NUMBER "3.14" -> ()
  | _ -> Alcotest.fail "expected NUMBER 3.14"

let test_lex_negative_integer () =
  let tokens = Lexer.tokenize "a(x: -5)" in
  let has_neg =
    List.exists
      (fun (t : Lexer.located) ->
        match t.token with Lexer.NUMBER "-5" -> true | _ -> false)
      tokens
  in
  Alcotest.(check bool) "has NUMBER -5" true has_neg

let test_lex_negative_float () =
  let tokens = Lexer.tokenize "a(x: -0.5)" in
  let has_neg =
    List.exists
      (fun (t : Lexer.located) ->
        match t.token with Lexer.NUMBER "-0.5" -> true | _ -> false)
      tokens
  in
  Alcotest.(check bool) "has NUMBER -0.5" true has_neg

let test_lex_negative_is_not_comment () =
  let tokens = Lexer.tokenize "a(x: -3)" in
  let has_comment =
    List.exists
      (fun (t : Lexer.located) ->
        match t.token with Lexer.COMMENT _ -> true | _ -> false)
      tokens
  in
  Alcotest.(check bool) "no comment" false has_comment

let test_lex_trailing_dot () =
  match Lexer.tokenize "a(x: 3.)" with
  | _ -> Alcotest.fail "expected lex error"
  | exception Lexer.Lex_error (_, msg) ->
    Alcotest.(check string) "error msg" "expected digit after '.'" msg

let test_lex_leading_dot () =
  match Lexer.tokenize "a(x: .5)" with
  | _ -> Alcotest.fail "expected lex error"
  | exception Lexer.Lex_error (_, msg) ->
    Alcotest.(check string) "error msg" "unexpected character '.'" msg

let test_lex_unit_suffix () =
  let tokens = Lexer.tokenize "100mg" in
  match (List.hd tokens).token with
  | Lexer.NUMBER "100mg" -> ()
  | _ -> Alcotest.fail "expected NUMBER 100mg"

let test_lex_float_unit_suffix () =
  let tokens = Lexer.tokenize "2.5cm" in
  match (List.hd tokens).token with
  | Lexer.NUMBER "2.5cm" -> ()
  | _ -> Alcotest.fail "expected NUMBER 2.5cm"

let test_lex_negative_unit_suffix () =
  let tokens = Lexer.tokenize "a(x: -10dB)" in
  let has_neg =
    List.exists
      (fun (t : Lexer.located) ->
        match t.token with Lexer.NUMBER "-10dB" -> true | _ -> false)
      tokens
  in
  Alcotest.(check bool) "has NUMBER -10dB" true has_neg

let test_lex_number_before_delimiter () =
  let tokens = Lexer.tokenize "a(x: 42)" in
  let toks = List.map (fun (t : Lexer.located) -> t.token) tokens in
  Alcotest.(check bool) "NUMBER then RPAREN"
    true
    (List.nth toks 4 = Lexer.NUMBER "42"
     && List.nth toks 5 = Lexer.RPAREN)

let test_lex_reserved_hash () =
  match Lexer.tokenize "#invalid" with
  | _ -> Alcotest.fail "expected lex error"
  | exception Lexer.Lex_error (_, msg) ->
    Alcotest.(check string) "error msg" "unexpected character '#'" msg

let test_lex_unicode_unit_suffix () =
  let tokens = Lexer.tokenize "500ミリ秒" in
  match (List.hd tokens).token with
  | Lexer.NUMBER "500ミリ秒" -> ()
  | _ -> Alcotest.fail "expected NUMBER 500ミリ秒"

let test_lex_unit_suffix_with_digit () =
  let tokens = Lexer.tokenize "100m2" in
  match (List.hd tokens).token with
  | Lexer.NUMBER "100m2" -> ()
  | _ -> Alcotest.fail "expected NUMBER 100m2"

let test_lex_unicode_cjk_ident () =
  let tokens = Lexer.tokenize "翻譯" in
  match (List.hd tokens).token with
  | Lexer.IDENT "翻譯" -> ()
  | _ -> Alcotest.fail "expected IDENT 翻譯"

let test_lex_unicode_greek_ident () =
  let tokens = Lexer.tokenize "α" in
  match (List.hd tokens).token with
  | Lexer.IDENT "α" -> ()
  | _ -> Alcotest.fail "expected IDENT α"

let test_lex_unicode_accented_ident () =
  let tokens = Lexer.tokenize "café" in
  match (List.hd tokens).token with
  | Lexer.IDENT "café" -> ()
  | _ -> Alcotest.fail "expected IDENT café"

let test_lex_unicode_mixed_ident () =
  let tokens = Lexer.tokenize "a_名前-test" in
  match (List.hd tokens).token with
  | Lexer.IDENT "a_名前-test" -> ()
  | _ -> Alcotest.fail "expected IDENT a_名前-test"

let test_lex_unicode_ident_col () =
  let tokens = Lexer.tokenize "翻譯 >>> b" in
  match tokens with
  | tok0 :: tok1 :: tok2 :: _ ->
    (match tok0.token with
     | Lexer.IDENT "翻譯" -> ()
     | _ -> Alcotest.fail "expected IDENT 翻譯");
    (match tok1.token with
     | Lexer.SEQ -> ()
     | _ -> Alcotest.fail "expected SEQ");
    (match tok2.token with
     | Lexer.IDENT "b" -> ()
     | _ -> Alcotest.fail "expected IDENT b");
    Alcotest.(check int) "翻譯 col" 1 tok0.loc.start.col;
    Alcotest.(check int) ">>> col" 4 tok1.loc.start.col;
    Alcotest.(check int) "b col" 8 tok2.loc.start.col
  | _ -> Alcotest.fail "expected at least 3 tokens"

let test_lex_mixed_unicode_col () =
  let tokens = Lexer.tokenize "a翻譯b >>> c" in
  match tokens with
  | tok0 :: tok1 :: _ ->
    (match tok0.token with
     | Lexer.IDENT s -> Alcotest.(check string) "ident" "a翻譯b" s
     | _ -> Alcotest.fail "expected IDENT a翻譯b");
    (match tok1.token with
     | Lexer.SEQ -> ()
     | _ -> Alcotest.fail "expected SEQ");
    Alcotest.(check int) "ident col" 1 tok0.loc.start.col;
    Alcotest.(check int) ">>> col" 6 tok1.loc.start.col
  | _ -> Alcotest.fail "expected at least 2 tokens"

let test_lex_unicode_string_col () =
  let tokens = Lexer.tokenize {|"翻譯" >>> b|} in
  match tokens with
  | tok0 :: tok1 :: tok2 :: _ ->
    (match tok0.token with
     | Lexer.STRING "翻譯" -> ()
     | _ -> Alcotest.fail "expected STRING 翻譯");
    (match tok1.token with
     | Lexer.SEQ -> ()
     | _ -> Alcotest.fail "expected SEQ");
    (match tok2.token with
     | Lexer.IDENT "b" -> ()
     | _ -> Alcotest.fail "expected IDENT b");
    Alcotest.(check int) "string col" 1 tok0.loc.start.col;
    Alcotest.(check int) ">>> col" 6 tok1.loc.start.col;
    Alcotest.(check int) "b col" 10 tok2.loc.start.col
  | _ -> Alcotest.fail "expected at least 3 tokens"

let test_lex_multiline_unicode_col () =
  let tokens = Lexer.tokenize "翻譯\nb" in
  match tokens with
  | tok0 :: tok1 :: _ ->
    Alcotest.(check int) "翻譯 line" 1 tok0.loc.start.line;
    Alcotest.(check int) "翻譯 col" 1 tok0.loc.start.col;
    Alcotest.(check int) "b line" 2 tok1.loc.start.line;
    Alcotest.(check int) "b col" 1 tok1.loc.start.col
  | _ -> Alcotest.fail "expected at least 2 tokens"

let test_lex_malformed_utf8 () =
  match Lexer.tokenize "\xff\xfe" with
  | _ -> Alcotest.fail "expected Lex_error"
  | exception Lexer.Lex_error (_, msg) ->
    Alcotest.(check string) "error msg" "invalid UTF-8 byte sequence" msg

let test_lex_error_col_after_unicode () =
  match Lexer.tokenize "翻譯 @" with
  | _ -> Alcotest.fail "expected Lex_error"
  | exception Lexer.Lex_error (pos, _) ->
    Alcotest.(check int) "error col" 4 pos.col

(* question operator *)
let test_lex_question () =
  let tokens = Lexer.tokenize "a?" in
  let toks = List.map (fun (t : Lexer.located) -> t.token) tokens in
  Alcotest.(check int) "token count" 3 (List.length toks);
  Alcotest.(check bool) "IDENT" true (List.nth toks 0 = Lexer.IDENT "a");
  Alcotest.(check bool) "QUESTION" true (List.nth toks 1 = Lexer.QUESTION);
  Alcotest.(check bool) "EOF" true (List.nth toks 2 = Lexer.EOF)

let test_lex_question_with_space () =
  let tokens = Lexer.tokenize "a ?" in
  let toks = List.map (fun (t : Lexer.located) -> t.token) tokens in
  Alcotest.(check int) "token count" 3 (List.length toks);
  Alcotest.(check bool) "QUESTION" true (List.nth toks 1 = Lexer.QUESTION)

let test_lex_question_after_string () =
  let tokens = Lexer.tokenize {|"hello"?|} in
  let toks = List.map (fun (t : Lexer.located) -> t.token) tokens in
  Alcotest.(check int) "token count" 3 (List.length toks);
  Alcotest.(check bool) "STRING" true (List.nth toks 0 = Lexer.STRING "hello");
  Alcotest.(check bool) "QUESTION" true (List.nth toks 1 = Lexer.QUESTION)

(* === Lexer loc span tests === *)

let test_lex_ident_loc_span () =
  let tokens = Lexer.tokenize "abc" in
  let t = List.hd tokens in
  Alcotest.(check int) "start col" 1 t.loc.start.col;
  Alcotest.(check int) "end col" 4 t.loc.end_.col

let test_lex_operator_loc_span () =
  let tokens = Lexer.tokenize "a >>> b" in
  let seq_tok = List.nth tokens 1 in
  Alcotest.(check int) ">>> start col" 3 seq_tok.loc.start.col;
  Alcotest.(check int) ">>> end col" 6 seq_tok.loc.end_.col

let test_lex_string_loc_span () =
  let tokens = Lexer.tokenize {|"hello"|} in
  let t = List.hd tokens in
  Alcotest.(check int) "start col" 1 t.loc.start.col;
  Alcotest.(check int) "end col" 8 t.loc.end_.col

let test_lex_question_loc_span () =
  let tokens = Lexer.tokenize "a?" in
  let q_tok = List.nth tokens 1 in
  Alcotest.(check int) "? start col" 2 q_tok.loc.start.col;
  Alcotest.(check int) "? end col" 3 q_tok.loc.end_.col

let test_lex_eof_loc_span () =
  let tokens = Lexer.tokenize "a" in
  let eof_tok = List.nth tokens 1 in
  (match eof_tok.token with
   | Lexer.EOF ->
     Alcotest.(check int) "eof start = end" eof_tok.loc.start.col eof_tok.loc.end_.col
   | _ -> Alcotest.fail "expected EOF")

let test_lex_unicode_ident_loc_span () =
  let tokens = Lexer.tokenize "翻譯" in
  let t = List.hd tokens in
  Alcotest.(check int) "start col" 1 t.loc.start.col;
  Alcotest.(check int) "end col (codepoints)" 3 t.loc.end_.col

let test_lex_double_colon () =
  let tokens = Lexer.tokenize "a :: B" in
  match tokens with
  | [ { token = IDENT "a"; _ }; { token = DOUBLE_COLON; _ }; { token = IDENT "B"; _ }; { token = EOF; _ } ] -> ()
  | _ -> Alcotest.fail "expected IDENT DOUBLE_COLON IDENT"

let test_lex_arrow () =
  let tokens = Lexer.tokenize "A -> B" in
  match tokens with
  | [ { token = IDENT "A"; _ }; { token = ARROW; _ }; { token = IDENT "B"; _ }; { token = EOF; _ } ] -> ()
  | _ -> Alcotest.fail "expected IDENT ARROW IDENT"

let test_lex_type_annotation () =
  let tokens = Lexer.tokenize "node :: Input -> Output" in
  match tokens with
  | [ { token = IDENT "node"; _ }; { token = DOUBLE_COLON; _ }; { token = IDENT "Input"; _ }; { token = ARROW; _ }; { token = IDENT "Output"; _ }; { token = EOF; _ } ] -> ()
  | _ -> Alcotest.fail "expected full type annotation token sequence"

let test_lex_colon_still_works () =
  let tokens = Lexer.tokenize "key: value" in
  match tokens with
  | [ { token = IDENT "key"; _ }; { token = COLON; _ }; { token = IDENT "value"; _ }; { token = EOF; _ } ] -> ()
  | _ -> Alcotest.fail "single colon should still produce COLON"

let test_lex_arrow_not_negative () =
  let tokens = Lexer.tokenize "-3 -> B" in
  match tokens with
  | [ { token = NUMBER "-3"; _ }; { token = ARROW; _ }; { token = IDENT "B"; _ }; { token = EOF; _ } ] -> ()
  | _ -> Alcotest.fail "-> after number should be ARROW"

let test_lex_arrow_no_whitespace () =
  let tokens = Lexer.tokenize "A->B" in
  match tokens with
  | [ { token = IDENT "A"; _ }; { token = ARROW; _ }; { token = IDENT "B"; _ }; { token = EOF; _ } ] -> ()
  | _ -> Alcotest.fail "-> without whitespace should tokenize correctly"

let test_lex_arrow_no_whitespace_in_type_ann () =
  let tokens = Lexer.tokenize "node::A->B" in
  match tokens with
  | [ { token = IDENT "node"; _ }; { token = DOUBLE_COLON; _ }; { token = IDENT "A"; _ }; { token = ARROW; _ }; { token = IDENT "B"; _ }; { token = EOF; _ } ] -> ()
  | _ -> Alcotest.fail "type annotation without whitespace should tokenize correctly"

let test_lex_ident_with_hyphen_before_arrow () =
  let tokens = Lexer.tokenize "my-node->B" in
  match tokens with
  | [ { token = IDENT "my-node"; _ }; { token = ARROW; _ }; { token = IDENT "B"; _ }; { token = EOF; _ } ] -> ()
  | _ -> Alcotest.fail "hyphenated ident before -> should not consume the arrow"

let test_lex_backslash () =
  let tokens = Lexer.tokenize "\\ x" in
  match (List.hd tokens).token with
  | Lexer.BACKSLASH -> ()
  | _ -> Alcotest.fail "expected BACKSLASH token"

let test_lex_let_keyword () =
  let tokens = Lexer.tokenize "let x" in
  match (List.hd tokens).token with
  | Lexer.LET -> ()
  | _ -> Alcotest.fail "expected LET token"

let test_lex_equals () =
  let tokens = Lexer.tokenize "=" in
  match (List.hd tokens).token with
  | Lexer.EQUALS -> ()
  | _ -> Alcotest.fail "expected EQUALS token"

let test_lex_let_in_ident () =
  let tokens = Lexer.tokenize "letter" in
  match (List.hd tokens).token with
  | Lexer.IDENT "letter" -> ()
  | _ -> Alcotest.fail "expected IDENT letter"

let test_lex_in_keyword () =
  let tokens = Lexer.tokenize "in" in
  match (List.hd tokens).token with
  | Lexer.IN -> ()
  | _ -> Alcotest.fail "expected IN token"

let test_lex_in_inside_ident () =
  let tokens = Lexer.tokenize "input" in
  match (List.hd tokens).token with
  | Lexer.IDENT "input" -> ()
  | _ -> Alcotest.fail "expected IDENT input, not IN"

let test_lex_in_as_prefix_of_ident () =
  let tokens = Lexer.tokenize "in_progress" in
  match (List.hd tokens).token with
  | Lexer.IDENT "in_progress" -> ()
  | _ -> Alcotest.fail "expected IDENT in_progress"

let test_lex_in_after_ident () =
  let tokens = Lexer.tokenize "x in" in
  match tokens with
  | [{ token = Lexer.IDENT "x"; _ }; { token = Lexer.IN; _ }; { token = Lexer.EOF; _ }] -> ()
  | _ -> Alcotest.fail "expected IDENT x, IN, EOF"

let test_lex_semicolon () =
  let tokens = Lexer.tokenize "a; b" in
  match tokens with
  | [ { token = IDENT "a"; _ }
    ; { token = SEMICOLON; _ }
    ; { token = IDENT "b"; _ }
    ; { token = EOF; _ } ] -> ()
  | _ -> Alcotest.fail "expected [IDENT a; SEMICOLON; IDENT b; EOF]"

let tests =
  [ "ident with digits", `Quick, test_lex_ident_with_digits
  ; "ident with hyphen", `Quick, test_lex_ident_with_hyphen
  ; "ident with underscore start", `Quick, test_lex_ident_with_underscore
  ; "all operators", `Quick, test_lex_all_operators
  ; "string", `Quick, test_lex_string
  ; "unterminated string", `Quick, test_lex_unterminated_string
  ; "comment", `Quick, test_lex_comment
  ; "loop keyword", `Quick, test_lex_loop_keyword
  ; "unexpected char", `Quick, test_lex_unexpected_char
  ; "fanout operator", `Quick, test_lex_fanout_operator
  ; "partial ampersand", `Quick, test_lex_partial_ampersand
  ; "double ampersand", `Quick, test_lex_double_ampersand
  ; "integer literal", `Quick, test_lex_integer
  ; "float literal", `Quick, test_lex_float
  ; "negative integer", `Quick, test_lex_negative_integer
  ; "negative float", `Quick, test_lex_negative_float
  ; "negative is not comment", `Quick, test_lex_negative_is_not_comment
  ; "trailing dot invalid", `Quick, test_lex_trailing_dot
  ; "leading dot invalid", `Quick, test_lex_leading_dot
  ; "unit suffix", `Quick, test_lex_unit_suffix
  ; "float unit suffix", `Quick, test_lex_float_unit_suffix
  ; "negative unit suffix", `Quick, test_lex_negative_unit_suffix
  ; "number before delimiter", `Quick, test_lex_number_before_delimiter
  ; "reserved hash", `Quick, test_lex_reserved_hash
  ; "unicode unit suffix", `Quick, test_lex_unicode_unit_suffix
  ; "unit suffix with digit", `Quick, test_lex_unit_suffix_with_digit
  ; "unicode CJK ident", `Quick, test_lex_unicode_cjk_ident
  ; "unicode Greek ident", `Quick, test_lex_unicode_greek_ident
  ; "unicode accented ident", `Quick, test_lex_unicode_accented_ident
  ; "unicode mixed ident", `Quick, test_lex_unicode_mixed_ident
  ; "unicode ident col", `Quick, test_lex_unicode_ident_col
  ; "mixed unicode col", `Quick, test_lex_mixed_unicode_col
  ; "unicode string col", `Quick, test_lex_unicode_string_col
  ; "multiline unicode col", `Quick, test_lex_multiline_unicode_col
  ; "malformed UTF-8", `Quick, test_lex_malformed_utf8
  ; "error col after unicode", `Quick, test_lex_error_col_after_unicode
  ; "question token", `Quick, test_lex_question
  ; "question with space", `Quick, test_lex_question_with_space
  ; "question after string", `Quick, test_lex_question_after_string
  ; "ident loc span", `Quick, test_lex_ident_loc_span
  ; "operator loc span", `Quick, test_lex_operator_loc_span
  ; "string loc span", `Quick, test_lex_string_loc_span
  ; "question loc span", `Quick, test_lex_question_loc_span
  ; "eof loc span", `Quick, test_lex_eof_loc_span
  ; "unicode ident loc span", `Quick, test_lex_unicode_ident_loc_span
  ; "double colon", `Quick, test_lex_double_colon
  ; "arrow token", `Quick, test_lex_arrow
  ; "type annotation tokens", `Quick, test_lex_type_annotation
  ; "colon still works", `Quick, test_lex_colon_still_works
  ; "arrow not negative", `Quick, test_lex_arrow_not_negative
  ; "arrow no whitespace", `Quick, test_lex_arrow_no_whitespace
  ; "arrow no whitespace in type ann", `Quick, test_lex_arrow_no_whitespace_in_type_ann
  ; "ident with hyphen before arrow", `Quick, test_lex_ident_with_hyphen_before_arrow
  ; "backslash token", `Quick, test_lex_backslash
  ; "let keyword", `Quick, test_lex_let_keyword
  ; "equals token", `Quick, test_lex_equals
  ; "let prefix in ident", `Quick, test_lex_let_in_ident
  ; "in keyword", `Quick, test_lex_in_keyword
  ; "in inside ident", `Quick, test_lex_in_inside_ident
  ; "in as prefix of ident", `Quick, test_lex_in_as_prefix_of_ident
  ; "in after ident", `Quick, test_lex_in_after_ident
  ; "semicolon", `Quick, test_lex_semicolon
  ]
