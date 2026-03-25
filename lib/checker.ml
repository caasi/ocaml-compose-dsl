open Ast

type error = { loc : loc; message : string }
type warning = { loc : loc; message : string }
type result = { errors : error list; warnings : warning list }

let rec normalize (e : expr) : expr =
  match e.desc with
  | Group inner -> normalize inner
  | Seq (a, b) -> { e with desc = Seq (normalize a, normalize b) }
  | Par (a, b) -> { e with desc = Par (normalize a, normalize b) }
  | Fanout (a, b) -> { e with desc = Fanout (normalize a, normalize b) }
  | Alt (a, b) -> { e with desc = Alt (normalize a, normalize b) }
  | Loop body -> { e with desc = Loop (normalize body) }
  | Node _ | Question _ -> e

let check (expr : expr) =
  let errors = ref [] in
  let warnings = ref [] in
  let add_error loc msg = errors := ({ loc; message = msg } : error) :: !errors in
  let add_warning loc msg = warnings := ({ loc; message = msg } : warning) :: !warnings in
  (* Left-to-right fold over Seq chains: +1 for Question, -1 (with
     saturation at 0) for Alt. Only downstream ||| can match upstream ?. *)
  let rec scan_questions counter (e : expr) =
    match e.desc with
    | Question _ -> counter + 1
    | Alt _ -> max 0 (counter - 1)
    | Node _ -> counter
    | Seq (a, b) ->
      let counter' = scan_questions counter a in
      scan_questions counter' b
    | Group _ -> counter (* defensive: unreachable after normalize *)
    | Par _ | Fanout _ | Loop _ -> counter
  in
  let check_question_balance (e : expr) =
    let unmatched = scan_questions 0 (normalize e) in
    for _ = 1 to unmatched do
      add_warning e.loc "'?' without matching '|||' in scope"
    done
  in
  let rec tail_has_question (e : expr) : bool =
    match e.desc with
    | Question _ -> true
    | Seq (_, b) -> tail_has_question b
    | Group _ -> false (* defensive: unreachable after normalize *)
    | _ -> false
  in
  let rec go (e : expr) =
    match e.desc with
    | Node n ->
      if n.name = "" && n.comments = [] then
        add_error e.loc "node has no purpose (no name and no comments)"
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
      let na = normalize a in
      let nb = normalize b in
      let left_tail_q = tail_has_question na in
      let right_tail_q = tail_has_question nb in
      if left_tail_q then
        add_warning a.loc
          "'?' as operand of '|||' does not match; \
           use 'question? >>> (left ||| right)' pattern";
      if right_tail_q then
        add_warning b.loc
          "'?' as operand of '|||' does not match; \
           use 'question? >>> (left ||| right)' pattern";
      (* Adjusted balance check: the tail ? already got a specific warning
         above, so subtract 1 to avoid a duplicate generic warning. *)
      let check_balance_adj has_tail_q ne (e : expr) =
        let unmatched = scan_questions 0 ne in
        let adj = max 0 (if has_tail_q then unmatched - 1 else unmatched) in
        for _ = 1 to adj do
          add_warning e.loc "'?' without matching '|||' in scope"
        done
      in
      check_balance_adj left_tail_q na a;
      check_balance_adj right_tail_q nb b;
      go a; go b
    | Loop body ->
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
