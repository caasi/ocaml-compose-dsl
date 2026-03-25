# Lambda and Let Binding

**Date:** 2026-03-26
**Status:** Draft

## Problem

Real-world Arrow DSL pipelines (e.g., `frontend-project.arr` — a 200-line frontend project workflow) suffer from three readability problems:

1. **No modularization** — All phases are chained in a single monolithic `>>>` pipeline with deep nesting, making navigation impossible.
2. **Repeated patterns** — The same `loop(trigger? >>> (pass ||| fix))` review/approval pattern appears 6+ times with minor variations, each written out in full.
3. **Long parallel chains** — 7-8 `&&&` operations chained together (e.g., design system components, pages, interaction states) create visual noise.

Lambda and let bindings solve problems 1 and 2 directly. Problem 3 is partially addressed (shorter lines via abstraction) but may benefit from additional syntax sugar in a future spec.

## Decision

Extend the DSL with lambda calculus as the foundation for abstraction. All new features are syntactic sugar that desugar to the existing Arrow combinator AST via beta reduction. The DSL remains a structural checker with no runtime.

Design principles:
- **Lambda calculus is the base** — `\x -> expr`, application, and variables are the core abstraction mechanism
- **`let` is sugar** — `let x = e` is sugar for `(\x -> rest) e`, standard lambda calculus let-binding
- **Arrow combinators sit on top** — `>>>`, `&&&`, `***`, `|||`, `loop`, `?` operate on expressions that may contain lambda terms
- **Opt-in** — Files without lambda/let are parsed exactly as before; full backward compatibility

## Design

### Syntax

#### Lambda

```ebnf
lambda = "\" , ident , { "," , ident } , "->" , seq_expr ;
```

`\` is a new single-character token. Multi-parameter lambdas desugar to curried form: `\a, b -> expr` is `\a -> \b -> expr`.

Lambda appears as a new `term` alternative:

```ebnf
term = node
     | "loop" , "(" , seq_expr , ")"
     | "(" , seq_expr , ")"
     | question_term
     | lambda
     ;
```

#### Application (positional args)

The existing `node` rule is extended to support positional arguments alongside named arguments:

```ebnf
node      = ident , [ "(" , [ call_args ] , ")" ] ;

call_args = named_args | positional_args ;

named_args      = arg , { "," , arg } ;            (* existing: key: value *)
positional_args = seq_expr , { "," , seq_expr } ;  (* new: lambda application *)

arg = ident , ":" , value ;
```

**Disambiguation:** After `(`, the parser peeks at the first two tokens. If they are `IDENT COLON`, it parses named args. Any other token sequence (including `IDENT RPAREN`, `IDENT ARROW`, `BACKSLASH`, etc.) triggers positional arg parsing. Named and positional args cannot be mixed in a single call.

**Backward compatibility note:** Currently `f(g)` is a parse error (the parser expects `ident: value`). With this change, `f(g)` becomes a valid application of `f` to the variable or node `g`. This is not a breaking change in practice — no valid existing pipeline produces `f(bare_ident)` without a colon. `f()` (empty parens) continues to produce `Node { name = "f"; args = [] }` since there are no args to disambiguate.

#### Let binding

```ebnf
program     = { let_binding } , seq_expr ;
let_binding = "let" , ident , "=" , seq_expr ;
```

`let` is syntactic sugar. `let x = e1` followed by `body` desugars to `(\x -> body) e1`. Multiple let bindings desugar to nested applications:

```
let a = e1
let b = e2
body

-- desugars to:
(\a -> (\b -> body) e2) e1
```

Note: each `let` binding is in scope for all subsequent bindings and the body. `let b = f(a)` is valid when `a` is defined by an earlier `let`. This follows from the desugaring — `e2` appears inside `\a -> ...`, so `a` is bound.

The parser constructs nested `Let` nodes from the `{ let_binding }` sequence: `Let("a", e1, Let("b", e2, body))`.

### New tokens

| Token | Lexeme | Notes |
|-------|--------|-------|
| `BACKSLASH` | `\` | Already excluded from ident chars in EBNF |
| `LET` | `let` | New keyword; existing identifiers named `let` would break |
| `EQUALS` | `=` | Already excluded from ident chars |

`->` and `IDENT` tokens already exist. The lexer dispatch in `tokenize` must add a match clause for `'\\'` to emit `BACKSLASH`.

### Token disambiguation: `->` in lambda vs type annotations

`->` appears in two contexts: lambda (`\x -> expr`) and type annotations (`:: A -> B`). These are unambiguous at the parser level:
- Type annotation `->` is only parsed inside `type_expr`, which is only entered after `DOUBLE_COLON`.
- Lambda `->` is only parsed inside `lambda`, which is only entered after `BACKSLASH`.

No lexer-level disambiguation is needed; the parser context determines interpretation.

### AST changes

New AST node types:

```ocaml
type expr_desc =
  | Node of node
  | Seq of expr * expr
  | Par of expr * expr
  | Fanout of expr * expr
  | Alt of expr * expr
  | Loop of expr
  | Group of expr
  | Question of question_term
  | Lambda of string list * expr    (* new: \params -> body *)
  | Var of string                   (* new: variable reference *)
  | App of expr * expr list         (* new: f(arg1, arg2, ...) *)
  | Let of string * expr * expr     (* new: let x = e1 in e2 *)
```

### Identifier resolution: Var vs Node

The parser must decide whether a bare identifier (e.g., `f` in `f >>> g`) is a variable reference (`Var`) or a workflow node (`Node`). This is resolved at **parse time** using scope tracking:

- The parser maintains a set of names currently in scope (from `let` bindings and lambda parameters).
- When parsing a bare identifier `x`:
  - If `x` is in scope → emit `Var(x)`
  - If `x` is not in scope → emit `Node({ name = x; args = []; comments = [] })`
- When parsing `x(...)`:
  - If `x` is in scope and args are positional → emit `App(Var(x), args)`
  - If `x` is in scope and args are named → error: "cannot pass named args to variable"
  - If `x` is not in scope → emit `Node({ name = x; args; comments = [] })` (named args) or `App(Node(x), args)` if positional args on a non-bound name (error at reduce time)

This means variable names shadow node names within their scope. A `let f = ...` makes `f` resolve as `Var` everywhere below that binding, even if `f` was previously used as a node name. This is consistent with standard lexical scoping.

### Let binding scope: top-level only

`let` bindings can only appear at the top level of a program, not inside grouped expressions, loop bodies, or other nested contexts. The grammar enforces this:

```ebnf
program = { let_binding } , seq_expr ;
```

Writing `(let x = e in body)` is a parse error. This keeps the reduction model simple and avoids questions about scope nesting. A future `where` clause (see Future Work) may relax this restriction.

### Evaluation model

A new `reducer.ml` module handles desugaring and reduction, sitting between parsing and checking in the pipeline: `parse >>> reduce >>> check`.

The reducer performs:

1. **Desugar `Let`** — `Let(x, e1, e2)` becomes `App(Lambda([x], e2), [e1])`
2. **Beta reduce** — substitute `App(Lambda(params, body), args)` by replacing `Var(param)` with the corresponding arg expression. Repeat until no more reducible applications exist.
3. **Verify fully reduced** — after reduction, the AST should contain no `Lambda`, `Var`, `App`, or `Let` nodes. If any remain, report an error (e.g., free variable, partial application).

The existing `checker.ml` is unchanged — it runs on the reduced pure Arrow AST.

**Termination guarantee:** The reduction strategy terminates because (1) `let` bindings cannot reference themselves (the parser tracks scope, and a binding's name is not in scope during its own RHS), (2) lambda parameters are only in scope within the lambda body (no self-application), and (3) each beta reduction step strictly decreases the number of `App` nodes wrapping `Lambda` nodes.

### Printer changes

The Printer module must handle all new AST node types for diagnostic output (e.g., printing unreduced AST in error messages):

| Node | Printer output |
|------|---------------|
| `Lambda(["x"; "y"], body)` | `Lambda(x, y, <body>)` |
| `Var("x")` | `Var(x)` |
| `App(f, [a; b])` | `App(<f>, <a>, <b>)` |
| `Let("x", e1, e2)` | `Let(x, <e1>, <e2>)` |

In normal operation (successful reduction), these nodes never appear in the final output — the printer only sees pure Arrow AST. But they are needed for debugging and error reporting.

### Error reporting

| Condition | Error message |
|-----------|---------------|
| Free variable | `Undefined variable 'x' at line N, col M` |
| Arity mismatch | `'f' expects N arguments but got M at line N, col M` |
| Unreduced lambda | `Lambda expression not fully applied at line N, col M` |
| Application of non-function | `'f' is not a function and cannot be applied at line N, col M` |
| `let` shadows | Warning: `'x' shadows previous binding at line N, col M` |

### Example: rewritten frontend-project.arr

```arrow
-- Reusable review loop pattern
let 審查迴圈 = \trigger, fix_branch ->
  loop(
    trigger
    >>> (通過 ||| fix_branch)
  )

-- Phase definitions
let discovery = (
  Google_Meet(對象: 利害關係人, 目的: 需求訪談) :: 專案 -> 訪談紀錄
  >>> Google_Meet(對象: 使用者, 目的: 痛點訪談)
  >>> Notion(文件: 會議紀錄)
  >>> 審查迴圈(
    Google_Meet(目的: 內部審查會議) >>> 內部審查?,
    Claude(任務: 修正需求規格書) >>> Notion(文件: 需求規格書更新)
  )
  >>> 審查迴圈(
    DocuSign(對象: 客戶, 文件: 需求規格書)?,
    Claude(任務: 依客戶意見修正) >>> Notion(文件: 需求規格書更新)
  )
)

let design = (...)
let handoff = (...)
let implementation = (...)
let delivery = (...)

-- Main pipeline: clear, navigable
discovery >>> design >>> handoff >>> implementation >>> delivery
```

**Before:** ~200 lines, single monolithic pipeline, 6 duplicated review loops.
**After:** ~5-line main pipeline, each phase self-contained, review pattern defined once.

## Scope and limitations

- **No recursion** — `let` bindings cannot reference themselves or later bindings. This keeps reduction trivially terminating.
- **No higher-order passing** — Lambdas must be fully applied. You cannot pass a lambda as a named arg value (named args take `value`, not `seq_expr`). Lambdas can only be applied via positional args.
- **No polymorphism** — No type variables, no generics. Type annotations remain documentation-only.
- **`let` is reserved** — Existing pipelines using `let` as a node name will break. This is an acceptable tradeoff given `let` is an extremely common keyword.

## README EBNF update

The README's top-level rule `pipeline = seq_expr` must be updated to reflect the new `program` rule:

```ebnf
program  = { let_binding } , pipeline ;
pipeline = seq_expr ;
```

This preserves `pipeline` as a named rule (useful for documentation) while adding `program` as the new top-level entry point.

## Future work

- **`&&&` list sugar** — A separate syntax for parallel fanout lists (e.g., `[a, b, c]` desugaring to `a &&& b &&& c`) could further reduce visual noise. Deferred to a future spec since lambda already partially addresses the problem.
- **`where` clauses** — `body where { x = e1; y = e2 }` as an alternative to top-level `let` for local definitions. Useful for literate documents where you want to read the main pipeline first.
