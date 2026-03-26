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

let drop_trailing_empty = function
  | [] -> []
  | lines ->
    let rev = List.rev lines in
    match rev with
    | "" :: rest -> List.rev rest
    | _ -> lines

let extract input =
  let lines = drop_trailing_empty (String.split_on_char '\n' input) in
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
