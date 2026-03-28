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

let call_arg_to_string to_s = function
  | Named a -> Printf.sprintf "Named(%s)" (arg_to_string a)
  | Positional e -> Printf.sprintf "Positional(%s)" (to_s e)

let rec to_string (e : expr) =
  let base = match e.desc with
    | Unit -> "Unit"
    | Var name -> Printf.sprintf "Var(%S)" name
    | StringLit s -> Printf.sprintf "StringLit(%S)" s
    | Seq (a, b) -> Printf.sprintf "Seq(%s, %s)" (to_string a) (to_string b)
    | Par (a, b) -> Printf.sprintf "Par(%s, %s)" (to_string a) (to_string b)
    | Fanout (a, b) -> Printf.sprintf "Fanout(%s, %s)" (to_string a) (to_string b)
    | Alt (a, b) -> Printf.sprintf "Alt(%s, %s)" (to_string a) (to_string b)
    | Loop body -> Printf.sprintf "Loop(%s)" (to_string body)
    | Group inner -> Printf.sprintf "Group(%s)" (to_string inner)
    | Question inner -> Printf.sprintf "Question(%s)" (to_string inner)
    | Lambda (params, body) ->
      Printf.sprintf "Lambda([%s], %s)"
        (String.concat ", " (List.map (Printf.sprintf "%S") params)) (to_string body)
    | App (fn, args) ->
      Printf.sprintf "App(%s, [%s])" (to_string fn)
        (String.concat ", " (List.map (call_arg_to_string to_string) args))
    | Let (name, value, body) ->
      Printf.sprintf "Let(%S, %s, %s)" name (to_string value) (to_string body)
  in
  match e.type_ann with
  | None -> base
  | Some { input; output } -> Printf.sprintf "TypeAnn(%s, %S, %S)" base input output
