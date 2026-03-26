# ocaml-compose-dsl

[![CI](https://github.com/caasi/ocaml-compose-dsl/actions/workflows/ci.yml/badge.svg)](https://github.com/caasi/ocaml-compose-dsl/actions/workflows/ci.yml)

A structural checker for an Arrow-style DSL designed for AI agent workflow composition.

## What Is This?

AI agents compose tools through natural language reasoning, but this approach is unreproducible, hard to review, and disappears when the conversation ends. This DSL gives agents (and humans) a shared, structured language to describe multi-step workflows — **without requiring a runtime or interpreter**. The agent itself expands the DSL into concrete tool calls.

The DSL uses Arrow combinators because they sit at the sweet spot between shell pipes (too linear) and monads (too opaque): pipeline structure is fully visible before execution.

## Grammar (EBNF)

```ebnf
program = { let_binding } , pipeline ;

let_binding = "let" , ident , "=" , seq_expr ;

lambda  = "\" , ident , { "," , ident } , "->" , seq_expr ;

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
         | lambda
         ;

node     = ident , [ "(" , [ call_args ] , ")" ] ;

call_args = named_args | positional_args ;

named_args      = arg , { "," , arg } ;
positional_args = seq_expr , { "," , seq_expr } ;

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
                (* note: "-" is a valid ident_char, but the lexer stops
                   before "->" so that the arrow token is recognized
                   even without surrounding whitespace *)

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

```
let greet = \name -> hello(to: name) >>> respond
greet(alice) >>> greet(bob)
```

```
let review = \trigger, fix ->
  loop(trigger >>> (pass ||| fix))

let phase1 = gather >>> review(check?, rework)
let phase2 = build >>> review(test?, fix)

phase1 >>> phase2
```

Lambdas and let bindings are reduced to pure Arrow pipelines before structural checking. They provide abstraction without adding runtime semantics.

> **Note:** `let` and `loop` are reserved keywords and cannot be used as node names.

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

Exits `0` with AST output in a constructor-style format (e.g. `TypeAnn(Node(...), "Input", "Output")` for annotated terms) on valid input, `1` with error messages on structural problems. Well-formedness warnings (e.g. `?` without matching `|||`) are printed to stderr without affecting the exit code.

## Literate Arrow Documents

Arrow DSL is designed to work inside natural language documents. Use fenced code blocks with the `arrow` language tag to embed workflow definitions and lightweight type constraints alongside prose — no special file extension or evaluator required. Any Markdown document can be a literate Arrow document.

````markdown
## Deployment

Build artifacts must pass CI before release.

```arrow
build :: Source -> Artifact
  >>> test :: Artifact -> Verified
  >>> deploy(env: production) :: Verified -> Released
```

The `:: Source -> Artifact` annotations serve as simple type
constraints that document what each step expects and produces,
making the workflow reviewable by both humans and agents.
````

Convention: `.arr` for standalone DSL files. For literate documents, just use regular `.md` — the `arrow` code blocks speak for themselves.

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
