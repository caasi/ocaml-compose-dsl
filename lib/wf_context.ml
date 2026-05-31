(* Wf_context: comment/prose recovery for the workflow emitter.
   Provides utilities to extract -- comments from source tokens and
   Markdown prose from literate-mode input. *)

(* "-- foo" → "foo". The tokenizer already strips the prefix from COMMENT
   tokens, so this matters only for the literate/prose path (raw "-- …" lines). *)
let strip_dashes s =
  let s = String.trim s in
  if String.length s >= 2 && s.[0] = '-' && s.[1] = '-'
  then String.trim (String.sub s 2 (String.length s - 2)) else s

(* Recover comments (line, text) via the batch tokenizer — NOT the AST.
   Lexer.tokenize returns `located` records: { token; loc }. *)
let comments_of_source (src : string) : (int * string) list =
  Lexer.tokenize src
  |> List.filter_map (fun (t : Lexer.located) ->
       match t.token with
       | Lexer.COMMENT text -> Some (t.loc.start.line, String.trim text)
       | _ -> None)

let derive_description comments ~fallback =
  match comments with c :: _ -> strip_dashes c | [] -> fallback

let derive_name ~path =
  match path with
  | None -> "workflow"
  | Some p ->
    let base = Filename.remove_extension (Filename.basename p) in
    if base = "" then "workflow" else base

(* Standard mode: consecutive leading comments (from line 1) → file-header banner. *)
let leading_block (comments : (int * string) list) : string list =
  let rec take expected = function
    | (ln, txt) :: rest when ln = expected -> txt :: take (expected + 1) rest
    | _ -> []
  in take 1 comments

(* Strip a trailing CR so CRLF-line-ending Markdown works correctly.
   Markdown.is_opening_fence checks for exact trailing whitespace; a '\r'
   left on the line defeats that check and causes fence lines to be
   collected into prose. *)
let strip_cr s =
  let n = String.length s in
  if n > 0 && s.[n-1] = '\r' then String.sub s 0 (n-1) else s

(* Literate mode: the doc's intro prose = non-empty lines BEFORE the first arrow
   fence (the surrounding Markdown that combine() discards). Header/description
   come from here when the .arr blocks carry no -- comments. *)
let markdown_prose (raw : string) : string list =
  let rec collect acc = function
    | [] -> List.rev acc
    | line :: _ when Markdown.is_opening_fence line -> List.rev acc
    | line :: rest ->
      let t = String.trim line in
      collect (if t = "" then acc else t :: acc) rest
  in collect [] (List.map strip_cr (String.split_on_char '\n' raw))
