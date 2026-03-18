# GitHub Actions Release Pipeline Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 當 push `v*` tag 時，自動編譯 Linux (x86_64, static) 和 macOS (x86_64, arm64) 的 binary，上傳到 GitHub Releases。一般 commit 只跑 test。

**Architecture:** 兩個 workflow — `ci.yml` 負責每次 push/PR 只跑 test；`release.yml` 負責 tag 觸發的 build + release。Linux 用 `ocaml/opam:alpine-3.21-ocaml-5.1` Docker image（預裝 opam + OCaml，musl 環境產出 static binary）。macOS 分 x86_64 (macos-13) 和 arm64 (macos-latest) 兩個 runner。artifacts 用 flat 結構（`merge-multiple: true`），方便之後 shell script 用 curl 直接抓。

**Tech Stack:** GitHub Actions, `ocaml/setup-ocaml@v3`, `softprops/action-gh-release@v2`, dune, opam

---

## Chunk 1: CI and Release Workflow

### Task 1: 建立 CI workflow（每次 push/PR 只跑 test）

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: 建立 `.github/workflows/ci.yml`**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
        ocaml-compiler: ["5.1"]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4

      - uses: ocaml/setup-ocaml@v3
        with:
          ocaml-compiler: ${{ matrix.ocaml-compiler }}

      - run: opam install . --deps-only --with-test

      - run: opam exec -- dune test
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add test workflow"
```

### Task 2: 建立 Release workflow（tag 觸發，static binary）

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: 建立 `.github/workflows/release.yml`**

Linux job 用 `ocaml/opam:alpine-3.21-ocaml-5.1` image（預裝 opam + OCaml + musl），不需要手動編譯 OCaml。macOS 用原生編譯，分 x86_64 和 arm64。

> **備註：**
> - `ocaml/opam` image 的預設 user 是 `opam`，不是 `root`。checkout 的檔案權限要注意。
> - Alpine 上 `ldd` 可能不存在（musl 沒有標準 ldd），用 `file` 確認 "statically linked" 就夠。
> - `upload-artifact` / `download-artifact` 會丟失 execute bit，所以 release job 裡的 `chmod +x` 是必要的。
> - macOS-13 runner 已 deprecated（2025 Q4 起），2026 年中可能移除。屆時 x86_64 macOS binary 需要改用其他方案（例如 macos-latest + Rosetta cross-compile）。目前先維持 macos-13。

```yaml
name: Release

on:
  push:
    tags: ["v*"]

permissions:
  contents: write

jobs:
  build-linux:
    runs-on: ubuntu-latest
    container:
      image: ocaml/opam:alpine-3.21-ocaml-5.1
      options: --user root
    steps:
      - uses: actions/checkout@v4

      - name: Install dependencies
        run: |
          chown -R opam:opam .
          su opam -c "opam install . --deps-only --with-test -y"

      - name: Build
        run: su opam -c "opam exec -- dune build"

      - name: Test
        run: su opam -c "opam exec -- dune test"

      - name: Copy binary
        run: cp _build/default/bin/main.exe ocaml-compose-dsl-linux-x86_64

      - name: Verify static linking
        run: file ocaml-compose-dsl-linux-x86_64

      - uses: actions/upload-artifact@v4
        with:
          name: ocaml-compose-dsl-linux-x86_64
          path: ocaml-compose-dsl-linux-x86_64

  build-macos:
    strategy:
      matrix:
        include:
          - os: macos-13
            asset_name: ocaml-compose-dsl-macos-x86_64
          - os: macos-latest
            asset_name: ocaml-compose-dsl-macos-arm64

    runs-on: ${{ matrix.os }}

    steps:
      - uses: actions/checkout@v4

      - uses: ocaml/setup-ocaml@v3
        with:
          ocaml-compiler: "5.1"

      - run: opam install . --deps-only --with-test

      - run: opam exec -- dune build

      - run: opam exec -- dune test

      - name: Copy binary
        run: cp _build/default/bin/main.exe ${{ matrix.asset_name }}

      - uses: actions/upload-artifact@v4
        with:
          name: ${{ matrix.asset_name }}
          path: ${{ matrix.asset_name }}

  release:
    needs: [build-linux, build-macos]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with:
          path: artifacts
          merge-multiple: true

      - name: Make binaries executable
        run: chmod +x artifacts/*

      - uses: softprops/action-gh-release@v2
        with:
          files: artifacts/*
          generate_release_notes: true
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add release workflow for tagged versions"
```

### Task 3: 驗證 CI workflow

- [ ] **Step 1: Push 到 main，確認 CI 通過**

```bash
git push origin main
```

到 `https://github.com/caasi/ocaml-compose-dsl/actions` 確認 ubuntu 和 macos 的 test 都 pass。

### Task 4: 驗證 Release workflow

- [ ] **Step 1: 建立並 push tag**

```bash
git tag v0.1.0
git push origin v0.1.0
```

- [ ] **Step 2: 確認 release 頁面**

到 `https://github.com/caasi/ocaml-compose-dsl/releases` 確認：
- Release `v0.1.0` 存在，有自動產生的 release notes
- 三個 binary：`ocaml-compose-dsl-linux-x86_64`、`ocaml-compose-dsl-macos-x86_64`、`ocaml-compose-dsl-macos-arm64`
- Linux binary 是 statically linked（從 build log 的 `file` / `ldd` 輸出確認）

- [ ] **Step 3: 如果 release workflow 失敗，debug**

常見問題：
- Alpine container 缺 system package — 看 log 加 `apk add`
- `opam init` 在 container 裡需要 `--disable-sandboxing`
- `main.exe` 路徑不對 — 用 `find _build -name main.exe` 確認
- macOS-13 runner 被 GitHub 廢掉 — 改用其他 x86_64 runner 或放棄該 target
