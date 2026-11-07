package com.dayspark.app

import android.content.Context
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

data class WidgetUiState(
  val todoMode: String = "today",
  val selectedDate: String? = null,
  val calendarMode: String = "month",
)

// Per-instance UI state lives beside the snapshot but never inside it:
// snapshot refreshes must not reset a widget's selected list or date.
object WidgetStateStore {
  private const val KEY_PREFIX = "widget_state_"

  private fun key(appWidgetId: Int) = "$KEY_PREFIX$appWidgetId"

  fun read(context: Context, appWidgetId: Int): WidgetUiState {
    val raw = WidgetSnapshot.prefs(context).getString(key(appWidgetId), null)
    if (raw.isNullOrEmpty()) return WidgetUiState()
    return try {
      val json = org.json.JSONObject(raw)
      WidgetUiState(
        todoMode = when (val mode = json.optString("todoMode", "today")) {
          "inbox", "all" -> mode
          else -> "today"
        },
        selectedDate = json.optString("selectedDate", "").ifEmpty { null },
        calendarMode = if (json.optString("calendarMode", "month") == "day") "day" else "month",
      )
    } catch (_: Exception) {
      WidgetUiState()
    }
  }

  fun write(context: Context, appWidgetId: Int, state: WidgetUiState) {
    val json = org.json.JSONObject().apply {
      put("todoMode", state.todoMode)
      if (!state.selectedDate.isNullOrEmpty()) put("selectedDate", state.selectedDate)
      put("calendarMode", state.calendarMode)
    }
    WidgetSnapshot.prefs(context).edit().putString(key(appWidgetId), json.toString()).apply()
  }

  fun clear(context: Context, appWidgetId: Int) {
    WidgetSnapshot.prefs(context).edit().remove(key(appWidgetId)).apply()
  }

  fun todayIso(): String =
    SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

  fun normalizedSelectedDate(state: WidgetUiState): String {
    val today = todayIso()
    val selected = state.selectedDate
    if (selected.isNullOrEmpty()) return today
    val parsed = runCatching {
      SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { isLenient = false }.parse(selected)
    }.getOrNull() ?: return today
    val selectedCalendar = java.util.Calendar.getInstance().apply { time = parsed }
    val now = java.util.Calendar.getInstance()
    val sameMonth = selectedCalendar.get(java.util.Calendar.YEAR) == now.get(java.util.Calendar.YEAR) &&
      selectedCalendar.get(java.util.Calendar.MONTH) == now.get(java.util.Calendar.MONTH)
    return if (sameMonth) selected else today
  }
}
