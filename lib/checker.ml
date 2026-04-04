open Ast

type warning = { loc : loc; message : string }
type result = { warnings : warning list }

let epistemic_pairs = [("branch", "merge")]
let epistemic_suggestions = [("leaf", "check")]

let rec collect_ident_names (e : expr) : string list =
  match e.desc with
  | Var name -> [name]
  | App (callee, args) ->
    collect_ident_names callee
    @ List.concat_map (fun arg ->
        match arg with
        | Positional e -> collect_ident_names e
        | Named _ -> []) args
  | Seq (a, b) | Par (a, b) | Fanout (a, b) | Alt (a, b) ->
    collect_ident_names a @ collect_ident_names b
  | Loop body | Question body | Group body -> collect_ident_names body
  | Unit | StringLit _ -> []
  | Lambda _ | Let _ -> []

let check_epistemic (e : expr) : warning list =
  let names = collect_ident_names e in
  let has name = List.mem name names in
  let warnings = ref [] in
  List.iter (fun (a, b) ->
    if has a && not (has b) then
      warnings :=
        { loc = e.loc;
          message =
            Printf.sprintf "'%s' without matching '%s' in the same statement" a b
        }
        :: !warnings)
    epistemic_pairs;
  List.iter (fun (a, b) ->
    if has a && not (has b) then
      warnings :=
        { loc = e.loc;
          message =
            Printf.sprintf
              "'%s' without '%s' \u{2014} consider adding verification" a b
        }
        :: !warnings)
    epistemic_suggestions;
  List.rev !warnings

let rec normalize (e : expr) : expr =
  match e.desc with
  | Group inner -> normalize inner
  | Seq (a, b) -> { e with desc = Seq (normalize a, normalize b) }
  | Par (a, b) -> { e with desc = Par (normalize a, normalize b) }
  | Fanout (a, b) -> { e with desc = Fanout (normalize a, normalize b) }
  | Alt (a, b) -> { e with desc = Alt (normalize a, normalize b) }
  | Loop body -> { e with desc = Loop (normalize body) }
  | Var _ | StringLit _ | Unit -> e
  | App (fn, args) ->
    { e with desc = App (normalize fn,
        List.map (function
          | Named a -> Named a
          | Positional e -> Positional (normalize e)) args) }
  | Question inner -> { e with desc = Question (normalize inner) }
  | Lambda _ | Let _ -> e

let check (expr : expr) =
  let warnings = ref [] in
  let add_warning loc msg = warnings := ({ loc; message = msg } : warning) :: !warnings in
  let rec scan_questions counter (e : expr) =
    match e.desc with
    | Question _ -> counter + 1
    | Alt _ -> max 0 (counter - 1)
    | Var _ | StringLit _ | Unit -> counter
    | App _ -> counter
    | Seq (a, b) ->
      let counter' = scan_questions counter a in
      scan_questions counter' b
    | Group _ -> counter
    | Par _ | Fanout _ | Loop _ -> counter
    | Lambda _ | Let _ -> counter
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
    | Group _ -> false
    | _ -> false
  in
  let rec go (e : expr) =
    match e.desc with
    | Var _ -> ()
    | StringLit _ | Unit -> ()
    | App (fn, args) ->
      go fn;
      List.iter (function
        | Named _ -> ()
        | Positional arg ->
          check_question_balance arg;
          go arg) args
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
    | Group inner -> go inner
    | Question inner -> go inner
    | Lambda _ | Let _ -> ()
  in
  check_question_balance expr;
  go expr;
  { warnings = List.rev !warnings @ check_epistemic expr }

let check_program (prog : Ast.program) : result =
  let warnings = List.concat_map (fun e -> (check e).warnings) prog in
  { warnings }
