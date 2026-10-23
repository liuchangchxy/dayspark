# Calendar D Final implementation

## Code mapping and preserved boundaries
- CalendarSection keeps kalender controllers, interaction callbacks, recurrence/all-day drag guards, local wall-clock conversion, provider-controlled view and paging. Deadline data is optional host input and is never added to EventsController.
- EventTile retains adapter and detail callback. Shallow filled category blocks now carry a dot; TaskAllocationTile uses surface fill, dashed outline and square symbol. Both preserve readable font sizes and clip excess vertical content instead of shrinking it.
- CalendarDayHeader uses weekday above compact date and filled today circle. ViewSwitcher uses neutral selected surface, 48px minimum interaction target. Existing month/day/week logic remains.
- CalendarDeadlineLane displays civil-date matching deadlines beneath kalender's day/all-day header, independently from the busy-time canvas. Max 96px with scrolling protects the time canvas when many deadlines share a day. Items open existing Todo details via host callback.
- Current-time line uses the dark-aware semantic warning token; desktop toolbar provides dot/square/flag legend at wide sizes.

## Verification
- Red-before-green: new narrow TaskAllocation test failed for missing non-color square marker before implementation.
- `flutter test test/ui/widgets/calendar/`: 46 passed after final deadline lane cap and dark-aware semantic token changes.
- `flutter test test/ui/widgets/calendar/d_final_tiles_test.dart`: 2 passed, including visible-date filtering and deadline callback identity.
- `dart analyze lib/ui/widgets/calendar test/ui/widgets/calendar/d_final_tiles_test.dart`: no issues.
- Parent must run final all-tests/analyzer plus real screenshots and visual comparison after integration. No screenshot acceptance claimed here.
- Final calendar diff whitespace check passed.

## D Final differences / decisions
- Deadline cells retain >=48px touch targets rather than prototype's very thin 26px lane; max96px scrolling protects calendar space → more vertical space but operable on touch.
- Month remains supported, alongside prioritized week/day; no domain behavior changed.
- No recurrence deadline expansion invented: host supplies ordinary deadlines only; series require existing occurrence-aware projection before representing additional dates.
