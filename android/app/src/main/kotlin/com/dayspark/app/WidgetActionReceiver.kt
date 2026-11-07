package com.dayspark.app

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent

// Checkbox taps land here: write a typed command ({commandId, target, todoId, ...})
// into independent SharedPreferences storage key (`widget_command_<commandId>`).
// Per-instance UI state changes (list mode, selected calendar date) also land
// here, then the owning provider re-renders exactly one widget.
// The DB is off-limits on this path (single-writer rule).
// The snapshot blob is NOT modified.
class WidgetActionReceiver : BroadcastReceiver() {

  override fun onReceive(context: Context, intent: Intent) {
    when (intent.action) {
      WidgetSnapshot.ACTION_TOGGLE_TODO,
      WidgetSnapshot.ACTION_COMPLETE_ACTION,
      -> completeFromWidget(context, intent)

      ACTION_SET_TODO_MODE,
      ACTION_CYCLE_TODO_MODE,
      -> updateTodoMode(context, intent)

      ACTION_SET_CALENDAR_DATE,
      ACTION_CALENDAR_TODAY,
      ACTION_SET_CALENDAR_MODE,
      -> updateCalendarState(context, intent)
    }
  }

  private fun completeFromWidget(context: Context, intent: Intent) {
    val todoId = intent.getIntExtra(WidgetSnapshot.EXTRA_TODO_ID, -1)
    if (todoId < 0) return

    WidgetSnapshot.writeCommand(
      context = context,
      target = intent.getStringExtra(WidgetSnapshot.EXTRA_TARGET) ?: "todo",
      todoId = todoId,
      todoSyncId = intent.getStringExtra(WidgetSnapshot.EXTRA_TODO_SYNC_ID),
      occurrenceId = intent.getStringExtra(WidgetSnapshot.EXTRA_OCCURRENCE_ID),
      sourceAllocationId = intent.getStringExtra(WidgetSnapshot.EXTRA_SOURCE_ALLOCATION_ID),
    )

    refreshAllWidgets(context)
  }

  private fun updateTodoMode(context: Context, intent: Intent) {
    val appWidgetId = intent.getIntExtra(EXTRA_APP_WIDGET_ID, -1)
    if (appWidgetId <= 0) return
    val current = WidgetStateStore.read(context, appWidgetId)
    val nextMode = if (intent.action == ACTION_CYCLE_TODO_MODE) {
      WidgetUiState.nextTodoMode(current.todoMode)
    } else {
      when (val mode = intent.getStringExtra(EXTRA_TODO_MODE)) {
        "inbox", "all" -> mode
        else -> "today"
      }
    }
    WidgetStateStore.write(context, appWidgetId, current.copy(todoMode = nextMode))
    TodoWidgetProvider.updateWidget(
      context,
      AppWidgetManager.getInstance(context),
      appWidgetId,
    )
  }

  private fun updateCalendarState(context: Context, intent: Intent) {
    val appWidgetId = intent.getIntExtra(EXTRA_APP_WIDGET_ID, -1)
    if (appWidgetId <= 0) return
    val current = WidgetStateStore.read(context, appWidgetId)
    val updated = when (intent.action) {
      ACTION_SET_CALENDAR_DATE -> current.copy(
        selectedDate = intent.getStringExtra(EXTRA_CALENDAR_DATE),
        calendarMode = if (intent.getBooleanExtra(EXTRA_ENTER_DAY, false)) "day" else current.calendarMode,
      )
      ACTION_CALENDAR_TODAY -> current.copy(selectedDate = WidgetStateStore.todayIso())
      else -> current.copy(
        calendarMode = if (intent.getStringExtra(EXTRA_CALENDAR_MODE) == "day") "day" else "month",
      )
    }
    WidgetStateStore.write(context, appWidgetId, updated)
    CalendarWidgetProvider.updateWidget(
      context,
      AppWidgetManager.getInstance(context),
      appWidgetId,
    )
  }

  private fun refreshAllWidgets(context: Context) {
    val manager = AppWidgetManager.getInstance(context)
    val providers = listOf(
      TodayWidgetProvider::class.java,
      CalendarWidgetProvider::class.java,
      TodoWidgetProvider::class.java,
    )
    for (provider in providers) {
      val ids = manager.getAppWidgetIds(ComponentName(context, provider))
      if (ids.isEmpty()) continue
      val update = Intent(context, provider).apply {
        action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
        putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
      }
      context.sendBroadcast(update)
    }
  }

  companion object {
    const val ACTION_SET_TODO_MODE = "com.dayspark.app.action.SET_TODO_MODE"
    const val ACTION_CYCLE_TODO_MODE = "com.dayspark.app.action.CYCLE_TODO_MODE"
    const val ACTION_SET_CALENDAR_DATE = "com.dayspark.app.action.SET_CALENDAR_DATE"
    const val ACTION_CALENDAR_TODAY = "com.dayspark.app.action.CALENDAR_TODAY"
    const val ACTION_SET_CALENDAR_MODE = "com.dayspark.app.action.SET_CALENDAR_MODE"

    const val EXTRA_APP_WIDGET_ID = "appWidgetId"
    const val EXTRA_TODO_MODE = "todoMode"
    const val EXTRA_CALENDAR_DATE = "calendarDate"
    const val EXTRA_CALENDAR_MODE = "calendarMode"
    const val EXTRA_ENTER_DAY = "enterDay"
  }
}
