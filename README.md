# ocaml-compose-dsl

A structural checker for an Arrow-style DSL designed for AI agent workflow composition.

## What Is This?

AI agents compose tools through natural language reasoning, but this approach is unreproducible, hard to review, and disappears when the conversation ends. This DSL gives agents (and humans) a shared, structured language to describe multi-step workflows — **without requiring a runtime or interpreter**. The agent itself expands the DSL into concrete tool calls.

The DSL uses Arrow combinators because they sit at the sweet spot between shell pipes (too linear) and monads (too opaque): pipeline structure is fully visible before execution.

## Grammar (EBNF)

```ebnf
pipeline = expr ;

expr     = term , { operator , term } ;

operator = ">>>"                        (* sequential composition *)
         | "***"                        (* parallel composition *)
         | "|||"                        (* branch / fallback *)
         ;

term     = node
         | "loop" , "(" , expr , ")"    (* feedback loop *)
         | "(" , expr , ")"            (* grouping *)
         ;

node     = ident , [ "(" , [ args ] , ")" ] ;

args     = arg , { "," , arg } ;

arg      = ident , ":" , value ;

value    = string
         | ident
         | "[" , [ value , { "," , value } ] , "]"
         ;

ident    = ( letter | "_" ) , { letter | digit | "-" | "_" } ;

string   = '"' , { any char - '"' } , '"' ;

comment  = "--" , { any char - newline } ;
```

Comments can appear after any term and are attached to the preceding node as purpose descriptions or reference tool annotations.

## Example

```
read(source: "data.csv")
  >>> parse(format: csv)
  >>> filter(condition: "age > 18")
  >>> (count *** collect(fields: [email]))
  >>> format(as: report)
```

```
loop (
  generate(artifact: code, from: spec)
    >>> verify(method: test_suite)
    >>> evaluate(criteria: all_pass)
)
```

## Usage

```sh
# From file
ocaml-compose-dsl pipeline.arrow

# From stdin
echo 'a >>> b' | ocaml-compose-dsl
```

Exits `0` with `OK` on valid input, `1` with error messages on structural problems.

## Build

Requires OCaml >= 5.1 and Dune >= 3.0.

```sh
dune build
dune test
```

## License

MIT
