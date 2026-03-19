# Numeric Literal Support

## Summary

Add numeric literal support to the DSL so node arguments can accept numbers (integers and decimals) as values, stored as raw strings without evaluation.

## Motivation

Currently `value` only supports `String`, `Ident`, and `List`. Numeric configuration values like `resize(width: 1920, height: 1080)` or `delay(seconds: 3.5)` must be quoted as strings or abused as idents. A `Number` variant makes intent explicit while keeping the DSL non-evaluating.

## Design

### AST (`lib/ast.ml`)

Add `Number of string` to the `value` type:

```ocaml
type value =
  | String of string
  | Ident of string
  | Number of string
  | List of value list
```

The string stores the literal text as written (e.g. `"-3.14"`). No parsing to int/float occurs — consumers decide interpretation.

### Lexer (`lib/lexer.ml`)

New token: `NUMBER of string`.

Matching rule: optional `-` prefix, one or more digits, optional `.` followed by one or more digits.

```
-? [0-9]+ ("." [0-9]+)?
```

The lexer adds a `read_number` function and a new match arm for digit characters (and `-` when followed by a digit, distinguishing from `--` comments).

### Parser (`lib/parser.ml`)

`parse_value` gains a `NUMBER s -> Number s` arm. The same arm is added inside list parsing so numbers can appear in lists (e.g. `[1, 2, 3]`).

### Printer (`lib/printer.ml`)

`value_to_string` gains:

```ocaml
| Number s -> Printf.sprintf "Number(%S)" s
```

### Checker (`lib/checker.ml`)

No changes. The checker validates structure, not value types.

### EBNF (`README.md`)

```ebnf
value    = string
         | number
         | ident
         | "[" , [ value , { "," , value } ] , "]"
         ;

number   = [ "-" ] , digit , { digit } , [ "." , digit , { digit } ] ;
```

## Files Changed

| File | Change |
|------|--------|
| `lib/ast.ml` | Add `Number of string` to `value` |
| `lib/lexer.ml` | Add `NUMBER of string` token, `read_number`, match arms for digits and negative sign |
| `lib/parser.ml` | Handle `NUMBER` in `parse_value` and list value parsing |
| `lib/printer.ml` | Handle `Number` in `value_to_string` |
| `README.md` | Update EBNF grammar |
| `test/test_compose_dsl.ml` | Add tests for integer, float, negative, and number-in-list cases |

## Edge Cases

- `-` alone is not a number (requires digit after)
- `-` followed by `-` is a comment, not a negative sign
- `.5` (no leading digit) is not valid — must be `0.5`
- `3.` (trailing dot, no fractional digits) is not valid — must be `3.0` or `3`
- Numbers only appear as arg values or list elements, never as node names
