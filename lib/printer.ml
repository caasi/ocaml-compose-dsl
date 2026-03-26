open Ast

let rec value_to_string = function
  | String s -> Printf.sprintf "String(%S)" s
  | Ident s -> Printf.sprintf "Ident(%S)" s
  | Number s -> Printf.sprintf "Number(%s)" s
  | List vs ->
    Printf.sprintf "List([%s])"
      (String.concat ", " (List.map value_to_string vs))

let arg_to_string (a : arg) =
  Printf.sprintf "%s: %s" a.key (value_to_string a.value)

let node_to_string_inner (n : node) =
  Printf.sprintf "%S, [%s], [%s]"
    n.name
    (String.concat ", " (List.map arg_to_string n.args))
    (String.concat ", " (List.map (Printf.sprintf "%S") n.comments))

let node_to_string (n : node) =
  Printf.sprintf "Node(%s)" (node_to_string_inner n)

let question_term_to_string = function
  | QNode n -> Printf.sprintf "QNode(%s)" (node_to_string_inner n)
  | QString s -> Printf.sprintf "QString(%S)" s

let rec to_string (e : expr) =
  let base = match e.desc with
    | Node n -> node_to_string n
    | Seq (a, b) -> Printf.sprintf "Seq(%s, %s)" (to_string a) (to_string b)
    | Par (a, b) -> Printf.sprintf "Par(%s, %s)" (to_string a) (to_string b)
    | Fanout (a, b) -> Printf.sprintf "Fanout(%s, %s)" (to_string a) (to_string b)
    | Alt (a, b) -> Printf.sprintf "Alt(%s, %s)" (to_string a) (to_string b)
    | Loop body -> Printf.sprintf "Loop(%s)" (to_string body)
    | Group inner -> Printf.sprintf "Group(%s)" (to_string inner)
    | Question qt -> Printf.sprintf "Question(%s)" (question_term_to_string qt)
    | Lambda (params, body) ->
      Printf.sprintf "Lambda([%s], %s)"
        (String.concat ", " (List.map (Printf.sprintf "%S") params)) (to_string body)
    | Var name -> Printf.sprintf "Var(%S)" name
    | App (fn, args) ->
      Printf.sprintf "App(%s, [%s])" (to_string fn)
        (String.concat ", " (List.map to_string args))
    | Let (name, value, body) ->
      Printf.sprintf "Let(%S, %s, %s)" name (to_string value) (to_string body)
  in
  match e.type_ann with
  | None -> base
  | Some { input; output } -> Printf.sprintf "TypeAnn(%s, %S, %S)" base input output
