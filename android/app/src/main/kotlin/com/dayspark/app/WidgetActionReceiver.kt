package com.dayspark.app

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// Checkbox taps land here: append {todoId, action:"complete", at} onto the
// stored snapshot's pendingTaps queue and re-render every widget — nothing
// else. The DB is off-limits on this path (single-writer rule); the app
// consumes the queue on its next flush through the normal complete flow.
class WidgetActionReceiver : BroadcastReceiver() {

  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action != WidgetSnapshot.ACTION_TOGGLE_TODO) return
    val todoId = intent.getIntExtra(WidgetSnapshot.EXTRA_TODO_ID, -1)
    if (todoId < 0) return

    // ISO-8601 UTC, matching WidgetPendingTap.at parsing on the Dart side.
    val at = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
      timeZone = java.util.TimeZone.getTimeZone("UTC")
    }.format(Date())

    if (!WidgetSnapshot.appendPendingTap(context, todoId, at)) {
      // No snapshot yet (app never flushed) — nothing to queue into.
      return
    }
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
