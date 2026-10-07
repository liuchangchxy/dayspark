package com.dayspark.app

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent

// Checkbox taps land here: write a typed command ({commandId, target, todoId, ...})
// into independent SharedPreferences storage key (`widget_command_<commandId>`) and
// re-render every widget.
// The DB is off-limits on this path (single-writer rule).
// The snapshot blob is NOT modified (ruling E).
// The app drains the queue through the domain toggleTodo pipeline on launch, resume, or refresh.
class WidgetActionReceiver : BroadcastReceiver() {

  override fun onReceive(context: Context, intent: Intent) {
    val action = intent.action
    if (action != WidgetSnapshot.ACTION_TOGGLE_TODO && action != WidgetSnapshot.ACTION_COMPLETE_ACTION) {
      return
    }

    val todoId = intent.getIntExtra(WidgetSnapshot.EXTRA_TODO_ID, -1)
    if (todoId < 0) return

    val target = intent.getStringExtra(WidgetSnapshot.EXTRA_TARGET) ?: "todo"
    val todoSyncId = intent.getStringExtra(WidgetSnapshot.EXTRA_TODO_SYNC_ID)
    val occurrenceId = intent.getStringExtra(WidgetSnapshot.EXTRA_OCCURRENCE_ID)
    val sourceAllocationId = intent.getStringExtra(WidgetSnapshot.EXTRA_SOURCE_ALLOCATION_ID)

    // Append to independent command storage key (Ruling E)
    WidgetSnapshot.writeCommand(
      context = context,
      target = target,
      todoId = todoId,
      todoSyncId = todoSyncId,
      occurrenceId = occurrenceId,
      sourceAllocationId = sourceAllocationId,
    )

    refreshAllWidgets(context)
  }

  private fun refreshAllWidgets(context: Context) {
    val manager = AppWidgetManager.getInstance(context)
    val providers = listOf(
      CalendarTodoWidgetProvider::class.java,
      UpcomingWidgetProvider::class.java,
      MonthDotsWidgetProvider::class.java,
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
}
