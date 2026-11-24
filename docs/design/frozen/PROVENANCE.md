# Frozen DaySpark UI/UX Spec

`dayspark-spec.html` is a verbatim copy of the frozen design master. Do not edit it.

| Field | Value |
|---|---|
| Source | OpenDesign local project `1a59db10-5541-4bc1-ad57-2f3bfbe121cc` |
| File | `dayspark-spec.html` |
| Freeze date | 2026-11-25 |
| Source file mtime | 2026-11-25 00:49:32 +08:00 |
| Bytes | 396808 |
| SHA-256 | `93f00029ce66e0c40a7b17cb45776513d889f95b66f792b78487b7e79d079c0e` |
| Status | `DAYSPARK_UI_UX_SPEC_FROZEN` |

Supersedes the 2026-11-21 master (`b7ed0c9b…`). This file is the only visual and
interaction authority for the Flutter UI. `ui/converge@560b058` is only the
Flutter implementation starting point — it is not a design authority. Flutter
does one convergence pass against this master; implementers do not redesign.
Flutter keeps owning real state, persistence, sync and platform behavior.

The freeze was preceded by a global visual review board
(`dayspark-review-board.html`, 22 representative desktop + mobile artboards):
one type scale, one row/header/button/sheet language, stable red/ink/gray
semantics, no screen that reads as old DaySpark or another app.
