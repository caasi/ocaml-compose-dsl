# Optional Type Annotations

**Date:** 2026-03-23
**Status:** Draft

## Problem

The Arrow DSL can describe workflow composition (`>>>`, `***`, `&&&`, `|||`, `loop`, `?`) but cannot describe what kind of data flows between nodes. When used in literate documents (e.g., CLAUDE.md), this means the DSL can express **how** things connect but not **what** they carry. Readers — both LLMs and humans — must infer data types from node names and context alone.

## Decision

Add optional type annotations to nodes and terms. Type annotations are parsed into the AST but **not checked** — they are erased by the checker, serving purely as structured documentation for readers. This follows the project's established principle that semantic judgments belong to the expanding agent, not the DSL checker (see: remove-loop-eval-check).

## Design

### Syntax

A type annotation is `:: Ident -> Ident` appearing after a term:

```ebnf
typed_term = term , [ "::" , type_expr ] ;
type_expr  = ident , "->" , ident ;
```

`::` is a new two-character token (following Haskell's convention for type signatures). `->` is also a new two-character token. Type identifiers reuse the existing `ident` rule — any valid identifier (including Unicode) is a valid type name.

Examples:

```
fetch(url: "https://example.com") :: URL -> HTML
  >>> parse :: HTML -> Data
  >>> filter(condition: "age > 18") :: Data -> Data
  >>> format(as: report) :: Data -> Report
```

Type annotations are optional. A pipeline can freely mix annotated and unannotated nodes:

```
fetch(url: "https://example.com") :: URL -> HTML
  >>> parse
  >>> format(as: report) :: Data -> Report
```

### Where annotations can appear

On any term — nodes, groups, loops, and questions:

```
node :: A -> B
node(key: value) :: A -> B
(a >>> b) :: A -> C
loop(body) :: A -> B
"question"? :: A -> Either
```

### EBNF changes

```ebnf
(* Replace term usage in par_expr with typed_term *)
par_expr    = typed_term , ( "***" | "&&&" ) , par_expr
            | typed_term ;

typed_term  = term , [ "::" , type_expr ] ;

type_expr   = ident , "->" , ident ;
```

`seq_expr` and `alt_expr` continue to reference their lower-precedence counterpart, so `typed_term` only needs to replace `term` in `par_expr`. `::` binds tighter than any operator — `a :: X -> Y >>> b` parses as `(a :: X -> Y) >>> b`.

### No ambiguity with existing `:`

`::` is a distinct token from `:`. The existing `:` appears only inside `( args )` as part of `key: value`. The type annotation uses `::` which is lexically unambiguous — no context-dependent disambiguation needed.

### Type expressiveness

Type annotations only support `Ident -> Ident` — no tuple types, no `Either`, no parameterized types. This is deliberate: the Arrow semantics table already documents that `***` produces `(A, (B, C))` and `|||` consumes `Either A B`. These structural types are implicit in the operators. The type annotation captures the **semantic** meaning (`Code -> Branch`), not the structural Arrow type. LLMs and humans reading `branch :: Code -> Branch` understand what flows without needing `:: Code -> (Branch, State)`.

If compound types prove necessary in practice, `type_expr` can be extended later without breaking existing annotations.

### AST changes

```ocaml
(* Add to ast.ml *)
type type_ann = { input : string; output : string }

(* Extend expr *)
type expr = { loc : loc; desc : expr_desc; type_ann : type_ann option }
```

Every `expr` gains an optional `type_ann` field. Nodes without annotations have `type_ann = None`.

### Implementation impact of AST change

Adding `type_ann` to `expr` is a breaking structural change. All code that constructs `expr` values must be updated:

**`parser.ml`:**
- `mk_expr` (line 14): change signature to `let mk_expr loc desc : expr = { loc; desc; type_ann = None }` — all existing call sites remain valid, producing unannotated exprs by default.
- `parse_par_expr` is the only place that may produce `type_ann = Some _` (see Parser changes below).
- `attach_comments_right` uses `{ e with desc = ... }` which preserves `type_ann` — no change needed.

**`checker.ml`:**
- `normalize` uses `{ e with desc = ... }` — preserves `type_ann`. When stripping `Group`, the inner expr's `type_ann` is kept. The outer `Group`'s `type_ann` is discarded, which is correct: if both the group and its contents have annotations, the inner one is more specific.
- `check` pattern-matches on `e.desc` — `type_ann` is not examined. No changes needed.

**`printer.ml`:**
- `to_string` needs to append type annotation output (see Printer changes).

### New tokens

```ocaml
(* Add to lexer token type *)
| DOUBLE_COLON  (** [::] *)
| ARROW         (** [->] *)
```

Two new two-character tokens:

**`::` (DOUBLE_COLON):** The lexer currently emits single `COLON` for `:`. Add a check: if the current char is `:` and the next char is also `:`, emit `DOUBLE_COLON` instead. Single `:` continues to emit `COLON` for arg syntax.

**`->` (ARROW):** Does not conflict with existing tokens:

- `--` (comment) is already handled — the lexer checks for `--` before falling through to `-`
- `-` followed by digit is a negative number — the lexer checks `peek_byte()` for digit before this
- `-` followed by `>` is currently a lex error, so `->` occupies unused syntax space

### Lexer changes

In the `':'` match arm, check for `::`:

```ocaml
| ':' ->
  if peek_byte () = Some ':' then begin
    advance (); advance ();
    tokens := { token = DOUBLE_COLON; loc = { start = p; end_ = pos () } } :: !tokens
  end else begin
    advance ();
    tokens := { token = COLON; loc = { start = p; end_ = pos () } } :: !tokens
  end
```

In the `'-'` match arm, after checking for `--` (comment) and `-digit` (negative number), add before the wildcard `_` arm:

```ocaml
| Some '>' ->
  advance (); advance ();
  tokens := { token = ARROW; loc = { start = p; end_ = pos () } } :: !tokens
```

The full `'-'` arm ordering becomes: `--` (comment) → `-digit` (negative number) → `->` (arrow) → error.

### Parser changes

Add `parse_type_ann` that optionally consumes `:: Ident -> Ident`:

```ocaml
let parse_type_ann st =
  let t = current st in
  match t.token with
  | Lexer.DOUBLE_COLON ->
    advance st;
    let t_in = current st in
    (match t_in.token with
     | Lexer.IDENT input ->
       advance st;
       expect st (fun tok -> tok = Lexer.ARROW) "expected '->' in type annotation";
       let t_out = current st in
       (match t_out.token with
        | Lexer.IDENT output ->
          advance st;
          Some { input; output }
        | _ -> raise (Parse_error (t_out.loc.start, "expected type name after '->'")))
     | _ -> raise (Parse_error (t_in.loc.start, "expected type name after '::'")))
  | _ -> None
```

Integration in `parse_par_expr` — call `parse_type_ann` after `parse_term`, before `eat_comments`. This means `node :: A -> B -- comment` attaches the comment to the node (via `eat_comments` → `attach_comments_right`), and `node -- comment :: A -> B` eats the comment first (inside `parse_term`), then parses the type annotation:

```ocaml
and parse_par_expr st =
  let lhs = parse_term st in
  let type_ann = parse_type_ann st in
  let lhs = match type_ann with
    | None -> lhs
    | Some _ -> { lhs with type_ann; loc = { lhs.loc with end_ = st.last_loc.end_ } }
  in
  let comments = eat_comments st in
  let lhs = attach_comments_right lhs comments in
  (* ... rest unchanged ... *)
```

When `type_ann` is present, the expr's `loc.end_` extends to cover the output type identifier, so error reporting and source mapping include the full annotation span.

### Checker changes

None. The checker ignores `type_ann` entirely. No type consistency checking is performed. This is deliberate — type annotations are documentation for the expanding agent and human readers, not constraints for the checker to enforce.

### Printer changes

Extend `to_string` to include type annotations in output:

```ocaml
let type_ann_to_string = function
  | None -> ""
  | Some { input; output } -> Printf.sprintf " :: %s -> %s" input output
```

Append after each expr's constructor output.

### CLI output

Type annotations appear in the OCaml constructor format output, allowing downstream tools to extract them:

```
$ echo 'fetch :: URL -> HTML >>> parse :: HTML -> Data' | ocaml-compose-dsl
Seq(Node("fetch", [], []) :: URL -> HTML, Node("parse", [], []) :: HTML -> Data)
```

## Literate Arrow Documents (Convention)

This section defines a usage convention, not a code change. No implementation is needed — it documents how type-annotated Arrow DSL is intended to be used in practice.

Type annotations are designed to work within literate documents — files where natural language prose and Arrow DSL code blocks coexist. The convention:

### Format

Use fenced code blocks with the `arrow` language tag:

````markdown
## Git Workflow

Planning (specs, plans, docs) can go directly to main.
Implementation must go through a feature branch.

```arrow
planning :: Doc -> Commit
  >>> commit(branch: main)

implementation :: Code -> Commit
  >>> branch(pattern: "feature/*") :: Code -> Branch
  >>> commit :: Branch -> Commit
```
````

### Principles

- **Natural language** describes constraints, rationale, and context (why, when, who)
- **Arrow DSL** describes workflows and data flow (what, how)
- **Type annotations** bridge the two — structured enough to be precise, semantic enough to be read as natural language (`Doc -> Commit` reads as "takes a document, produces a commit"). Uses `::` following Haskell's convention for type signatures
- Constraints like "must", "never", "may" stay in natural language — the DSL does not attempt to formalize modality

### File extension

`.arrow.md` for literate arrow documents (convention, not enforced). Plain `.arr` for standalone Arrow DSL files.

## README.md updates

Add a section after the existing examples documenting:

1. Type annotation syntax and examples
2. The literate document convention (`.arrow.md`, `arrow` code blocks)
3. That type annotations are documentation, not enforcement

## Non-changes

- No type checking or type inference
- No generic types, no type parameters, no tuple types, no Either types
- No changes to comment syntax or semantics
- No new checker errors or warnings related to types
- All existing syntax and tests remain valid (`type_ann = None` for all existing exprs)

## References

- **Gradual Typing** (Siek & Taha, 2006) — optional type annotations that can be added incrementally
- **GOSPEL** (Charguéraud et al., FM 2019) — tool-agnostic specification annotations in OCaml
- **Lightweight Formal Methods** (Jackson, 2002) — partial specification is better than no specification
- **`constrained-categories`** (Haskell) — Arrow/Category with per-morphism type constraints
- **Literate Programming** (Knuth, 1984) — prose and code as a unified document
