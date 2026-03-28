type block = {
  content : string;
  markdown_start : int;
}

let is_opening_fence line =
  let len = String.length line in
  let i = ref 0 in
  (* skip up to 3 leading spaces *)
  while !i < len && !i < 3 && line.[!i] = ' ' do incr i done;
  (* must have exactly 3 backticks *)
  if !i + 3 > len then false
  else if line.[!i] <> '`' || line.[!i+1] <> '`' || line.[!i+2] <> '`' then false
  else if !i + 3 < len && line.[!i+3] = '`' then false (* 4+ backticks *)
  else begin
    i := !i + 3;
    (* extract info string *)
    let info_start = !i in
    while !i < len && line.[!i] <> ' ' && line.[!i] <> '\t' do incr i done;
    let info = String.sub line info_start (!i - info_start) in
    (* rest must be whitespace *)
    while !i < len && (line.[!i] = ' ' || line.[!i] = '\t') do incr i done;
    !i = len && (info = "arrow" || info = "arr")
  end

let is_closing_fence line =
  let len = String.length line in
  let i = ref 0 in
  while !i < len && !i < 3 && line.[!i] = ' ' do incr i done;
  if !i + 3 > len then false
  else if line.[!i] <> '`' || line.[!i+1] <> '`' || line.[!i+2] <> '`' then false
  else if !i + 3 < len && line.[!i+3] = '`' then false
  else begin
    i := !i + 3;
    while !i < len && (line.[!i] = ' ' || line.[!i] = '\t') do incr i done;
    !i = len
  end

let drop_last_empty = function
  | [] -> []
  | lines ->
    let rev = List.rev lines in
    match rev with
    | "" :: rest -> List.rev rest
    | _ -> lines

let strip_cr line =
  let len = String.length line in
  if len > 0 && line.[len - 1] = '\r' then String.sub line 0 (len - 1)
  else line

let extract input =
  let lines =
    input
    |> String.split_on_char '\n'
    |> List.map strip_cr
    |> drop_last_empty
  in
  let rec scan lines line_num state acc =
    match lines, state with
    | [], `Outside -> List.rev acc
    | [], `Inside (start, buf) ->
      let content = Buffer.contents buf in
      List.rev ({ content; markdown_start = start } :: acc)
    | line :: rest, `Outside ->
      if is_opening_fence line then
        scan rest (line_num + 1) (`Inside (line_num + 1, Buffer.create 256)) acc
      else
        scan rest (line_num + 1) `Outside acc
    | line :: rest, `Inside (start, buf) ->
      if is_closing_fence line then begin
        let content = Buffer.contents buf in
        scan rest (line_num + 1) `Outside ({ content; markdown_start = start } :: acc)
      end else begin
        Buffer.add_string buf line;
        Buffer.add_char buf '\n';
        scan rest (line_num + 1) (`Inside (start, buf)) acc
      end
  in
  scan lines 1 `Outside []

(* Counts '\n' characters. extract always appends '\n' after each content
   line, and combine normalizes content to end with '\n' for external
   callers, so count_lines == number of lines in the block. *)
let count_lines s =
  let n = ref 0 in
  String.iter (fun c -> if c = '\n' then incr n) s;
  !n

let combine blocks =
  match blocks with
  | [] -> ("", [])
  | _ ->
    let buf = Buffer.create 1024 in
    let rec build blocks current_line acc =
      match blocks with
      | [] -> (Buffer.contents buf, List.rev acc)
      | b :: rest ->
        let content =
          if b.content = "" || b.content.[String.length b.content - 1] = '\n'
          then b.content
          else b.content ^ "\n"
        in
        if current_line > 1 then Buffer.add_string buf ";\n";
        Buffer.add_string buf content;
        let entry = (current_line, b.markdown_start) in
        let lines_in_block = count_lines content in
        (* +1 accounts for the separator ";\n" emitted before the next block *)
        let next_line = current_line + lines_in_block + (if rest <> [] then 1 else 0) in
        build rest next_line (entry :: acc)
    in
    build blocks 1 []

let translate_line table line =
  match table with
  | [] -> line
  | _ ->
    let rec find = function
      | [] -> line
      | [(cs, ms)] -> line - cs + ms
      | (cs, ms) :: ((cs2, _) :: _ as rest) ->
        if line < cs2 then line - cs + ms
        else find rest
    in
    find table
