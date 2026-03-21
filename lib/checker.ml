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
  let rec count_question_seq = function
    | Seq (a, b) ->
      let qa = count_question_node a in
      let qb = count_question_seq b in
      qa + qb
    | e -> count_question_node e
  and count_question_node = function
    | Question _ -> 1
    | Alt _ -> -1
    | Node _ -> 0
    | Seq (a, b) -> count_question_node a + count_question_seq b
    | Group _ -> 0 (* defensive: unreachable after normalize *)
    | Par _ | Fanout _ | Loop _ -> 0
  in
  let check_question_balance expr =
    let n = count_question_seq (normalize expr) in
    let unmatched = max 0 n in
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
        | Question _ -> ()
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
