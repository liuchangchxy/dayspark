# Task 1 evidence — quick-add input latency (2026-11-14)

## What was reported

Repeated todo creation on a real Android phone: after roughly two creations,
typing the next todo becomes severely laggy, sometimes barely usable.

## Reproduction environment available

No physical device was attached to this workstation (`adb devices` empty; the
Device panel offered no Android host). An API 35 `google_apis` x86_64 emulator
was provisioned under `D:\ADB` and driven with `adb`, with an instrumented
profile build (`--dart-define=DS_FRAME_PROBE=true`).

Limit of that environment, stated plainly: text was injected through
`adb shell input`, so Gboard's composing path and voice dictation were not
exercised the way a human thumbs them. Frame and main-thread measurements are
valid; "the keyboard felt slow" is not something this harness can judge.

## Instrumentation

- Dart: `SchedulerBinding.addTimingsCallback` (slow frames ≥32 ms), plus
  `Stopwatch` around `HomeWidgetService.updateWidget` (total / projection /
  action / todos / month / l10n) and around `ReminderReconciler._enqueue`.
- Kotlin: `System.nanoTime()` around each provider's `onUpdate`.
- Scenario: a calendar widget pinned on the launcher (so the native path runs),
  then 15–75 todos created through the real UI.

## Measurements

Per-keystroke UI work (75 todos in the database, typing into the Tasks-tab
inline field and the mobile quick-create sheet):

- worst frame **build** time: 15 ms; typical 1–9 ms
- no frame over 16 ms of UI-thread work in 158 sampled slow frames

So the typing path itself is O(text length), not O(todo count). The parser runs
~13 regexes per rebuild, and the widget snapshot is never rebuilt per keystroke.

Per committed write (before the fix), same build:

| Phase | ms |
|---|---|
| `updateWidget` total | 58–152 |
| Dart snapshot build | 25–65 |
| — `ActionProjectionQuery.fetch` | **14–30** |
| — `buildTodosBlock` | 2–7 |
| — `monthCalendar` | 2–8 |
| — l10n + theme (prefs cached) | 0 |
| native `CalendarWidgetProvider.onUpdate` (1 instance) | 21–36 |
| `ReminderReconciler` queue | 12–63 |

Every commit published on the record bus, and the listener rebuilt the whole
snapshot immediately — one build (plus a synchronous `SharedPreferences.commit`
and three `AppWidget` broadcasts) per save, landing in exactly the gap before
the next keystroke. Cost is flat per save but scales with widget instances,
todo/event count (`fetch` re-selects all todos several times) and device speed;
on a mid/low-end phone the same window is several hundred milliseconds, which
is the shape the report describes.

## Fix (no feature disabled)

`lib/infrastructure/platform/widget_refresh_scheduler.dart`:

- coalesce a burst of record-bus batches into one rebuild (400 ms trailing);
- hold the rebuild while a text field owns focus (IME live), capped at 4 s so
  widgets cannot go stale during a long typing session;
- one in-flight rebuild at a time; requests during a run collapse into one
  follow-up.

`HomeWidgetService.updateWidget` also returns early when the launcher hosts no
DaySpark widget (`hasWidgets` on the existing `com.dayspark.app/widget_commands`
channel), after still draining widget commands and legacy pending taps — a tap
queued by a since-removed widget is still a user action.

Measured after the fix, 15 rapid creations with a widget pinned:

- snapshot rebuilds: **5 instead of 15** (~4.6 s apart, i.e. off the save path)
- per rebuild: 59–65 ms total, 16–23 ms Dart build

## Not verified

- Real-device behaviour with Gboard Chinese composing and voice dictation.
- Whether the phone's symptom disappears: that needs the device.

The fix removes the only write-triggered work measured to accumulate and to
run inside the typing window; it does not prove the phone's lag was solely this.

## Independent review findings applied

An independent reviewer re-read the diff, ran the affected tests, and drove the
scheduler's state machine with scripted timelines. Four defects it found were
fixed in the same branch:

1. **Consumed legacy taps were never cleared with zero instances.** The old
   snapshot is the only place `pendingTaps` lives, and the early return skipped
   the rewrite, so every later flush replayed the tap and republished on the
   record bus — a 400 ms refresh loop for the life of the process. The snapshot
   is now always rewritten; only the native broadcast is gated.
2. **The max-deferral bound could be lost.** A request arriving during an
   in-flight run had its cap consumed by the run it could not start, leaving it
   with no deadline once the debounce met a focused field. The cap is now
   re-armed on both paths (regression test:
   `a run that outlives the cap cannot defer forever`).
3. **A sync-throwing refresh wedged the scheduler** (`_running` stayed true).
   `_onRun` now goes through `Future.sync`.
4. **The `hasWidgets` probe could abort rendering** by rethrowing anything that
   was not `MissingPluginException`/`PlatformException`; it now assumes
   installed on any failure.

Also covered by new tests: the probe returning false must not stop the snapshot
from being written (a widget pinned later reads it directly), and a consumed
legacy tap is cleared in the stored blob.

The reviewer's remaining observations are recorded as follow-ups rather than
silently dropped: `updateHomeWidgetProvider` and the scheduler can still call
`updateWidget` concurrently (pre-existing; completion is idempotent via
`alreadyApplied`), and `consumeWidgetCommands` has no mutual exclusion.
