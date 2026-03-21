# Question Operator (`?`) Design Spec

## Motivation

The current DSL has `|||` (Alt) for branching, but there is no way to express **what produces the Either** that `|||` consumes. Conditions are hidden in opaque string arguments (e.g., `filter(condition: "age > 18")`), making branching structure invisible at the pipeline level.

The `?` operator makes Either-production explicit without introducing a condition expression language — the condition content stays as natural language strings or node semantics, which is appropriate for an agent-authored DSL.

## Design Decisions

### Use Case

This DSL is primarily written by AI agents to record and reuse workflows. Humans read but rarely write. Agents don't need DRY abstractions (let binding, recursion, pattern matching) — they can expand pipelines inline. The `?` operator addresses a structural visibility gap, not an expressiveness gap.

### PLT Positioning

The DSL deliberately avoids a full type system — if you want that, use OCaml directly as an eDSL host. However, operators create implicit structural constraints (e.g., `?` implies an Either that should be consumed by `|||`). These are **context-sensitive well-formedness constraints**, enforced via checker warnings rather than type errors. This sits between CFG-level syntax and a full type system.

### Approach Chosen

**Approach B: `?` syntax + well-formedness warnings.** Minimal syntax addition with structural feedback via warnings. No AST-level distinction between loop variants (Approach C was rejected as over-design). Pure syntax without any checker awareness (Approach A) was rejected as too thin.

## Grammar Changes

The `term` rule is extended:

```ebnf
term = node
     | "loop" , "(" , seq_expr , ")"
     | "(" , seq_expr , ")"
     | string , "?"
     | node , "?"
     ;
```

`?` is part of the term syntax, not a standalone postfix operator. It binds tightest — only to the immediately preceding string or node.

Whitespace between the string/node and `?` is irrelevant (consistent with the rest of the DSL).

## AST Changes

A new `question_term` type constrains what `Question` can wrap:

```ocaml
type question_term =
  | QNode of node
  | QString of string

type expr =
  | Node of node
  | Seq of expr * expr
  | Par of expr * expr
  | Fanout of expr * expr
  | Alt of expr * expr
  | Loop of expr
  | Group of expr
  | Question of question_term
```

The OCaml type system enforces that `Question` can only contain a node or a string — not arbitrary expressions.

## Lexer Changes

Add a `Question` token for the `?` character. The `?` character is already excluded from identifier characters in the existing grammar, so there is no ambiguity. The `| '?' ->` match arm must be added before the catch-all error case in the tokenizer.

## Parser Changes

In `parse_term`:

1. If the current token is a `STRING`, peek the next token. If it is `QUESTION`, consume both and return `Question (QString s)`. If not, raise a parse error: `"bare string is not a valid term; did you mean to add '?'?"`.
2. After parsing a node, peek for `?`. If found, consume it and return `Question (QNode n)`. Comments on the node are parsed and attached to the inner node before `?` is consumed.
3. A bare string without `?` remains invalid as a term (parse error as described above).

Whitespace between the string/node and `?` is handled by the lexer's whitespace skipping — the parser sees only the token stream.

## Checker Changes

### New Warning Mechanism

The checker currently only produces errors. A warning mechanism is added:

- Warnings are collected alongside errors during traversal.
- A warning does not cause the checker to fail (exit 0 is preserved).

### Warning Rules

**Rule 1: `?` without matching `|||`**

Walk the `Seq` chain at the current scope level with an integer counter (not a boolean). Increment the counter when encountering `Question`. Decrement (min 0) when encountering `Alt`. At scope exit, if counter > 0, emit one warning per unmatched `?`.

**Scope boundaries** (each is checked independently): top-level expression, `Loop` body, `Group` body, each branch of `Par`, and each branch of `Fanout`. The walker does **not** descend into these sub-scopes when scanning the current scope — each boundary spawns its own independent walk.

This means the `?` and `|||` must be in the same `Seq` chain (possibly with intermediate steps). A `|||` nested inside a `Par`/`Fanout` branch, `Group`, or `Loop` does **not** count as matching — it belongs to a different scope.

```
warning: '?' without matching '|||' in scope
```

Warnings do not include line/col positions (the AST does not carry position information). Adding position tracking to the AST is deferred to a future plan.

No other warning rules are added. Specifically, existing `|||` usage without an upstream `?` is **not** warned — this avoids a breaking change for current pipelines.

### Loop Interaction

`?` inside a `loop` body has a natural semantic interpretation:
- Left (condition met) → exit the loop
- Right (condition not met) → feed back, continue iterating

This is **not enforced** by the checker. The `?` inside `loop` follows the same warning rule as anywhere else — if there's no `|||` downstream in the loop body, it warns. The loop AST node remains `Loop of expr` with no variant distinction.

## CLI Output Changes

| Scenario | stdout | stderr | exit code |
|----------|--------|--------|-----------|
| Success, no warnings | AST | (empty) | 0 |
| Success, with warnings | AST | warning messages | 0 |
| Failure | (empty) | error messages | 1 |

Warning format matches existing error format with a `warning:` prefix.

## Pattern Match Exhaustiveness

Adding `Question` to `expr` requires updating all existing pattern matches:

- `attach_comments_right`: when called on `Question (QNode n)`, recurse into the inner node and attach comments there. For `Question (QString _)`, comments are dropped (strings have no comment field). In practice, comments are typically parsed and attached to the inner node before `?` is consumed, so this case is rare.
- Checker's `Loop` body scan: `Question` is traversed like any other node.
- Printer: new case for `Question` output.

## Printer Changes

`Question` prints in OCaml constructor format:

```
Question (QString "earth is not flat")
Question (QNode {name = "validate"; args = [{key = "method"; value = Ident "test_suite"}]; comments = []})
```

## Examples

### Basic branching

```
"earth is not flat"? >>> (believe ||| doubt)
```

### Node with arguments

```
validate(method: test_suite)? >>> (deploy ||| rollback)
```

### With intermediate steps

```
validate(method: test_suite)? >>> log >>> transform >>> (deploy ||| rollback)
```

### Inside loop

```
loop(
  generate >>> verify >>> "all tests pass"?
  >>> (exit ||| continue)
)
```

### Warning case

```
-- warns: '?' without matching '|||'
"is ready"? >>> process >>> done
```

### `|||` inside `***` does NOT match `?`

```
-- warns: '?' without matching '|||' — the ||| is inside a *** branch, different scope
"ready"? >>> a *** (b ||| c)
```

### Grouped question

```
-- valid: ("hello"?) is fine, ? binds inside the group
("is valid"?) >>> (accept ||| reject)
```

## Future Work

- **AST position tracking**: add line/col to AST nodes so warnings can report positions.
- **Let binding / composition**: if pipeline reuse becomes a real need, revisit named sub-pipelines.
- **`left` / `right` operators**: if explicit Either injection is needed.
- **Additional warning rules**: `|||` without upstream `?` (currently not warned to avoid breaking changes).
