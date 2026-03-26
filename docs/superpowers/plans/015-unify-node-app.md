# Unify Node and App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the `Node` AST variant and unify it with `App` using a `call_arg` type that supports mixed named/positional arguments, fixing issue #21.

**Architecture:** Replace `Node of node` with `Var of string` (bare names) and `App of expr * call_arg list` (names with args). Remove parser scope tracking. Allow free `Var` and unbound `App` to survive reduction. Update checker to treat `Var` and `App` as leaves for structural analysis.

**Tech Stack:** OCaml 5.1, Dune, Alcotest

**Spec:** `docs/superpowers/specs/2026-03-27-unify-node-app-design.md`

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `lib/ast.ml` | Modify | Remove `node` type, `Node` variant. Add `call_arg` type. Change `App` to use `call_arg list`. |
| `lib/parser.ml` | Modify | Remove scope tracking. Unify named/positional parsing with per-arg disambiguation. All idents produce `Var`/`App(Var,...)`. |
| `lib/reducer.ml` | Modify | Handle `call_arg`. Allow free `Var` and unbound `App`. Update `desugar`/`substitute`/`beta_reduce`/`verify`. |
| `lib/checker.ml` | Modify | Replace `Node` matches with `Var`/`App`. Treat `App` as leaf in `scan_questions`. Independently check positional arg sub-expressions in `go`. |
| `lib/printer.ml` | Modify | Remove `Node`/`node_to_string`. Add `call_arg_to_string`. Update `App` printing. |
| `test/test_compose_dsl.ml` | Modify | Update all `Node`-matching tests to use `Var`/`App`. Add mixed-arg tests. Update printer expected output. |
| `README.md` | Modify | Update EBNF grammar: remove `node` rule, add `call_args`/`call_arg` rules, update `term`. |
| `CLAUDE.md` | Modify | Update Ast documentation to reflect new types. |

---

### Task 1: AST — Add `call_arg`, remove `Node`

**Files:**
- Modify: `lib/ast.ml`

This task changes the core type definitions. It will break the build (all other modules reference `Node`), which is expected — subsequent tasks fix each module.

- [ ] **Step 1: Modify `lib/ast.ml`**

Remove the `node` type and `Node` variant. Add `call_arg`. Change `App` signature.

```ocaml
type pos = { line : int; col : int }
type loc = { start : pos; end_ : pos }

type value =
  | String of string
  | Ident of string
  | Number of string
  | List of value list

type arg = { key : string; value : value }

(* node type removed *)

type type_ann = { input : string; output : string }

type expr = { loc : loc; desc : expr_desc; type_ann : type_ann option }
and expr_desc =
  | Var of string                   (** variable reference, bound or free *)
  | StringLit of string             (** string literal as expression *)
  | Seq of expr * expr              (** [>>>] *)
  | Par of expr * expr              (** [***] *)
  | Fanout of expr * expr           (** [&&&] *)
  | Alt of expr * expr              (** [|||] *)
  | Loop of expr
  | Group of expr
  | Question of expr                (** [?] — parser allows on Var, StringLit, App *)
  | Lambda of string list * expr    (** [\x, y -> body] *)
  | App of expr * call_arg list     (** unified application, mixed named/positional *)
  | Let of string * expr * expr     (** [let x = expr] followed by rest of program *)

and call_arg =
  | Named of arg                    (** key: value — static configuration *)
  | Positional of expr              (** pipeline expression *)
```

Note: `call_arg` must be defined after `expr` (mutual recursion via `Positional of expr`), so it goes in the `and` chain.

- [ ] **Step 2: Verify the build fails with expected errors**

Run: `dune build 2>&1 | head -30`
Expected: Compilation errors in parser.ml, reducer.ml, checker.ml, printer.ml referencing `Node` and `App` type mismatches. This confirms the type change propagated.

- [ ] **Step 3: Commit**

```bash
git add lib/ast.ml
git commit -m "refactor(ast): remove Node, add call_arg, unify App"
```

---

### Task 2: Printer — Update for new AST

**Files:**
- Modify: `lib/printer.ml`

Update the printer first because tests compare against `Printer.to_string` output. Getting the printer right early makes subsequent test updates straightforward.

- [ ] **Step 1: Rewrite `lib/printer.ml`**

```ocaml
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
```

Key changes:
- Removed `node_to_string_inner` and `node_to_string`
- Added `call_arg_to_string` — wraps each arg with `Named(...)` or `Positional(...)`
- `App` now prints `call_arg list` using `call_arg_to_string`
- `Var` already existed and is unchanged

- [ ] **Step 2: Verify printer compiles**

Run: `dune build 2>&1 | grep printer`
Expected: No errors from printer.ml (other modules still broken).

- [ ] **Step 3: Commit**

```bash
git add lib/printer.ml
git commit -m "refactor(printer): update for unified App with call_arg"
```

---

### Task 3: Parser — Remove scope, unify call arg parsing

**Files:**
- Modify: `lib/parser.ml`

This is the largest change. Remove scope tracking, unify named/positional arg parsing with per-arg disambiguation, produce `Var` for all idents.

- [ ] **Step 1: Rewrite `lib/parser.ml`**

Key changes from current parser:

**Remove scope:** Delete `scope : StringSet.t` from `state`, remove `StringSet` module. Remove all `st.scope` references — `in_scope` checks, `old_scope` save/restore in lambda and let.

**Replace `parse_args`** (lines 71-90, named-only) with `parse_call_args` that handles mixed args:

```ocaml
let rec parse_call_arg st =
  let t = current st in
  match t.token with
  | Lexer.IDENT _ ->
    (* Peek ahead: IDENT COLON → Named arg *)
    (match st.tokens with
     | _ :: { Lexer.token = Lexer.COLON; _ } :: _ ->
       let key = match t.token with Lexer.IDENT k -> k | _ -> assert false in
       advance st;  (* consume IDENT *)
       advance st;  (* consume COLON *)
       let value = parse_value st in
       Named { key; value }
     | _ ->
       (* Not IDENT COLON → Positional *)
       Positional (parse_seq_expr st))
  | _ ->
    (* Anything else starts a positional arg *)
    Positional (parse_seq_expr st)

and parse_call_args st =
  let args = ref [] in
  let rec go () =
    let t = current st in
    match t.token with
    | Lexer.RPAREN -> ()
    | _ ->
      args := parse_call_arg st :: !args;
      let t2 = current st in
      (match t2.token with
       | Lexer.COMMA ->
         advance st;
         let t_after = current st in
         (match t_after.token with
          | Lexer.RPAREN ->
            raise (Parse_error (t_after.loc.start, "unexpected trailing comma in argument list"))
          | _ -> go ())
       | Lexer.RPAREN -> ()
       | _ -> raise (Parse_error (t2.loc.start, "expected ',' or ')'")))
  in
  go ();
  List.rev !args
```

**Rewrite `parse_term` IDENT branch** (lines 206-294):

```ocaml
| Lexer.IDENT name ->
  advance st;
  let t_next = current st in
  (match t_next.token with
   | Lexer.LPAREN ->
     advance st;
     let args = parse_call_args st in
     expect st (fun tok -> tok = Lexer.RPAREN) "expected ')'";
     let rparen_end = st.last_loc.end_ in
     let _ = eat_comments st in
     let app_expr = mk_expr { start = t.loc.start; end_ = rparen_end }
       (App (mk_expr t.loc (Var name), args)) in
     let t2 = current st in
     (match t2.token with
      | Lexer.QUESTION ->
        advance st;
        mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (Question app_expr)
      | _ -> app_expr)
   | _ ->
     let ident_end = st.last_loc.end_ in
     let _ = eat_comments st in
     let var_expr = mk_expr { start = t.loc.start; end_ = ident_end } (Var name) in
     let t2 = current st in
     (match t2.token with
      | Lexer.QUESTION ->
        advance st;
        mk_expr { start = t.loc.start; end_ = st.last_loc.end_ } (Question var_expr)
      | _ -> var_expr))
```

**Rewrite `parse_lambda`:** Remove scope manipulation. Lambda params are just recorded, not added to scope:

```ocaml
and parse_lambda st start_loc =
  let params = ref [] in
  let seen = ref StringSet.empty in
  let rec read_params () =
    let t = current st in
    match t.token with
    | Lexer.IDENT name ->
      if StringSet.mem name !seen then
        raise (Parse_error (t.loc.start,
          Printf.sprintf "duplicate parameter '%s' in lambda" name));
      seen := StringSet.add name !seen;
      advance st;
      params := name :: !params;
      let t2 = current st in
      (match t2.token with
       | Lexer.COMMA -> advance st; read_params ()
       | Lexer.ARROW -> advance st
       | _ -> raise (Parse_error (t2.loc.start, "expected ',' or '->' in lambda")))
    | _ -> raise (Parse_error (t.loc.start, "expected parameter name"))
  in
  read_params ();
  let param_list = List.rev !params in
  let body = parse_seq_expr st in
  mk_expr { start = start_loc; end_ = body.loc.end_ } (Lambda (param_list, body))
```

Note: `StringSet` is still used for duplicate param detection in lambda, so keep the module but remove it from parser state.

**Rewrite `parse_program`:** Remove scope from let binding:

```ocaml
let parse_program tokens =
  let st = make tokens in
  let rec read_lets () =
    let _ = eat_comments st in
    let t = current st in
    match t.token with
    | Lexer.LET ->
      advance st;
      let t_name = current st in
      let name = match t_name.token with
        | Lexer.IDENT s -> advance st; s
        | _ -> raise (Parse_error (t_name.loc.start, "expected identifier after 'let'"))
      in
      expect st (fun tok -> tok = Lexer.EQUALS) "expected '=' after let binding name";
      let value = parse_seq_expr st in
      let rest = read_lets () in
      mk_expr { start = t.loc.start; end_ = rest.loc.end_ } (Let (name, value, rest))
    | _ ->
      let expr = parse_seq_expr st in
      let t_end = current st in
      (match t_end.token with
       | Lexer.EOF -> ()
       | _ -> raise (Parse_error (t_end.loc.start, "expected end of input")));
      expr
  in
  read_lets ()
```

**Update `attach_comments_right`:** Replace `Node` branch. Comments on `Var` and `App` are dropped (known regression):

```ocaml
let rec attach_comments_right (e : expr) comments =
  if comments = [] then e
  else match e.desc with
    | Seq (a, b) -> { e with desc = Seq (a, attach_comments_right b comments) }
    | Par (a, b) -> { e with desc = Par (a, attach_comments_right b comments) }
    | Fanout (a, b) -> { e with desc = Fanout (a, attach_comments_right b comments) }
    | Alt (a, b) -> { e with desc = Alt (a, attach_comments_right b comments) }
    | Group inner -> { e with desc = Group (attach_comments_right inner comments) }
    | Loop inner -> { e with desc = Loop (attach_comments_right inner comments) }
    | StringLit _ -> e
    | Question inner -> { e with desc = Question (attach_comments_right inner comments) }
    | Var _ | App _ | Lambda _ | Let _ -> e
```

**Update `make`:** Remove scope from state:

```ocaml
type state = {
  mutable tokens : Lexer.located list;
  mutable last_loc : loc;
}

let make tokens = { tokens; last_loc = dummy_loc }
```

- [ ] **Step 2: Verify parser compiles**

Run: `dune build 2>&1 | grep -v "Warning"`
Expected: parser.ml compiles. reducer.ml and checker.ml still have errors (they reference `Node`).

- [ ] **Step 3: Commit**

```bash
git add lib/parser.ml
git commit -m "refactor(parser): remove scope tracking, unify call arg parsing"
```

---

### Task 4: Reducer — Handle `call_arg`, allow free variables

**Files:**
- Modify: `lib/reducer.ml`

- [ ] **Step 1: Rewrite `lib/reducer.ml`**

Key changes:

**`free_vars`:** Replace `Node` with `Var`, handle `call_arg`:

```ocaml
let rec free_vars (e : expr) : StringSet.t =
  match e.desc with
  | Var v -> StringSet.singleton v
  | StringLit _ -> StringSet.empty
  | Question inner -> free_vars inner
  | Seq (a, b) | Par (a, b) | Fanout (a, b) | Alt (a, b) ->
    StringSet.union (free_vars a) (free_vars b)
  | Loop body | Group body -> free_vars body
  | Lambda (params, body) ->
    let fv = free_vars body in
    List.fold_left (fun s p -> StringSet.remove p s) fv params
  | App (fn, args) ->
    List.fold_left (fun s a ->
      match a with
      | Named _ -> s
      | Positional e -> StringSet.union s (free_vars e))
      (free_vars fn) args
  | Let (n, v, b) ->
    StringSet.union (free_vars v) (StringSet.remove n (free_vars b))
```

**`desugar`:** Replace `Node` with `Var`, wrap let value in `Positional`:

```ocaml
let rec desugar (e : expr) : expr =
  match e.desc with
  | Let (name, value, body) ->
    let value' = desugar value in
    let body' = desugar body in
    { e with desc = App ({ e with desc = Lambda ([name], body') }, [Positional value']) }
  | Seq (a, b) -> { e with desc = Seq (desugar a, desugar b) }
  | Par (a, b) -> { e with desc = Par (desugar a, desugar b) }
  | Fanout (a, b) -> { e with desc = Fanout (desugar a, desugar b) }
  | Alt (a, b) -> { e with desc = Alt (desugar a, desugar b) }
  | Loop body -> { e with desc = Loop (desugar body) }
  | Group inner -> { e with desc = Group (desugar inner) }
  | Lambda (params, body) -> { e with desc = Lambda (params, desugar body) }
  | App (fn, args) ->
    { e with desc = App (desugar fn, List.map desugar_call_arg args) }
  | Var _ | StringLit _ -> e
  | Question inner -> { e with desc = Question (desugar inner) }

and desugar_call_arg = function
  | Named a -> Named a
  | Positional e -> Positional (desugar e)
```

**`substitute`:** Replace `Node` with `Var`, handle `call_arg`:

```ocaml
let rec substitute fresh_name (name : string) (replacement : expr) (e : expr) : expr =
  match e.desc with
  | Var v when v = name ->
    (match e.type_ann with
     | None -> replacement
     | Some _ -> { replacement with type_ann = e.type_ann })
  | Var _ | StringLit _ -> e
  | Question inner -> { e with desc = Question (substitute fresh_name name replacement inner) }
  | Seq (a, b) -> { e with desc = Seq (substitute fresh_name name replacement a, substitute fresh_name name replacement b) }
  | Par (a, b) -> { e with desc = Par (substitute fresh_name name replacement a, substitute fresh_name name replacement b) }
  | Fanout (a, b) -> { e with desc = Fanout (substitute fresh_name name replacement a, substitute fresh_name name replacement b) }
  | Alt (a, b) -> { e with desc = Alt (substitute fresh_name name replacement a, substitute fresh_name name replacement b) }
  | Loop body -> { e with desc = Loop (substitute fresh_name name replacement body) }
  | Group inner -> { e with desc = Group (substitute fresh_name name replacement inner) }
  | Lambda (params, body) ->
    if List.mem name params then e
    else
      let repl_fv = free_vars replacement in
      let params', body' = List.fold_left (fun (ps, b) p ->
        if StringSet.mem p repl_fv then
          let p' = fresh_name p in
          (p' :: ps, substitute fresh_name p { e with desc = Var p'; type_ann = None } b)
        else (p :: ps, b)
      ) ([], body) params in
      let params' = List.rev params' in
      { e with desc = Lambda (params', substitute fresh_name name replacement body') }
  | App (fn, args) ->
    { e with desc = App (
        substitute fresh_name name replacement fn,
        List.map (substitute_call_arg fresh_name name replacement) args) }
  | Let (n, v, b) ->
    let v' = substitute fresh_name name replacement v in
    if n = name then { e with desc = Let (n, v', b) }
    else { e with desc = Let (n, v', substitute fresh_name name replacement b) }

and substitute_call_arg fresh_name name replacement = function
  | Named a -> Named a  (* Named args contain values, not expressions *)
  | Positional e -> Positional (substitute fresh_name name replacement e)
```

**`beta_reduce`:** Handle `call_arg list`, allow free Var callee:

```ocaml
let rec beta_reduce fresh_name (e : expr) : expr =
  match e.desc with
  | App (fn, args) ->
    let fn' = beta_reduce fresh_name fn in
    let args' = List.map (beta_reduce_call_arg fresh_name) args in
    (match fn'.desc with
     | Lambda (params, body) ->
       (* Extract positional args only *)
       let positional = List.filter_map (function
         | Positional e -> Some e | Named _ -> None) args' in
       let named = List.filter_map (function
         | Named a -> Some a | Positional _ -> None) args' in
       if named <> [] then
         raise (Reduce_error (e.loc.start, "cannot pass named args to lambda"));
       let n_params = List.length params in
       let n_args = List.length positional in
       if n_params <> n_args then
         raise (Reduce_error (e.loc.start,
           Printf.sprintf "arity mismatch: expected %d arguments but got %d" n_params n_args));
       let result = List.fold_left2
         (fun acc param arg -> substitute fresh_name param arg acc)
         body params positional
       in
       beta_reduce fresh_name result
     | Var _ ->
       (* Free variable application — survives reduction *)
       { e with desc = App (fn', args') }
     | StringLit s ->
       raise (Reduce_error (e.loc.start,
         Printf.sprintf "%S is a string literal and cannot be applied" s))
     | _ ->
       raise (Reduce_error (e.loc.start, "expression is not a function and cannot be applied")))
  | Seq (a, b) -> { e with desc = Seq (beta_reduce fresh_name a, beta_reduce fresh_name b) }
  | Par (a, b) -> { e with desc = Par (beta_reduce fresh_name a, beta_reduce fresh_name b) }
  | Fanout (a, b) -> { e with desc = Fanout (beta_reduce fresh_name a, beta_reduce fresh_name b) }
  | Alt (a, b) -> { e with desc = Alt (beta_reduce fresh_name a, beta_reduce fresh_name b) }
  | Loop body -> { e with desc = Loop (beta_reduce fresh_name body) }
  | Group inner -> { e with desc = Group (beta_reduce fresh_name inner) }
  | Lambda _ -> e
  | Var _ | StringLit _ | Let _ -> e
  | Question inner -> { e with desc = Question (beta_reduce fresh_name inner) }

and beta_reduce_call_arg fresh_name = function
  | Named a -> Named a
  | Positional e -> Positional (beta_reduce fresh_name e)
```

**`verify`:** Allow free `Var` and `App(Var _, _)`:

```ocaml
let rec verify (e : expr) : unit =
  match e.desc with
  | Lambda _ ->
    raise (Reduce_error (e.loc.start, "lambda expression not fully applied"))
  | Var _ -> ()  (* free variable — allowed *)
  | App ({ desc = Var _; _ }, args) ->
    (* Free variable application — verify positional arg sub-expressions *)
    List.iter (function
      | Named _ -> ()
      | Positional e -> verify e) args
  | App _ ->
    raise (Reduce_error (e.loc.start, "unreduced application"))
  | Let _ ->
    raise (Reduce_error (e.loc.start, "unreduced let binding"))
  | Seq (a, b) | Par (a, b) | Fanout (a, b) | Alt (a, b) -> verify a; verify b
  | Loop body | Group body -> verify body
  | StringLit _ -> ()
  | Question inner -> verify inner
```

- [ ] **Step 2: Verify reducer compiles**

Run: `dune build 2>&1 | grep -v "Warning"`
Expected: reducer.ml compiles. Only checker.ml still has errors.

- [ ] **Step 3: Commit**

```bash
git add lib/reducer.ml
git commit -m "refactor(reducer): handle call_arg, allow free Var and unbound App"
```

---

### Task 5: Checker — Replace `Node` with `Var`/`App`

**Files:**
- Modify: `lib/checker.ml`

- [ ] **Step 1: Rewrite `lib/checker.ml`**

```ocaml
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
  | Var _ | StringLit _ -> e
  | App (fn, args) ->
    { e with desc = App (normalize fn,
        List.map (function
          | Named a -> Named a
          | Positional e -> Positional (normalize e)) args) }
  | Question inner -> { e with desc = Question (normalize inner) }
  | Lambda _ | Let _ -> e

let check (expr : expr) =
  let errors = ref [] in
  let warnings = ref [] in
  let add_warning loc msg = warnings := ({ loc; message = msg } : warning) :: !warnings in
  let rec scan_questions counter (e : expr) =
    match e.desc with
    | Question _ -> counter + 1
    | Alt _ -> max 0 (counter - 1)
    | Var _ | StringLit _ -> counter
    | App _ -> counter  (* isolated sub-expression — no leaking *)
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
    | StringLit _ -> ()
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
  { errors = List.rev !errors; warnings = List.rev !warnings }
```

Key changes:
- `Node _` replaced with `Var _` everywhere
- `App` in `normalize`: recursively normalizes callee and Positional args
- `App` in `scan_questions`: treated as leaf (`counter` — no leaking)
- `App` in `go`: recursively checks callee + independently checks each Positional arg
- Removed `add_error` (no longer needed — `Node` empty name check is gone since `Var ""` is impossible from parser)

- [ ] **Step 2: Build the project**

Run: `dune build`
Expected: Clean compilation, no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/checker.ml
git commit -m "refactor(checker): replace Node with Var/App, isolated positional arg checking"
```

---

### Task 6: Tests — Update existing tests for new AST

**Files:**
- Modify: `test/test_compose_dsl.ml`

This task updates all existing tests that reference `Node` to use `Var`/`App`. The tests should compile and most should pass after this change (some may need printer output updates).

- [ ] **Step 1: Write failing test for the new feature (mixed args)**

Add at the top of the new tests, before updating old ones, to confirm the old parser rejects it:

```ocaml
let test_parse_mixed_args () =
  let ast = parse_ok {|push(remote: origin, v)|} in
  match ast.desc with
  | App ({ desc = Var "push"; _ }, [Named { key = "remote"; _ }; Positional { desc = Var "v"; _ }]) -> ()
  | _ -> Alcotest.fail "expected App(Var push, [Named, Positional])"
```

- [ ] **Step 2: Run the new test to confirm it fails**

Run: `dune test 2>&1 | tail -20`
Expected: Many failures due to `Node` patterns no longer existing. The mixed args test may also fail.

- [ ] **Step 3: Update parser test patterns**

Replace all `Ast.Node n` / `Ast.Node _` patterns with the new AST equivalents. The mapping:

| Old pattern | New pattern |
|---|---|
| `Ast.Node { name = "x"; args = []; _ }` or `Ast.Node _` (bare name) | `Ast.Var "x"` or `Ast.Var _` |
| `Ast.Node { name = "x"; args; _ }` (with named args) | `Ast.App ({ desc = Ast.Var "x"; _ }, args)` where args are `Named` |
| `Ast.Node n` then `n.name`, `n.args`, `n.comments` | `Ast.App ({ desc = Ast.Var name; _ }, args)` then destructure `call_arg list` |

Specific test updates (non-exhaustive — every test matching `Node` needs updating):

**`test_parse_node_with_args`**: `Node n` → `App ({ desc = Var "read"; _ }, [Named { key = "source"; _ }])`

**`test_parse_node_no_parens`**: `Node n` → `Var "count"`

**`test_parse_node_empty_parens`**: `Node n` → `App ({ desc = Var "noop"; _ }, [])`

**`test_parse_multiple_args`**: `Node n` → `App ({ desc = Var "load"; _ }, args)` then check `args` is `[Named {key="from";_}; Named {key="key";_}; Named {key="ttl";_}]`

**`test_parse_string_value`** through **`test_parse_number_with_unit`**: `Node n` → `App ({ desc = Var _; _ }, [Named { value; _ }])` then check value.

**`test_parse_seq`** etc.: `Ast.Node _` → `Ast.Var _`

**`test_parse_comments_attach_to_node`**: Comments are now **dropped** (known regression). This test should be updated to verify comments are dropped or removed. Change to verify the parse succeeds and produces the expected `Seq(Var, Var)` structure without checking comments.

**`test_parse_multiline_comments`**: Same — comments dropped. Update to verify parse succeeds.

**`test_parse_comment_on_group`**: Comment attaches via `attach_comments_right` which now drops on Var. Update to verify structure without comment check.

**`test_parse_comment_on_loop`**: Same.

**`test_parse_comment_on_node_question`**: Same.

- [ ] **Step 4: Update printer test expected output**

All printer tests that expected `Node("name", [...], [...])` need updating:

| Old expected | New expected |
|---|---|
| `Node("a", [], [])` | `Var("a")` |
| `Node("a", [x: Ident("csv")], [])` | `App(Var("a"), [Named(x: Ident("csv"))])` |
| `Node("a", [], ["comment"])` | `Var("a")` (comments dropped) |

**`test_print_simple_node`**: `Node("count", [], [])` → `Var("count")`

**`test_print_node_with_args`**: `Node("read", [source: String("data.csv")], [])` → `App(Var("read"), [Named(source: String("data.csv"))])`

**`test_print_node_with_list_arg`**: Similar update with `Named`.

**`test_print_seq`**: `Seq(Node("a", [], []), Node("b", [], []))` → `Seq(Var("a"), Var("b"))`

All similar pattern throughout printer, reducer, and integration tests.

**`test_print_app`**: Currently expects `App(Var("f"), [Node("a", [], [])])`. New: `App(Var("f"), [Positional(Var("a"))])`

**`test_print_let`**: Currently expects `Let("f", Node("a", [], []), Var("f"))`. New: `Let("f", Var("a"), Var("f"))`

**`test_print_comment`**: Comments on bare Var are dropped. Update or remove.

- [ ] **Step 5: Update reducer test expected output**

**`test_reduce_no_lambda`**: `Seq(Node("a", [], []), Node("b", [], []))` → `Seq(Var("a"), Var("b"))`

**`test_reduce_let_simple`** through **`test_reduce_capture_avoiding`**: Same pattern — all `Node("x", [], [])` become `Var("x")`.

**`test_reduce_free_variable`**: Currently tests that `y` in lambda body is parsed as `Node` (out of scope). Now it will be `Var "y"`. Expected: `Var("y")`.

**`test_reduce_non_function_apply`**: `let f = a\nf(b)` — currently `f` is bound to `Node "a"`, applying it fails. Now `f` is bound to `Var "a"`, applying `Var "a"` should still fail since `Var` is not `Lambda`. The error message from reducer: `"expression is not a function and cannot be applied"`. This test may need to check the specific error message if it changed.

Wait — actually: `let f = a` binds `f` to `Var "a"`. Then `f(b)` reduces: desugar → `App(Lambda(["f"], App(Var "f", [Positional(Var "b")])), [Positional(Var "a")])`. Beta-reduce the outer: substitute `f` → `Var "a"` in body → `App(Var "a", [Positional(Var "b")])`. Then beta-reduce the inner App: callee is `Var "a"` which is a free Var → it **survives**. This is different from current behavior where it fails!

This is a behavioral change: **applying a bound variable that resolves to a bare name (free Var) no longer fails**. It produces `App(Var "a", [Positional(Var "b")])` which survives reduction. This matches the spec: free Var callees survive.

Update `test_reduce_non_function_apply`: it should now **succeed**, not fail. Rename to `test_reduce_free_var_apply` and check the output:

```ocaml
let test_reduce_free_var_apply () =
  let ast = reduce_ok "let f = a\nf(b)" in
  Alcotest.(check string) "printed"
    "App(Var(\"a\"), [Positional(Var(\"b\"))])"
    (Printer.to_string ast)
```

Similarly, **`test_reduce_positional_on_undefined`**: `f(a, b)` where `f` is unbound. Now the parser produces `App(Var "f", [Positional(Var "a"); Positional(Var "b")])`. The reducer sees `Var "f"` (free) → survives. This test should now **succeed**. Update:

```ocaml
let test_reduce_positional_on_undefined () =
  let ast = reduce_ok "f(a, b)" in
  Alcotest.(check string) "printed"
    "App(Var(\"f\"), [Positional(Var(\"a\")), Positional(Var(\"b\"))])"
    (Printer.to_string ast)
```

- [ ] **Step 6: Update checker tests**

**`test_check_*`** tests use `check_ok` which runs parse → reduce → check. Since `Node` is gone, the pipeline is `Var`/`App` throughout. Most checker tests should pass without changes (they test question/alt balance on pipelines of bare names, which are now `Var` — checker treats `Var` same as `Node` for balance).

The removed `Node`-specific check (empty name + no comments → error) has no equivalent for `Var` since `Var ""` can't be produced by the parser. Remove any test for that if present.

Update `test_check_string_lit_question_with_alt` if its internal pattern matching references `Node`.

- [ ] **Step 7: Update `test_parse_let_scope`**

This test currently checks that `f` in let body is parsed as `Var "f"` (in scope) vs other names parsed as `Node`. After the change, everything is `Var`/`App` regardless of scope. The test should verify the structure still parses correctly — `f` in body is `Var "f"`, and `a`, `b` are also `Var`.

```ocaml
let test_parse_let_scope () =
  let tokens = Lexer.tokenize "let f = a >>> b\nf" in
  let ast = Parser.parse_program tokens in
  match ast.desc with
  | Let ("f", value, body) ->
    (match value.desc with
     | Seq ({ desc = Var "a"; _ }, { desc = Var "b"; _ }) -> ()
     | _ -> Alcotest.fail "expected Seq(Var a, Var b)");
    (match body.desc with
     | Var "f" -> ()
     | _ -> Alcotest.fail "expected Var f body")
  | _ -> Alcotest.fail "expected Let"
```

- [ ] **Step 8: Update `test_parse_empty_positional_args`**

Currently this tests `let f = \x -> x\nf()` — with scope, parser knew `f` was bound and entered positional mode, then rejected empty positional. Without scope, `f()` produces `App(Var "f", [])`. The reduce step then tries to beta-reduce: `f` → lambda with 1 param, 0 positional args → arity mismatch. So the error moves from parser to reducer.

Update the test to expect a **reducer** error instead of parser error:

```ocaml
let test_empty_application_arity () =
  match reduce_ok "let f = \\ x -> x\nf()" with
  | _ -> Alcotest.fail "expected reduce error (arity mismatch)"
  | exception Reducer.Reduce_error (_, msg) ->
    Alcotest.(check bool) "mentions arity" true (contains msg "arity")
```

- [ ] **Step 9: Verify `test_parse_trailing_comma_positional` still passes**

`let f = \x -> x\nf(a,)` — without scope, the trailing comma rejection is handled by `parse_call_args` (Task 3 already includes the trailing comma check). Verify this test still works — it now expects a parser error from the unified `parse_call_args` rather than the old positional-only path.

- [ ] **Step 10: Add new mixed args tests to test suites**

Add to `parser_tests`:
```ocaml
; "mixed named and positional args", `Quick, test_parse_mixed_args
```

Update renamed/changed tests in their respective suite lists. Remove tests that no longer apply (comment attachment on nodes).

- [ ] **Step 11: Run all tests**

Run: `dune test`
Expected: All tests pass.

- [ ] **Step 12: Commit**

```bash
git add test/test_compose_dsl.ml
git commit -m "test: update all tests for unified Var/App AST"
```

---

### Task 7: Tests — Add new feature tests

**Files:**
- Modify: `test/test_compose_dsl.ml`

Add tests specifically for the new mixed-args capability and free variable behavior.

- [ ] **Step 1: Write mixed args parser tests**

```ocaml
let test_parse_mixed_named_positional () =
  let ast = parse_ok {|push(remote: origin, v)|} in
  match ast.desc with
  | App ({ desc = Var "push"; _ }, [Named { key = "remote"; value = Ident "origin" }; Positional { desc = Var "v"; _ }]) -> ()
  | _ -> Alcotest.fail "expected App(Var push, [Named, Positional])"

let test_parse_positional_then_named () =
  let ast = parse_ok {|deploy(stage, env: production)|} in
  match ast.desc with
  | App ({ desc = Var "deploy"; _ }, [Positional { desc = Var "stage"; _ }; Named { key = "env"; value = Ident "production" }]) -> ()
  | _ -> Alcotest.fail "expected App with positional then named"

let test_parse_multiple_positional () =
  let ast = parse_ok {|f(a >>> b, c)|} in
  match ast.desc with
  | App ({ desc = Var "f"; _ }, [Positional { desc = Seq _; _ }; Positional { desc = Var "c"; _ }]) -> ()
  | _ -> Alcotest.fail "expected App with two positional args"

let test_parse_app_question () =
  let ast = parse_ok {|check(strict: true)?|} in
  match ast.desc with
  | Question { desc = App ({ desc = Var "check"; _ }, [Named _]); _ } -> ()
  | _ -> Alcotest.fail "expected Question(App(...))"

let test_parse_var_question () =
  let ast = parse_ok {|ready?|} in
  match ast.desc with
  | Question { desc = Var "ready"; _ } -> ()
  | _ -> Alcotest.fail "expected Question(Var)"

let test_parse_empty_parens () =
  match desc_of "noop()" with
  | App ({ desc = Var "noop"; _ }, []) -> ()
  | _ -> Alcotest.fail "expected App(Var noop, [])"
```

- [ ] **Step 2: Write mixed args reducer tests**

```ocaml
let test_reduce_mixed_args () =
  let ast = reduce_ok "let v = a >>> b\npush(remote: origin, v)" in
  Alcotest.(check string) "printed"
    {|App(Var("push"), [Named(remote: Ident("origin")), Positional(Seq(Var("a"), Var("b")))])|}
    (Printer.to_string ast)

let test_reduce_named_args_on_lambda_error () =
  reduce_fails "let f = \\ x -> x\nf(key: val)"

let test_reduce_free_var_with_named () =
  let ast = reduce_ok {|push(remote: origin)|} in
  Alcotest.(check string) "printed"
    {|App(Var("push"), [Named(remote: Ident("origin"))])|}
    (Printer.to_string ast)

let test_reduce_free_var_bare () =
  let ast = reduce_ok "a >>> b" in
  Alcotest.(check string) "printed"
    {|Seq(Var("a"), Var("b"))|}
    (Printer.to_string ast)
```

- [ ] **Step 3: Write mixed args checker tests**

```ocaml
let test_check_mixed_args_no_error () =
  let _ = check_ok "let v = a >>> b\npush(remote: origin, v)" in
  ()

let test_check_question_in_positional_arg () =
  (* Question inside positional arg should not leak to outer scope *)
  let warnings = check_ok_with_warnings "push(remote: origin, inner?)" in
  Alcotest.(check int) "1 warning from isolated arg" 1 (List.length warnings)

let test_check_app_question_with_alt () =
  let _ = check_ok "check(strict: true)? >>> (pass ||| fail)" in
  ()
```

- [ ] **Step 4: Write integration test for issue #21**

```ocaml
let test_integration_mixed_args () =
  let input = "let v = some_pipeline\npush(remote: origin, v)" in
  let tokens = Lexer.tokenize input in
  let ast = Parser.parse_program tokens in
  let reduced = Reducer.reduce ast in
  let result = Checker.check reduced in
  Alcotest.(check int) "no errors" 0 (List.length result.Checker.errors)
```

- [ ] **Step 5: Add new tests to suite lists**

Add to `parser_tests`, `reducer_tests`, `checker_tests`, `integration_tests` as appropriate.

- [ ] **Step 6: Run all tests**

Run: `dune test`
Expected: All tests pass, including new mixed args tests.

- [ ] **Step 7: Commit**

```bash
git add test/test_compose_dsl.ml
git commit -m "test: add mixed named/positional args tests for issue #21"
```

---

### Task 8: Documentation — Update README and CLAUDE.md

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update README.md EBNF grammar**

Replace the `term`, `node`, `call_args`, `named_args`, `positional_args` rules (lines 35-54) with:

```ebnf
term     = ident , [ "(" , [ call_args ] , ")" ] , [ "?" ]
                                                    (* ident with optional args and question *)
         | string , [ "?" ]                        (* string literal, optionally question;
                                                      AST represents both as Question(expr) *)
         | "loop" , "(" , seq_expr , ")"            (* feedback loop *)
         | "(" , seq_expr , ")"                    (* grouping *)
         | lambda
         ;

call_args = call_arg , { "," , call_arg } ;
call_arg  = ident , ":" , value                    (* Named — per-arg disambiguation via IDENT ":" *)
          | seq_expr                                (* Positional — any expression *)
          ;
```

Remove the `node`, `named_args`, `positional_args` rules entirely. Keep `arg` and `value` rules unchanged (they're still used by `Named` call_arg).

- [ ] **Step 2: Add a mixed args example to README.md**

After the existing lambda/let examples (around line 190), add:

```
```
let v = some_pipeline
push(remote: origin, v)
```

Named and positional arguments can be freely mixed. Named arguments (`key: value`) provide static configuration; positional arguments pass pipeline expressions.
```

- [ ] **Step 3: Update README.md prose**

Update the description after the EBNF (around line 84) to replace mentions of "node" with the new model. The key sentence change:

Old: "All operators are right-associative (matching Haskell Arrow fixity). Comments can appear after any term and are attached to the preceding node as purpose descriptions or reference tool annotations."

New: "All operators are right-associative (matching Haskell Arrow fixity)."

(Remove the comment attachment sentence since comments are no longer attached to nodes.)

- [ ] **Step 4: Update CLAUDE.md Ast description**

Update the `Ast` bullet point (around line 35) to reflect the new types:

Old: `Node, StringLit (string literal as expression), Seq (>>>), Par (***), Fanout (&&&), Alt (|||), Loop, Group, Question (?), Lambda (\x -> body), Var (variable reference), App (positional application), Let (let x = expr). Lambda, Var, App, and Let are reduced away by the Reducer before structural checking.`

New: `Var (variable reference, bound or free), StringLit (string literal as expression), Seq (>>>), Par (***), Fanout (&&&), Alt (|||), Loop, Group, Question (?), Lambda (\x -> body), App (unified application with call_arg list — mixed named/positional), Let (let x = expr). Lambda and Let are reduced away by the Reducer. Free Var and App with free Var callee survive reduction.`

Update the `Question` note: "Question takes an `expr` directly (parser allows Var, StringLit, or App)."

Update the `Reducer` bullet: mention that free Var and unbound App survive reduction.

Update the `Checker` bullet: mention isolated positional arg sub-expression checking.

Remove mentions of `Node` and `node` type. Remove "No unit value" note about `f()` being a parse error (it's now valid — `App(Var "f", [])`).

- [ ] **Step 5: Run tests to confirm nothing broke**

Run: `dune test`
Expected: All pass (docs changes don't affect tests, but good hygiene).

- [ ] **Step 6: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: update EBNF and docs for unified Var/App model"
```

---

### Task 9: Final Validation

- [ ] **Step 1: Run full test suite**

Run: `dune test`
Expected: All tests pass.

- [ ] **Step 2: Test the CLI with mixed args**

Run:
```bash
echo 'let v = a >>> b
push(remote: origin, v)' | dune exec ocaml-compose-dsl
```
Expected: Clean output like `App(Var("push"), [Named(remote: Ident("origin")), Positional(Seq(Var("a"), Var("b")))])`, exit 0.

- [ ] **Step 3: Test backwards compatibility**

Run:
```bash
echo 'a >>> b *** c' | dune exec ocaml-compose-dsl
echo 'read(source: "data.csv") >>> filter(condition: "age > 18")' | dune exec ocaml-compose-dsl
echo '"earth is not flat"? >>> (believe ||| doubt)' | dune exec ocaml-compose-dsl
echo 'let f = \x -> x >>> done
f(step)' | dune exec ocaml-compose-dsl
```
Expected: All produce valid output, exit 0.

- [ ] **Step 4: Test empty parens**

Run:
```bash
echo 'noop()' | dune exec ocaml-compose-dsl
```
Expected: `App(Var("noop"), [])`, exit 0.

- [ ] **Step 5: Mark plan complete**

```bash
git log --oneline -10
```
Verify all commits are present and the implementation is complete.
