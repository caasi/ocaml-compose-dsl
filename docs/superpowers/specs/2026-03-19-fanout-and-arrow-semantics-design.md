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
```

All operators are left-associative. `***` and `&&&` share the highest precedence (matching Haskell's Arrow instances). Groups and loop bodies return to the lowest precedence level (`seq_expr`).

`a >>> b &&& c >>> d` parses as `a >>> (b &&& c) >>> d`.

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

### 4. Parser

Replace single `parse_expr` + `parse_binop` with 3 precedence levels:

- `parse_seq_expr` — consumes `>>>`, calls `parse_alt_expr`
- `parse_alt_expr` — consumes `|||`, calls `parse_par_expr`
- `parse_par_expr` — consumes `***` and `&&&`, calls `parse_term`

Each level is a left-associative while loop. `parse_term` unchanged.

### 5. Checker

No changes. `&&&` has no structural constraints (unlike `loop` which requires an eval node).

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
| `\|\|\|` | fanin   | `Arrow a c → Arrow b c → Arrow (Either a b) c` |
| `loop`   | feedback | `Arrow (a,s) (b,s) → Arrow a b`               |

`***` is left-associative: `a *** b *** c` types as `((A,B), C)`.
Comments can annotate the concrete types when the structure isn't obvious from node names.
```

### 7. Example `.arr` Files

Three files in `examples/` demonstrating real subagent workflows:

**`examples/brainstorming.arr`** — parallel research → sequential design process. Shows `***` producing nested tuples from 3-way parallel, comments as type annotations.

**`examples/tdd-loop.arr`** — TDD cycle with `loop` feedback. Shows `|||` as Either (pass/fail branching), loop-carried error context.

**`examples/release.arr`** — CI/CD pipeline. Shows `&&&` (same code → lint + test) vs `***` (separate binaries → separate builds). Demonstrates when to use each.

## What This Does NOT Add

- **No `fmap` / `arr`** — every node is already an opaque arrow. Agent infers transformations from names + args.
- **No `>>=`** — would make pipeline structure depend on runtime values, destroying static visibility.
- **No `first` / `second`** — describable via comments when needed. Keep syntax minimal.
- **No type checker** — types in comments are advisory, for agents and humans.

## Testing

New tests needed:

- **Lexer:** `&&&` token recognition
- **Parser:**
  - `a &&& b` → `Fanout(Node a, Node b)`
  - Precedence: `a >>> b &&& c >>> d` → `Seq(Seq(Node a, Fanout(Node b, Node c)), Node d)`
  - Precedence: `a ||| b *** c` → `Alt(Node a, Par(Node b, Node c))`
  - Mixed: `a >>> b ||| c &&& d *** e`
  - Groups override precedence: `(a >>> b) &&& c`
- **Existing tests:** must still pass (behavior change for mixed operators — tests that relied on same-precedence parsing may need updating)
