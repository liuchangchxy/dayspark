package com.dayspark.app

import android.content.Context
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// The widgets are read-only snapshots now, so there is no per-instance
// selected list, calendar date or calendar mode to persist. Only two helpers
// survive: the ISO "today" the calendar provider keys off, and the cleanup of
// legacy `widget_state_<id>` keys when an instance is removed.
object WidgetStateStore {
  private const val KEY_PREFIX = "widget_state_"

  private fun key(appWidgetId: Int) = "$KEY_PREFIX$appWidgetId"

  fun clear(context: Context, appWidgetId: Int) {
    WidgetSnapshot.prefs(context).edit().remove(key(appWidgetId)).apply()
  }

  fun todayIso(): String =
    SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
}
