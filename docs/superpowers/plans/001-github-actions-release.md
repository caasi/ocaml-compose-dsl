# GitHub Actions Release Pipeline Implementation Plan

> **Status:** ✅ Implemented via PR #1 (merged 2026-03-19)

**Goal:** 當 push `v*` tag 時，自動編譯 Linux (x86_64, static) 和 macOS (x86_64, arm64) 的 binary，上傳到 GitHub Releases。一般 commit 只跑 test。

**Architecture:** 兩個 workflow — `ci.yml` 負責每次 push/PR 只跑 test；`release.yml` 負責 tag 觸發的 build + release。Linux 用 `ocaml/opam:alpine-3.21-ocaml-5.1` Docker image（預裝 opam + OCaml，musl 環境產出 static binary）。macOS 分 x86_64 (macos-13) 和 arm64 (macos-15) 兩個 runner。artifacts 用 flat 結構（`merge-multiple: true`），方便之後 shell script 用 curl 直接抓。

**Tech Stack:** GitHub Actions, `ocaml/setup-ocaml@v3`, `softprops/action-gh-release@v2`, dune, opam

---

## Implementation Notes (deviations from original plan)

以下是實作過程中與原始 plan 不同的地方，經 Copilot code review (PR #2, #3, #4) 修正：

- **`opam install -y`** — 原始 plan 的 ci.yml 和 macOS job 漏了 `-y` flag，CI 會卡住
- **Permissions 最小化** — top-level 改 `contents: read`，只有 release job 給 `contents: write`
- **`dune-workspace` static profile** — 新增 `dune-workspace` 定義 `(static (link_flags (:standard -ccopt -static)))`，確保 musl 環境產出真正的 static binary
- **`dune build @install`** — 使用 `@install` target，binary 放在 `_build/install/default/bin/ocaml-compose-dsl`（public installed name）
- **Build profiles** — Linux 用 `--profile static`，macOS 用 `--profile release`
- **Test before build** — `dune test` 移到 `dune build --profile ...` 之前，避免 default profile 覆蓋 artifacts
- **Static linking 驗證** — `file` 輸出存變數避免跑兩次，grep pattern 加上 `static-pie linked`
- **`apk add file`** — Alpine 需要手動裝 `file` utility
- **`if-no-files-found: error`** — upload-artifact 加上，binary 不見直接 fail
- **macOS arm64 runner** — 從 `macos-latest` 改為 `macos-15`，避免 GitHub 改預設後 asset name 不符

---

## Chunk 1: CI and Release Workflow

### Task 1: 建立 CI workflow（每次 push/PR 只跑 test）

**Files:**
- Create: `.github/workflows/ci.yml`

- [x] **Step 1: 建立 `.github/workflows/ci.yml`**
- [x] **Step 2: Commit**

### Task 2: 建立 Release workflow（tag 觸發，static binary）

**Files:**
- Create: `.github/workflows/release.yml`
- Create: `dune-workspace`

- [x] **Step 1: 建立 `.github/workflows/release.yml`**
- [x] **Step 2: Commit**

### Task 3: 驗證 CI workflow

- [ ] **Step 1: Push 到 main，確認 CI 通過**

> 待首次 tag release 時驗證。

### Task 4: 驗證 Release workflow

- [ ] **Step 1: 建立並 push tag**
- [ ] **Step 2: 確認 release 頁面**
- [ ] **Step 3: 如果 release workflow 失敗，debug**

> 待首次 tag release 時驗證。
