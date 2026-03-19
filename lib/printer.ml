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

let node_to_string (n : node) =
  Printf.sprintf "Node(%S, [%s], [%s])"
    n.name
    (String.concat ", " (List.map arg_to_string n.args))
    (String.concat ", " (List.map (Printf.sprintf "%S") n.comments))

let rec to_string = function
  | Node n -> node_to_string n
  | Seq (a, b) -> Printf.sprintf "Seq(%s, %s)" (to_string a) (to_string b)
  | Par (a, b) -> Printf.sprintf "Par(%s, %s)" (to_string a) (to_string b)
  | Fanout (a, b) -> Printf.sprintf "Fanout(%s, %s)" (to_string a) (to_string b)
  | Alt (a, b) -> Printf.sprintf "Alt(%s, %s)" (to_string a) (to_string b)
  | Loop body -> Printf.sprintf "Loop(%s)" (to_string body)
  | Group inner -> Printf.sprintf "Group(%s)" (to_string inner)
