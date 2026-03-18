#!/bin/sh
set -eu

TAG="${1:?Usage: $0 <tag>}"
ASSET="ocaml-compose-dsl-macos-x86_64"

echo "Building release binary..."
opam exec -- dune build --profile release @install

cp _build/install/default/bin/ocaml-compose-dsl "$ASSET"
echo "Built: $ASSET ($(file -b "$ASSET"))"

echo "Uploading to release $TAG..."
gh release upload "$TAG" "$ASSET" --clobber

rm "$ASSET"
echo "Done."
