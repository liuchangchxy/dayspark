# Frozen DaySpark UI/UX Spec

`dayspark-spec.html` and `dayspark-coverage-map.md` are verbatim copies of the frozen design master and its coverage map. Do not edit them.

| Field | Value |
|---|---|
| Source | OpenDesign local project `1a59db10-5541-4bc1-ad57-2f3bfbe121cc` |
| Files | `dayspark-spec.html`, `dayspark-coverage-map.md` |
| Freeze date | 2026-11-26 |
| Bytes (spec) | 589984 |
| SHA-256 (spec) | `6c350167894af67cc31097ca5021bd340317248a17b22cd0e8fbad673f71f9bf` |
| Bytes (map) | 17987 |
| SHA-256 (map) | `887733c5fc3a5c7e39257681916e1f48792f620061e84dbdd5615e7dd4234aad` |
| Status | `DAYSPARK_UI_UX_SPEC_FROZEN` |

Supersedes the 2026-11-25 master (`93f00029…`). This freeze includes the pre-freeze adjudication: mobile calendar Today/search/create entries, out-of-range and cross-midnight presentation, clickable timed deadlines, stale-data error state, recurring-save scope confirmation, multi-day all-day creation, deleted-object and startup-failure states, and the mobile pushed-page sync banner.

`dayspark-spec.html` is the only visual and interaction authority for the Flutter UI. `dayspark-coverage-map.md` records feature → operation → required UI/state → board → verdict, plus the implementation/design/product classification. `ui/converge@2027d5a` is the Flutter implementation starting point, not a design authority. Implementers do not redesign; Flutter keeps owning real state, persistence, sync and platform behavior.
