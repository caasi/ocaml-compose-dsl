# Add `&&&` (Fanout) Operator and Formalize Arrow Semantics

**Date:** 2026-03-19
**Status:** Draft

## Motivation

The DSL uses Arrow combinators (`>>>`, `***`, `|||`, `loop`) to describe AI agent workflows. When stress-tested against real subagent composition patterns, the existing syntax is expressive enough — but two things are missing:

1. **`&&&` (fanout)** — duplicate a single input to two arrows: `f &&& g : a → (b, c)`. Distinct from `***` which splits a tuple. Real use case: run lint and test on the same code simultaneously.
2. **Formal Arrow semantics** — the DSL implicitly follows Arrow types (tuples for `***`, Either for `|||`) but this isn't documented. Agents and humans need to know the data flow rules.

The DSL intentionally has no interpreter, no type checker, and no `fmap`/`>>=`. It's structured CoT for agents. Arrow semantics describe the data flow; the agent decides the concrete types.

## Changes

### 1. EBNF: Operator Precedence

**Before** (all operators same precedence):

```ebnf
expr     = term , { operator , term } ;
operator = ">>>" | "***" | "|||" ;
```

**After** (3 levels, lowest to highest):

```ebnf
pipeline = seq_expr ;

seq_expr = alt_expr , { ">>>" , alt_expr } ;
alt_expr = par_expr , { "|||" , par_expr } ;
par_expr = term ,     { ( "***" | "&&&" ) , term } ;

term     = node
         | "loop" , "(" , seq_expr , ")"
         | "(" , seq_expr , ")"
         ;

(* remaining rules unchanged *)
node     = ident , [ "(" , [ args ] , ")" ] ;
args     = arg , { "," , arg } ;
arg      = ident , ":" , value ;
value    = string | ident | "[" , [ value , { "," , value } ] , "]" ;
ident    = ( letter | "_" ) , { letter | digit | "-" | "_" } ;
string   = '"' , { any char - '"' } , '"' ;
comment  = "--" , { any char - newline } ;
```

All operators are right-associative (matching Haskell's `infixr`). Precedence from lowest to highest: `>>>` (1) < `|||` (2) < `***`/`&&&` (3). Groups and loop bodies return to the lowest precedence level (`seq_expr`).

`a >>> b &&& c >>> d` parses as `a >>> ((b &&& c) >>> d)`.

### 2. AST

Add one variant:

```ocaml
type expr =
  | Node of node
  | Seq of expr * expr
  | Par of expr * expr
  | Fanout of expr * expr    (* &&& *)
  | Alt of expr * expr
  | Loop of expr
  | Group of expr
```

### 3. Lexer

Add `Ampersand3` token for `&&&`. Same triple-character peek pattern as `Seq3` (`>>>`), `Star3` (`***`), `Pipe3` (`|||`).

Partial `&` or `&&` raises `Lex_error` (same as partial `>`, `*`, `|` today).

### 4. Parser

Replace single `parse_expr` + `parse_binop` with 3 precedence levels:

- `parse_seq_expr` — consumes `>>>`, calls `parse_alt_expr`
- `parse_alt_expr` — consumes `|||`, calls `parse_par_expr`
- `parse_par_expr` — consumes `***` and `&&&`, calls `parse_term`

Each level is right-associative (parse the right side recursively). `parse_term` unchanged.

### 5. Checker

No new constraints. `&&&` has no structural constraints (unlike `loop` which requires an eval node).

`Fanout` must be added to all pattern matches in `checker.ml` — both the outer `go` traversal and the inner `scan` function inside the `Loop` case — to avoid incomplete match warnings and ensure `Fanout` nodes inside loop bodies are scanned for eval nodes.

### 6. README: Arrow Semantics Section

Add between Grammar and Example:

```markdown
## Arrow Semantics

The operators follow Arrow combinator semantics. The DSL has no type checker —
these types describe the data flow for the agent (and human) reading the pipeline.

| Operator | Name     | Type                                          |
|----------|----------|-----------------------------------------------|
| `>>>`    | compose  | `Arrow a b → Arrow b c → Arrow a c`           |
| `***`    | product  | `Arrow a b → Arrow c d → Arrow (a,c) (b,d)`   |
| `&&&`    | fanout   | `Arrow a b → Arrow a c → Arrow a (b,c)`       |
| `\|\|\|` | fanin / branch | `Arrow a c → Arrow b c → Arrow (Either a b) c` |
| `loop`   | feedback | `Arrow (a,s) (b,s) → Arrow a b`               |

`***` is right-associative: `a *** b *** c` types as `(A, (B,C))`.
Comments can annotate the concrete types when the structure isn't obvious from node names.
```

### 7. Example `.arr` Files

Three files in `examples/` demonstrating real subagent workflows:

**`examples/brainstorming.arr`**

```
-- explore_context : () → (SourceCode, (History, Docs))
-- summarize       : (SourceCode, (History, Docs)) → Context
-- ask_questions   : Context → Requirements
-- propose         : Requirements → Design

(read_files(glob: "lib/**/*.ml") *** git_log(n: "20") *** read_docs(path: "CLAUDE.md"))
  >>> summarize
  >>> ask_questions(style: one_at_a_time)
  >>> propose(count: "3")
  >>> present_design
  >>> write_spec
```

**`examples/tdd-loop.arr`**

```
-- write_test : Feature → (Code, TestSuite)
-- implement  : (Code, ErrorContext) → (Code, ErrorContext)
-- run_tests  : Code → Either PassResult FailResult
-- evaluate   : Either PassResult FailResult → (Result, ErrorContext)

write_test(for: feature)
  >>> loop(
    implement
      >>> run_tests
      >>> evaluate(criteria: all_pass)
  )
  >>> commit
```

**`examples/release.arr`**

```
-- lint      : Code → LintReport
-- test      : Code → TestReport
-- gate      : (LintReport, TestReport) → (Code, Code)
-- build_*   : Code → Binary
-- upload    : (Binary, Binary) → Release

(lint &&& test)
  >>> gate(require: [pass, pass])
  >>> (build_linux(profile: static) *** build_macos(profile: release))
  >>> upload_release(tag: "v0.1.0")
```

## What This Does NOT Add

- **No `fmap` / `arr`** — every node is already an opaque arrow. Agent infers transformations from names + args.
- **No `>>=`** — would make pipeline structure depend on runtime values, destroying static visibility.
- **No `first` / `second`** — describable via comments when needed. Keep syntax minimal.
- **No type checker** — types in comments are advisory, for agents and humans.

## Testing

New tests needed:

- **Lexer:**
  - `&&&` token recognition
  - Partial `&` and `&&` raise `Lex_error`
- **Parser:**
  - `a &&& b` → `Fanout(Node a, Node b)`
  - Precedence: `a >>> b &&& c >>> d` → `Seq(Node a, Seq(Fanout(Node b, Node c), Node d))` (right-assoc)
  - Precedence: `a ||| b *** c` → `Alt(Node a, Par(Node b, Node c))`
  - Mixed `***` and `&&&`: `a *** b &&& c` → `Par(Node a, Fanout(Node b, Node c))` (right-associative, same precedence)
  - Mixed all: `a >>> b ||| c &&& d *** e` → `Seq(Node a, Alt(Node b, Par(Fanout(Node c, Node d), Node e)))` (precedence: `>>>` < `|||` < `***`/`&&&`, all right-assoc)
  - Groups override precedence: `(a >>> b) &&& c` → `Fanout(Group(Seq(Node a, Node b)), Node c)`
  - Right-assoc: `a >>> b >>> c` → `Seq(Node a, Seq(Node b, Node c))`
- **Breaking change for existing tests:**
  - Associativity change: `a >>> b >>> c` was `Seq(Seq(a,b),c)`, now `Seq(a,Seq(b,c))`
  - Precedence change: `a >>> b *** c ||| d` was `Alt(Par(Seq(a,b),c),d)` (left-to-right, same precedence), now `Seq(a, Alt(Par(b,c), d))` (precedence + right-assoc)
  - Existing tests using chained or mixed operators must be updated
