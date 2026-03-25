# ocaml-compose-dsl

[![CI](https://github.com/caasi/ocaml-compose-dsl/actions/workflows/ci.yml/badge.svg)](https://github.com/caasi/ocaml-compose-dsl/actions/workflows/ci.yml)

A structural checker for an Arrow-style DSL designed for AI agent workflow composition.

## What Is This?

AI agents compose tools through natural language reasoning, but this approach is unreproducible, hard to review, and disappears when the conversation ends. This DSL gives agents (and humans) a shared, structured language to describe multi-step workflows — **without requiring a runtime or interpreter**. The agent itself expands the DSL into concrete tool calls.

The DSL uses Arrow combinators because they sit at the sweet spot between shell pipes (too linear) and monads (too opaque): pipeline structure is fully visible before execution.

## Grammar (EBNF)

```ebnf
pipeline = seq_expr ;

seq_expr = alt_expr , ">>>" , seq_expr              (* sequential — infixr 1 *)
         | alt_expr ;
alt_expr = par_expr , "|||" , alt_expr              (* branch — infixr 2 *)
         | par_expr ;
par_expr    = typed_term , ( "***" | "&&&" ) , par_expr (* parallel / fanout — infixr 3 *)
            | typed_term ;

typed_term  = term , [ "::" , type_expr ] ;

type_expr   = ident , "->" , ident ;

question_term = string , "?"                       (* question — produces Either *)
              | node , "?"
              ;

term     = node
         | "loop" , "(" , seq_expr , ")"            (* feedback loop *)
         | "(" , seq_expr , ")"                    (* grouping *)
         | question_term
         ;

node     = ident , [ "(" , [ args ] , ")" ] ;

args     = arg , { "," , arg } ;

arg      = ident , ":" , value ;

value    = string
         | number
         | ident
         | "[" , [ value , { "," , value } ] , "]"
         ;

ident       = ident_start , { ident_char } ;
ident_start = ? any valid UTF-8 codepoint that is not an ASCII digit,
                not ASCII whitespace, and not one of ( ) [ ] : , > * | & - " .
                ! # $ % ^ + = { } < ; ' ` ~ / ? @ \ ? ;
ident_char  = ? any valid UTF-8 codepoint that is not ASCII whitespace,
                and not one of ( ) [ ] : , > * | & " .
                ! # $ % ^ + = { } < ; ' ` ~ / ? @ \ ? ;

string   = '"' , { ? any valid UTF-8 codepoint except '"' ? } , '"' ;

number     = [ "-" ] , digit , { digit } , [ "." , digit , { digit } ] , [ ident_start , { ident_char } ] ;

comment  = "--" , { any char - newline } ;
```

All operators are right-associative (matching Haskell Arrow fixity). Comments can appear after any term and are attached to the preceding node as purpose descriptions or reference tool annotations.

## Arrow Semantics

The operators follow Arrow combinator semantics. The DSL has no type checker —
the `::` type annotations and the types in this table describe the data flow for the agent (and human) reading the pipeline.

| Operator | Name           | Type                                          |
|----------|----------------|-----------------------------------------------|
| `>>>`    | compose        | `Arrow a b → Arrow b c → Arrow a c`           |
| `***`    | product        | `Arrow a b → Arrow c d → Arrow (a,c) (b,d)`   |
| `&&&`    | fanout         | `Arrow a b → Arrow a c → Arrow a (b,c)`       |
| <code>&#124;&#124;&#124;</code> | fanin / branch | `Arrow a c → Arrow b c → Arrow (Either a b) c` |
| `loop`   | feedback       | `Arrow (a,s) (b,s) → Arrow a b`               |
| `?`     | question       | `Arrow a (Either a a)`                        |

`***` is right-associative: `a *** b *** c` types as `(A, (B, C))`.
Comments can annotate the concrete types when the structure isn't obvious from node names.

## Type Annotations

Nodes and terms can carry optional type annotations using `::`:

```
fetch(url: "https://example.com") :: URL -> HTML
  >>> parse :: HTML -> Data
  >>> filter(condition: "age > 18") :: Data -> Data
  >>> format(as: report) :: Data -> Report
```

Annotations are optional — a pipeline can freely mix annotated and unannotated nodes. Type identifiers follow the same `ident` rule as node names, including Unicode support.

Type annotations are **documentation, not enforcement**. They are parsed into the AST but not checked. The DSL has no type checker — annotations describe the intended data flow for the agent (and human) reading the pipeline.

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

```
(lint &&& test)
  >>> gate(require: [pass, pass])
  >>> (build_linux(profile: static) *** build_macos(profile: release))
  >>> upload(tag: "v0.1.0")
```

```
resize(width: 1920, height: 1080)
  >>> compress(quality: 85)
  >>> dose(amount: 100mg)       -- numeric literals with unit suffixes
  >>> adjust(offset: -3.14)     -- negative floats supported
```

```
読み込み(ソース: "データ.csv")
  >>> フィルタ(条件: "年齢 > 18")
  >>> 出力
```

```
"earth is not flat"?
  >>> (believe ||| doubt)
```

```
loop(
  generate >>> verify >>> "all tests pass"?
  >>> (continue ||| fix_and_retry)
)
```

```
planning :: Doc -> Commit
  >>> commit(branch: main)

implementation :: Code -> Commit
  >>> branch(pattern: "feature/*") :: Code -> Branch
  >>> commit :: Branch -> Commit
```

Identifiers and unit suffixes accept any non-ASCII UTF-8 codepoint, so the DSL works naturally with non-Latin scripts. Error positions report codepoint-level columns, not byte offsets.

## Usage

```sh
# From file
ocaml-compose-dsl pipeline.arr

# From stdin
echo 'a >>> b' | ocaml-compose-dsl

# Help and version
ocaml-compose-dsl --help
ocaml-compose-dsl --version
```

Exits `0` with AST output in a constructor-style format with optional `:: input -> output` type annotations on valid input, `1` with error messages on structural problems. Well-formedness warnings (e.g. `?` without matching `|||`) are printed to stderr without affecting the exit code.

## Literate Arrow Documents

Arrow DSL is designed to work in literate documents — files where natural language prose and Arrow code blocks coexist. Use fenced code blocks with the `arrow` language tag:

````markdown
## Deployment

Build artifacts must pass CI before release.

```arrow
build :: Source -> Artifact
  >>> test :: Artifact -> Verified
  >>> deploy(env: production) :: Verified -> Released
```
````

Convention: `.arrow.md` for literate documents, `.arr` for standalone DSL files.

## Install

Pre-built binaries are available on the [Releases](https://github.com/caasi/ocaml-compose-dsl/releases) page for:

- Linux x86_64 (statically linked)
- macOS x86_64
- macOS arm64

## Build

Requires OCaml >= 5.1 and Dune >= 3.0.

```sh
dune build
dune test
```

## Known Limitations

- The recursive descent parser is not tail-recursive. Extremely long pipelines (thousands of chained operators) could overflow the stack. In practice this is unlikely for human-authored workflows.

## License

MIT
