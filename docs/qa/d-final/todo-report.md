# Todo D Final implementation

Changed `lib/ui/widgets/todo/todo_list_tile.dart` and its focused widget tests.

- Flat list rows with hairline separators, compact priority marks, title-first hierarchy.
- Desktop deadline aligned on the right; mobile places deadline beneath a two-line bounded title.
- No empty date metadata for undated items. Existing tags retain tooltip labels; recurrence has a repeat icon.
- Checkbox now has a real 48 × 48 target independent from the details target.
- `_toggle` and occurrence selection logic unchanged; no Provider/Writer/domain edits.
- Existing optional index remains supported; parent can omit ordinal display for D Final.

Validation: focused Todo tile and l10n tests: 10 passed. Targeted dart analyze: no issues.
New tests verify 390px mixed-language layout, mobile deadline placement, actual checkbox dimensions, desktop deadline alignment, and no Card container. Existing tests retain toggle/detail separation and completed restoration.

Visual baseline inspected: D Final desktop Todo screenshot. Impeccable craft-floor applied. Full app screenshots, dark-mode comparison, full analyze/test and CI remain parent integration tasks.
