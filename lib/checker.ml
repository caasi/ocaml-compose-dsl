open Ast

type error = { message : string }

let check expr =
  let errors = ref [] in
  let add msg = errors := { message = msg } :: !errors in
  let rec go = function
    | Node n ->
      if n.name = "" && n.comments = [] then
        add "node has no purpose (no name and no comments)"
    | Seq (a, b) -> go a; go b
    | Par (a, b) -> go a; go b
    | Fanout (a, b) -> go a; go b
    | Alt (a, b) -> go a; go b
    | Loop body ->
      let has_eval = ref false in
      let rec scan = function
        | Node n ->
          if String.length n.name >= 4 &&
             (let s = String.lowercase_ascii n.name in
              let len = String.length s in
              s = "evaluate" || s = "eval" || s = "check" || s = "test"
              || s = "judge" || s = "verify" || s = "validate"
              || (len >= 4 && String.sub s 0 4 = "eval")
              || (len >= 5 && String.sub s 0 5 = "check")) then
            has_eval := true
        | Seq (a, b) | Par (a, b) | Fanout (a, b) | Alt (a, b) -> scan a; scan b
        | Loop inner -> scan inner
        | Group inner -> scan inner
      in
      scan body;
      if not !has_eval then
        add "loop has no evaluation/termination node (expected a node like 'evaluate', 'check', 'verify', etc.)";
      go body
    | Group inner -> go inner
  in
  go expr;
  List.rev !errors
