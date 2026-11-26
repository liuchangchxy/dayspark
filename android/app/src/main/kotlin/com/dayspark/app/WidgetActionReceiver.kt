package com.dayspark.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

// The native widgets are a read-only snapshot: they never complete, edit or
// switch state in place. Every row is a deep link into the App, so the old
// command queue writes (complete / uncomplete) and the per-instance mode /
// calendar-date broadcasts have been removed. The class stays registered in
// the manifest so launchers and pending intents from older installs resolve to
// a safe no-op instead of crashing.
class WidgetActionReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    // Intentionally empty. Widget taps start MainActivity through
    // WidgetSupport.openUri; nothing mutates data from a widget broadcast.
  }
}
