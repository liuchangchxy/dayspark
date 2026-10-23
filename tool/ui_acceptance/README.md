# D Final real Flutter acceptance app

Run from repository root:

```sh
flutter run -d macos --target tool/ui_acceptance/main.dart
flutter build web --target tool/ui_acceptance/main.dart --no-tree-shake-icons
python3 -m http.server 8765 --directory build/web
```

Open the web build at localhost:8765. Use 1440×900 for Desktop Action / Calendar / Todo, and 390×844 for Mobile Action. Navigate using the actual application sidebar or bottom navigation.

Use `--dart-define=QA_THEME=dark` and/or `--dart-define=QA_LOCALE=en` with run/build for dark and English checks. Defaults are light, Chinese, week calendar. Seed dates and current allocation are relative to launch time.

This renders production DaySparkApp, router, providers and Home with real SQLite data. Every launch creates a distinct `dayspark_d_final_acceptance_<timestamp>` Drift database; it never opens `calendar_todo`. All Todo, Event and TaskAllocation fixtures use existing creation providers/writers; only the initial QA calendar uses its existing DAO. Preferences are an in-memory test store initialized by `test/support/ui_acceptance_preferences.dart`; native user preferences are never accessed. No user sync credentials are present. All fixture records are illustrative QA data.

Web requires the repository's existing sqlite3.wasm / drift_worker.js assets. Native builds require the normal Flutter macOS prerequisites. The harness deliberately skips production main's alarm initialization, while retaining timezone initialization for recurrence and the actual DaySparkApp lifecycle.
