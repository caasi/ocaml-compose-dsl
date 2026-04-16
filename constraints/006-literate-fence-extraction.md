---
id: RULE-006
title: Literate mode only extracts arrow/arr fenced code blocks
domain: markdown
severity: must
---

## Given

A Markdown document processed in literate mode (`--literate`).

## When

The `Markdown.extract` function scans for fenced code blocks.

## Then

- Only blocks fenced with exactly `` ```arrow `` or `` ```arr `` (with optional trailing whitespace) are extracted.
- Tilde fences (`~~~arrow`) are **not** recognized.
- Four or more backtick fences (`````arrow`) are **not** recognized.
- Info string prefixes (`arrows`, `arrow-diagram`) are **not** recognized.
- Extra text after the info string (e.g., `` ```arrow some-label ``) causes the block to be rejected.
- Indentation up to 3 spaces before the fence is allowed; 4+ spaces makes it not a fence.
- Unclosed blocks (no closing fence) are still extracted.
- CRLF line endings are normalized to LF in extracted content.
- Multiple extracted blocks are combined with `;` (semicolon) as statement separator.
- Line numbers are translated back to original Markdown positions via the offset table.

## Unless

N/A — these rules define the boundary of what constitutes a valid code block.

## Examples

| Input | Blocks Extracted | Pass? |
|---|---|---|
| `` ```arrow\na >>> b\n``` `` | 1 | yes |
| `` ```arr\na >>> b\n``` `` | 1 | yes |
| `~~~arrow\na >>> b\n~~~` | 0 | yes |
| ```` ````arrow\na >>> b\n```` ```` | 0 | yes |
| `` ```arrows\na >>> b\n``` `` | 0 | yes |
| `` ```arrow-diagram\na >>> b\n``` `` | 0 | yes |
| `` ```arrow some-label\na >>> b\n``` `` | 0 | yes |
| `   ```arrow\na >>> b\n   ``` ` (3-space indent) | 1 | yes |
| `    ```arrow\na >>> b\n    ``` ` (4-space indent) | 0 | yes |
| `` ```arrow\na >>> b\n `` (unclosed) | 1 | yes |
| `` ```arrow  \na >>> b\n``` `` (trailing ws) | 1 | yes |

## Properties

- **Strict matching**: Only the exact info strings `arrow` and `arr` are accepted.
- **CommonMark-aligned**: Indentation and fence rules follow CommonMark conventions (3-space max indent).
- **Graceful degradation**: Unclosed blocks are still extracted rather than silently dropped.
- **Line mapping preservation**: Error positions can always be translated back to original Markdown line numbers.
