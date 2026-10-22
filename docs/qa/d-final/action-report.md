# Action implementation

- Mapped and retained `actionProjectionProvider`, all existing completion provider invocations, exact recurrence occurrence IDs, Earlier missed/history pickers, recurrence error and legacy confirmation paths.
- Replaced repeated row cards with open divided list rows. Event calendar icon/time and planned checkbox/time remain distinct from deadline rows; section hierarchy retained.
- Current Event/Allocation intervals grouped under Now, followed by remaining schedule. Time-free deadlines remain in their own section.
- Desktop >=1000dp opens a 320dp inspector only when selected; editor button invokes original route callback. Mobile retains direct detail route and full-width rows, with 16dp content inset.
- Added desktop selection/edit-route test with long bilingual text and overflow exception check. Existing allocation/recurrence/history/error tests retained.
- `dart analyze lib/ui/pages/home/action_section.dart`: no issues.
- `flutter test test/ui/pages/home/action_section_test.dart`: 9 passed.
- Used Impeccable craft-floor and inspected frozen desktop screenshot. Full screenshot comparison remains parent integration responsibility.
- Six-things filtering and global date/header/navigation remain in Home ownership; no domain changes.

## Toolbar refinement
- Added mobile seven-day strip using existing `actionDateProvider` (at 390dp, each target is ~51x64dp), localized weekdays and active-day tint.
- Added local All/Events/Todos display filters; recurrence diagnostics and historical access paths retained. Added optional calendar callback.
- Added desktop six-things toggle using existing persisted setting. No Action-specific cap introduced (existing cap remains owned by Todo semantics).
- Added actual widget test for 390x844 week-strip target size, selected projection date and overflow. Focused suite now **10 passed**.
