open Ast

type error = { message : string }
type warning = { message : string }
type result = { errors : error list; warnings : warning list }

let rec normalize = function
  | Group inner -> normalize inner
  | Seq (a, b) -> Seq (normalize a, normalize b)
  | Par (a, b) -> Par (normalize a, normalize b)
  | Fanout (a, b) -> Fanout (normalize a, normalize b)
  | Alt (a, b) -> Alt (normalize a, normalize b)
  | Loop body -> Loop (normalize body)
  | (Node _ | Question _) as e -> e

let check expr =
  let errors = ref [] in
  let warnings = ref [] in
  let add_error msg = errors := ({ message = msg } : error) :: !errors in
  let add_warning msg = warnings := ({ message = msg } : warning) :: !warnings in
  (* Left-to-right fold over Seq chains: +1 for Question, -1 (with
     saturation at 0) for Alt. Only downstream ||| can match upstream ?. *)
  let rec scan_questions counter = function
    | Question _ -> counter + 1
    | Alt _ -> max 0 (counter - 1)
    | Node _ -> counter
    | Seq (a, b) ->
      let counter' = scan_questions counter a in
      scan_questions counter' b
    | Group _ -> counter (* defensive: unreachable after normalize *)
    | Par _ | Fanout _ | Loop _ -> counter
  in
  let check_question_balance expr =
    let unmatched = scan_questions 0 (normalize expr) in
    for _ = 1 to unmatched do
      add_warning "'?' without matching '|||' in scope"
    done
  in
  let rec go = function
    | Node n ->
      if n.name = "" && n.comments = [] then
        add_error "node has no purpose (no name and no comments)"
    | Seq (a, b) -> go a; go b
    | Par (a, b) ->
      check_question_balance a;
      check_question_balance b;
      go a; go b
    | Fanout (a, b) ->
      check_question_balance a;
      check_question_balance b;
      go a; go b
    | Alt (a, b) ->
      check_question_balance a;
      check_question_balance b;
      go a; go b
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
        | Question (QNode n) -> scan (Node n)
        | Question (QString _) -> ()
      in
      scan body;
      if not !has_eval then
        add_error "loop has no evaluation/termination node (expected a node like 'evaluate', 'check', 'verify', etc.)";
      check_question_balance body;
      go body
    | Group inner ->
      (* Group is syntactic (precedence), not a scope boundary.
         Balance checking happens on the enclosing scope after normalize
         strips all Group wrappers. *)
      go inner
    | Question _ -> ()
  in
  check_question_balance expr;
  go expr;
  { errors = List.rev !errors; warnings = List.rev !warnings }
