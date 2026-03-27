open Compose_dsl

let parse_ok input =
  let tokens = Lexer.tokenize input in
  Parser.parse_program tokens

let desc_of input = (parse_ok input).desc

let parse_fails input =
  match parse_ok input with
  | _ -> Alcotest.fail "expected parse error"
  | exception Parser.Parse_error _ -> ()

let check_ok input =
  let ast = parse_ok input in
  let ast = Reducer.reduce ast in
  let result = Checker.check ast in
  Alcotest.(check int) "no checker warnings" 0 (List.length result.Checker.warnings);
  ast

let check_ok_with_warnings input =
  let ast = parse_ok input in
  let ast = Reducer.reduce ast in
  let result = Checker.check ast in
  result.Checker.warnings

let has_warning_containing substr warnings =
  List.exists (fun (w : Checker.warning) ->
    let len = String.length substr in
    let rec scan i =
      if i + len > String.length w.message then false
      else if String.sub w.message i len = substr then true
      else scan (i + 1)
    in
    scan 0
  ) warnings

let contains s sub =
  let len = String.length sub in
  let rec scan i = i + len <= String.length s && (String.sub s i len = sub || scan (i + 1)) in
  scan 0

let reduce_ok input =
  let tokens = Lexer.tokenize input in
  let ast = Parser.parse_program tokens in
  Reducer.reduce ast

let reduce_fails input =
  match reduce_ok input with
  | _ -> Alcotest.fail "expected reduce error"
  | exception Reducer.Reduce_error _ -> ()
