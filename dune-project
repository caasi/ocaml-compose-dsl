(lang dune 3.0)

(name ocaml-compose-dsl)

(version 0.5.0)

(generate_opam_files true)

(source
 (github caasi/ocaml-compose-dsl))

(authors "caasi Huang" "Claude <noreply@anthropic.com>")

(maintainers "caasi Huang")

(license MIT)

(package
 (name ocaml-compose-dsl)
 (synopsis "A compose DSL for OCaml")
 (depends
  (ocaml
   (>= 5.1))
  dune))

(package
 (name ocaml-compose-dsl-lib)
 (synopsis "Library for ocaml-compose-dsl")
 (depends
  (ocaml
   (>= 5.1))
  dune
  (alcotest :with-test)))
