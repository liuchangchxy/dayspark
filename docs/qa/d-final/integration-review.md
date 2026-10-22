# Independent integration review — Shell / Theme / Todo

Scope: reviewed Home, WorkspaceSidebar, Theme, accent preset compatibility, TodoListTile; Calendar and Action implementation excluded from independent code judgment. Followed docs/process/REVIEWING.md. No production/test edits by reviewer.

## Specification conformity
- ✅ Three primary desktop destinations and mobile Bottom Navigation; mobile threshold 1000 logical pixels. Home page heading shares horizontal origin 28 desktop /16 mobile across tabs (`home_page.dart:399`). Existing saved initial tab retained.
- ✅ Independent 48×48 completion checkbox, separate title/detail InkWell; recurring Todo completion still delegates through existing occurrence picker (`todo_list_tile.dart:134`, `_toggle`). No new domain writer or entity.
- ✅ Blue default changes to frozen cobalt while all persisted AppAccent IDs remain identical; green/orange/purple presets and legacy fallback remain supported (`theme_provider.dart:14,34,38,88`).
- ✅ Deadline consumption filters ordinary active Todos and routes to existing detail route; no recurrence expansion fabricated (`home_page.dart:_buildCalendarTab`).
- ✅ Changed paths do not include database/schema/sync/reminder/attachment/backup/MCP writes. Theme provider edit is presentation color only.
- Pending independent evidence: real 1440×900 /390×844 screenshots and dark/long-text comparison. Widget checks do not replace visual acceptance.

## Quality findings
- **P1, found and fixed during review:** workspace-create was inserted into What's New dialog actions while FAB was removed, leaving normal pages without create access (original Home lines233–254). Parent moved it to AppBar actions; current `home_page.dart:342–361` has the real create entry. Focused analyzer subsequently reports zero issues. No remaining finding from this root cause.
- **Gate failure pending parent fix:** theme tests still assert old blue/background/radius16; new frozen values intentionally differ. Reviewer command below produced three failures. Update tests to externally specified D Final values rather than weakening assertions. This prevents claiming full-green delivery before tests reflect approved baseline.
- No further P0/P1 found in inspected shell/Todo code.

## Independently executed evidence
- `dart analyze lib/ui/pages/home/home_page.dart lib/ui/widgets/workspace_sidebar.dart lib/ui/widgets/todo/todo_list_tile.dart lib/core/theme lib/domain/providers/theme_provider.dart`: **No issues found**.
- `flutter test test/ui/pages/home/home_tab_navigation_test.dart`: **5 passed**; saved initial tabs, tab changes and desktop shared content origin exercised.
- `flutter test test/ui/widgets/todo/todo_list_tile_test.dart test/ui/widgets/todo/todo_list_tile_l10n_test.dart test/core/theme/app_theme_test.dart test/core/theme/app_colors_test.dart`: **24 passed, 3 failed**. Failures exactly old light accent, old light background and old card radius expectations. Todo interaction and long Chinese/English mobile row checks passed.

## Adversarial recipe application
1. Empty-test attack: Todo tests assert real callback counts and zero detail taps when checkbox tapped; desktop/mobile geometry assertions depend on actual render layout. Existing theme-provider enum existence test is not accepted as preset compatibility evidence; source persistence IDs inspected directly.
2. Boundary: mobile title/date at390 logical width and independent48px target exercised; Home five-tab tests exercise branch threshold/desktop origin. Very short desktop windows still require real screenshot evidence, no blanket responsive claim.
3. Evidence inversion: analyzer found no issue only after moved create entry; real AppBar integration is inspected, not existence of a detached button definition. Runtime fingerprint/screenshots delegated to parent.
4. Self-proof: color tests currently have external literal old design values and correctly turned red; must replace from frozen design truth, not copy constants into expectations.
5. Key consistency: AppAccent blue/green/orange/purple string IDs unchanged; ARB shared generation consumed. No wire/schema changes.
6. Delivery penetration: no build success treated as visual acceptance; parent real runtime capture remains required.

Quality conclusion: **Approved for reviewed code after reported create fix, conditional on resolving three stale theme assertions and completing required runtime visual verification.** Not a final full-goal acceptance.
