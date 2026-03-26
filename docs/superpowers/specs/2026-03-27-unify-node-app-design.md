# Unify Node and App: Mixed Named/Positional Arguments

**Issue:** [#21 — Cannot mix named and positional arguments](https://github.com/caasi/ocaml-compose-dsl/issues/21)

**Status:** Design approved

## Problem

The parser currently uses all-or-nothing disambiguation for call arguments: if `IDENT ":"` is detected, all args must be named; otherwise all args are positional. This makes it impossible to pass a bound variable alongside named arguments:

```
let v = some_pipeline
push(remote: origin, v)   -- parse error
```

## Solution: Unify Node and App

Rather than patching the existing split, remove the `Node` AST variant entirely. All identifiers become `Var`, and all call syntax produces `App` with a unified `call_arg` type that supports mixed named and positional arguments.

## AST Changes

### Remove

```ocaml
(* Delete *)
type node = { name : string; args : arg list; comments : string list }

(* Delete from expr_desc *)
| Node of node
```

### Add/Modify

```ocaml
type call_arg =
  | Named of arg                  (* key: value -- static configuration *)
  | Positional of expr            (* pipeline expression *)

(* Unchanged types *)
type arg = { key : string; value : value }
type value = String of string | Ident of string | Number of string | List of value list

(* Modified expr_desc -- Node removed, App changed *)
type expr_desc =
  | Var of string                 (* variable reference, bound or free *)
  | StringLit of string
  | Seq of expr * expr
  | Par of expr * expr
  | Fanout of expr * expr
  | Alt of expr * expr
  | Loop of expr
  | Group of expr
  | Question of expr              (* ? -- parser allows on Var, StringLit, App *)
  | Lambda of string list * expr
  | App of expr * call_arg list   (* unified application, mixed named/positional *)
  | Let of string * expr * expr
```

### Mapping from old to new

| Old syntax | Old AST | New AST |
|---|---|---|
| `push` | `Node {name="push"; args=[]; comments=[]}` | `Var "push"` |
| `push()` | `Node {name="push"; args=[]; comments=[]}` | `App(Var "push", [])` |
| `push(remote: origin)` | `Node {name="push"; args=[...]; ...}` | `App(Var "push", [Named {key="remote";...}])` |
| `f(x, y)` (f bound) | `App(Var "f", [x; y])` | `App(Var "f", [Positional x; Positional y])` |
| `push(remote: origin, v)` | **parse error** | `App(Var "push", [Named {...}; Positional(Var "v")])` |

## EBNF Grammar Changes

Replace the `node`, `call_args`, `named_args`, `positional_args` rules:

```ebnf
term     = ident , [ "(" , [ call_args ] , ")" ] , [ "?" ]
         | string , [ "?" ]
         | "loop" , "(" , seq_expr , ")"
         | "(" , seq_expr , ")"
         | lambda
         ;

call_args = call_arg , { "," , call_arg } ;
call_arg  = ident , ":" , value           (* Named -- per-arg disambiguation *)
          | seq_expr                       (* Positional *)
          ;
```

The `node` rule is removed. The first alternative in `term` now handles both bare identifiers and identifiers with call arguments.

Disambiguation is per-argument: if `IDENT ":"` is seen at arg position, it is a Named arg. Otherwise the arg is parsed as a Positional `seq_expr`. Named and positional args can appear in any order.

**Important:** Named arg values remain the restricted `value` type (`String | Ident | Number | List`), not `expr`. This restriction is load-bearing for disambiguation: since `value` cannot start with operators or complex expressions, the `IDENT ":"` lookahead unambiguously identifies Named args. Promoting `value` to `expr` would create parsing ambiguity and is not part of this change.

## Parser Changes

### Scope tracking removed

The parser no longer needs scope (`StringSet`) for disambiguation:

- All identifiers produce `Var` regardless of binding status
- Argument mode is determined per-arg by `IDENT ":"` lookahead
- Empty parens `push()` always produce `App(Var, [])`

Scope is removed from the parser state. Lambda/let binding resolution is handled entirely by the reducer.

### parse_term flow

For `IDENT name`:
1. Check next token for `LPAREN`
2. If yes: parse `call_args` (mixed named/positional), expect `RPAREN`, check for `?`
   - Result: `App(Var name, call_args)`, optionally wrapped in `Question`
3. If no: check for `?`
   - Result: `Var name`, optionally wrapped in `Question`

### Question operator

`?` can now follow:
- `Var` -- `push?` -> `Question(Var "push")`
- `StringLit` -- `"text"?` -> `Question(StringLit "text")`
- `App` -- `push(x, y)?` -> `Question(App(Var "push", [...]))`

## Reducer Changes

### Free variables survive reduction

The reducer no longer rejects free (unbound) `Var` or `App` with free callee. After reduction:

- **Bound Var** -- substituted away (unchanged behavior)
- **Free Var** -- survives as-is (was `Reduce_error`, now allowed)
- **App with Lambda callee** -- beta-reduced using Positional args
- **App with free Var callee** -- survives; Positional arg exprs are recursively reduced

### desugar

`desugar` converts `Let(name, value, body)` into `App(Lambda([name], body'), [Positional value'])`. The generated arg is wrapped in `Positional` to match the unified `call_arg` type.

### Beta-reduction rules for App

When `App(callee, args)` and callee reduces to `Lambda(params, body)`:

1. Extract Positional args from `args`
2. If any Named args present -> `Reduce_error` ("cannot pass named args to lambda")
3. Arity check: count of Positional args must equal count of params
4. Substitute params with Positional arg values in body

When `App(callee, args)` and callee is a free Var:

1. Recursively reduce all Positional arg exprs
2. Return `App` as-is (no beta-reduction)

When `App(callee, args)` and callee reduces to anything else (StringLit, Seq, Par, etc.):

- `Reduce_error` -- e.g. `"hello"(x)` -> "string literal cannot be applied", `(a >>> b)(x)` -> "expression is not a function and cannot be applied". Same error behavior as before, minus the `Node` branch which no longer exists.

### verify changes

`verify` distinguishes App by callee type:

- `App(Var _, _)` -> OK (free variable application, survives reduction)
- `App(Lambda _, _)` -> `Reduce_error` (unapplied lambda that should have been reduced -- indicates a bug)
- `App(_, _)` with any other callee -> `Reduce_error` (should have been caught during beta_reduce, but verify catches it as a safety net)

No longer errors on:
- Free `Var` (was: "undefined variable")

Still errors on:
- Unapplied `Lambda` (not inside App)
- Unreduced `Let`

## Checker Changes

### normalize

- `Var _` -> return as-is (leaf)
- `App(callee, args)` -> recursively normalize callee and all Positional arg exprs

### scan_questions

- `Var _` -> `counter` (leaf, no effect on balance)
- `App _` -> `counter` (leaf; positional args are **isolated sub-expressions**, question/alt balance does not leak across application boundaries)
- `Question _` -> `counter + 1` (leaf behavior preserved, does not recurse into inner)

### go (structural checking)

- `Var _` -> no action (leaf)
- `App(callee, args)` -> recursively check callee; **independently** check each Positional arg (each runs its own scan_questions etc.). Named args contain `value`, not `expr`, so no structural checking needed.

## Printer Changes

| AST | Output |
|---|---|
| `Var "push"` | `Var("push")` |
| `App(Var "push", [Named {key="remote"; value=Ident "origin"}])` | `App(Var("push"), [Named(remote: Ident("origin"))])` |
| `App(Var "push", [Named {...}; Positional(Seq(a,b))])` | `App(Var("push"), [Named(remote: Ident("origin")), Positional(Seq(Var("a"), Var("b")))])` |
| `Question(App(Var "f", [...]))` | `Question(App(Var("f"), [...]))` |

## Comments Handling

**Short-term:** `attach_comments_right` drops comments on `Var` and `App`, same as it currently does for `Lambda`/`App`/`Let`. This is a known regression from removing `Node.comments`.

**Long-term:** Address via the "expression-level comments" future idea (add `comments: string list` to `expr`). Out of scope for this change.

## Semantic Notes

- The DSL is a structural description language, not an executable one
- Named args are static configuration (key-value pairs for the agent to interpret)
- Positional args are expressions passed to the step (the agent decides semantics)
- No evaluation order is defined; the checker validates structure without simplification
- Positional args inside App are isolated sub-expressions: their internal question/alt balance does not affect the outer pipeline
