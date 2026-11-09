# UI test layers

Run `flutter pub get` once after checkout or dependency changes, then run from the repository root on macOS with Flutter and Xcode installed:

| Entry | Purpose |
| --- | --- |
| `tool/test_fast.sh` | Domain tests, Widget journeys and master-detail behavior; no native app. |
| `tool/test_ui.sh` | Three native macOS `integration_test` flows using `DaySparkApp`, the production router and an isolated in-memory SQLite database. |
| `tool/test_full.sh` | Local guards, Dart packages, Flutter analyze and full tests, native UI flows, and a macOS release build and signature check. |

Full delivery also requires the existing CI jobs for Android, iOS simulator, web, Windows and Linux builds and their platform-specific checks. They cannot all run on one macOS host; the local full command does not claim to replace CI. CI runs the native flows once, in the existing macOS build job; the required `test` check combines that job with the Ubuntu checks. Timing varies with build caches and machine; the native app build makes UI substantially slower on a cold run.

Widget and journey tests judge state, data and breakpoint behavior. Native integration tests check a few user interactions in a running Flutter app; they use isolated preferences and database and disable home-widget refresh to avoid touching the user's widget data. Human or Agent GUI acceptance judges product experience, visibility, hierarchy, density and wording. See `tool/ui_acceptance/README.md` for that separate acceptance app.
