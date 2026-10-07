package com.dayspark.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// Primary today widget. Renders the v3 `widget_snapshot` blob (legacy
// three-key fallback while dual-write lives), styles from the theme block,
// wires checkbox taps into the independent command queue, and deep-links the
// quick-add button through dayspark://quick-add (engine deep link →
// go_router redirect → widgetDeepLinkLocation).
class CalendarTodoWidgetProvider : AppWidgetProvider() {

  override fun onUpdate(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetIds: IntArray,
  ) {
    for (appWidgetId in appWidgetIds) {
      updateAppWidget(context, appWidgetManager, appWidgetId)
    }
  }

  companion object {
    private fun updateAppWidget(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetId: Int,
    ) {
      val views = RemoteViews(context.packageName, R.layout.calendar_todo_widget)
      val dateFormat = SimpleDateFormat("MMM d, yyyy", Locale.getDefault())
      views.setTextViewText(R.id.widget_date, dateFormat.format(Date()))

      val snapshot = WidgetSnapshot.read(context)
      if (snapshot != null) {
        renderSnapshot(context, views, snapshot)
      } else {
        renderLegacyFallback(context, views)
      }

      appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun renderSnapshot(context: Context, views: RemoteViews, snapshot: WidgetSnapshot) {
      val ui = snapshot.ui()
      val theme = snapshot.theme()

      theme?.let {
        val background = it.colors["background"]
        if (background != null) {
          views.setInt(R.id.widget_root, "setBackgroundColor", background)
        }
        applyTextColor(views, R.id.widget_events_header, it, "accent")
        applyTextColor(views, R.id.widget_todos_header, it, "accent")
        applyTextColor(views, R.id.widget_date, it, "textSecondary")
        applyTextColor(views, R.id.todo_count, it, "textSecondary")
        applyTextColor(views, R.id.no_events, it, "textSecondary")
        applyTextColor(views, R.id.no_todos, it, "textSecondary")
        applyTextColor(views, R.id.widget_quick_add, it, "accent")
      }

      val hasUi = ui != null
      views.setTextViewText(R.id.widget_events_header, ui?.todayEventsHeader ?: "")
      views.setTextViewText(R.id.widget_todos_header, ui?.todos ?: "")
      views.setTextViewText(
        R.id.widget_quick_add,
        ui?.quickAdd ?: "",
      )
      views.setViewVisibility(R.id.widget_quick_add, if (hasUi) View.VISIBLE else View.GONE)

      // Timeline (EventOccurrence + TaskAllocation) (≤3 slots)
      val timeline = snapshot.todayTimeline()
      val eventIds = listOf(R.id.event_0, R.id.event_1, R.id.event_2)
      for (i in 0..2) {
        if (i < timeline.size) {
          val item = timeline[i]
          val timeStr = if (item.isAllDay) {
            ui?.allDay ?: ""
          } else if (item.end.isNotEmpty()) {
            "${item.start} - ${item.end}"
          } else {
            item.start
          }
          val text = if (timeStr.isNotEmpty()) "${item.summary}  $timeStr" else item.summary
          views.setTextViewText(eventIds[i], text)
          views.setViewVisibility(eventIds[i], View.VISIBLE)
          theme?.let { applyTextColor(views, eventIds[i], it, "textPrimary") }
        } else {
          views.setViewVisibility(eventIds[i], View.GONE)
        }
      }
      views.setViewVisibility(
        R.id.no_events,
        if (timeline.isEmpty() && hasUi) View.VISIBLE else View.GONE,
      )
      if (hasUi) views.setTextViewText(R.id.no_events, ui!!.noEvents)

      // Actions (TodoDeadline + TaskInstance) (≤3 slots) with optimistic state
      val actions = snapshot.todayActions()
      val pendingTargets = WidgetSnapshot.readPendingTargets(context)
      views.setTextViewText(R.id.todo_count, ui?.pendingCount ?: "${snapshot.todoCount()}")
      val rowIds = listOf(R.id.todo_row_0, R.id.todo_row_1, R.id.todo_row_2)
      val checkIds = listOf(R.id.todo_check_0, R.id.todo_check_1, R.id.todo_check_2)
      val textIds = listOf(R.id.todo_text_0, R.id.todo_text_1, R.id.todo_text_2)
      val dueIds = listOf(R.id.todo_due_0, R.id.todo_due_1, R.id.todo_due_2)

      for (i in 0..2) {
        if (i < actions.size) {
          val a = actions[i]
          views.setTextViewText(textIds[i], a.summary)
          val secondaryText = a.deadline ?: a.displayTime ?: ""
          views.setTextViewText(dueIds[i], secondaryText)
          views.setViewVisibility(dueIds[i], if (secondaryText.isEmpty()) View.GONE else View.VISIBLE)
          views.setViewVisibility(rowIds[i], View.VISIBLE)
          theme?.let {
            applyTextColor(views, textIds[i], it, "textPrimary")
            applyTextColor(views, dueIds[i], it, "textSecondary")
          }

          val isPending = if (a.target == "taskInstance") {
            val occ = a.occurrenceId ?: ""
            pendingTargets.instanceKeys.contains("${a.todoId}:$occ")
          } else {
            pendingTargets.todoIds.contains(a.todoId)
          }

          if (a.todoId > 0) {
            views.setViewVisibility(checkIds[i], View.VISIBLE)
            views.setBoolean(checkIds[i], "setChecked", isPending)
            views.setOnClickPendingIntent(
              rowIds[i],
              actionPendingIntent(context, a),
            )
          } else {
            views.setViewVisibility(checkIds[i], View.GONE)
            views.setOnClickPendingIntent(rowIds[i], null)
          }
        } else {
          views.setViewVisibility(rowIds[i], View.GONE)
        }
      }
      views.setViewVisibility(
        R.id.no_todos,
        if (actions.isEmpty() && hasUi) View.VISIBLE else View.GONE,
      )
      if (hasUi) views.setTextViewText(R.id.no_todos, ui!!.allDone)

      views.setOnClickPendingIntent(R.id.widget_quick_add, quickAddPendingIntent(context))
    }

    private fun actionPendingIntent(context: Context, action: WidgetSnapshot.ActionRow): PendingIntent {
      val intent = Intent(context, WidgetActionReceiver::class.java).apply {
        this.action = WidgetSnapshot.ACTION_COMPLETE_ACTION
        val occPart = action.occurrenceId ?: "single"
        data = Uri.parse("dayspark://widget-action/${action.target}/${action.todoId}/$occPart")
        putExtra(WidgetSnapshot.EXTRA_TARGET, action.target)
        putExtra(WidgetSnapshot.EXTRA_TODO_ID, action.todoId)
        if (!action.todoSyncId.isNullOrEmpty()) {
          putExtra(WidgetSnapshot.EXTRA_TODO_SYNC_ID, action.todoSyncId)
        }
        if (!action.occurrenceId.isNullOrEmpty()) {
          putExtra(WidgetSnapshot.EXTRA_OCCURRENCE_ID, action.occurrenceId)
        }
      }
      val requestCode = (action.todoId.hashCode() * 31 + (action.occurrenceId?.hashCode() ?: 0)) and 0x7FFFFFFF
      return PendingIntent.getBroadcast(
        context,
        requestCode,
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
      )
    }

    private fun quickAddPendingIntent(context: Context): PendingIntent {
      val intent = Intent(Intent.ACTION_VIEW, Uri.parse("dayspark://quick-add")).apply {
        flags =
          Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_CLEAR_TOP or
            Intent.FLAG_ACTIVITY_SINGLE_TOP
      }
      return PendingIntent.getActivity(
        context,
        QUICK_ADD_REQUEST_CODE,
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
      )
    }

    private const val QUICK_ADD_REQUEST_CODE = 1001

    private fun applyTextColor(
      views: RemoteViews,
      viewId: Int,
      theme: WidgetSnapshot.ThemeBlock,
      key: String,
    ) {
      val color = theme.colors[key] ?: return
      views.setTextColor(viewId, color)
    }

    // Downlevel window only: app predates widget_snapshot (or the blob is
    // corrupt).
    private fun renderLegacyFallback(context: Context, views: RemoteViews) {
      val prefs = WidgetSnapshot.prefs(context)
      views.setViewVisibility(R.id.widget_events_header, View.GONE)
      views.setViewVisibility(R.id.widget_todos_header, View.GONE)
      views.setViewVisibility(R.id.widget_quick_add, View.GONE)
      views.setViewVisibility(R.id.no_events, View.GONE)
      views.setViewVisibility(R.id.no_todos, View.GONE)

      val count = prefs.getInt("todo_count", 0)
      views.setTextViewText(R.id.todo_count, if (count > 0) "$count" else "")

      for (id in listOf(R.id.event_0, R.id.event_1, R.id.event_2)) {
        views.setViewVisibility(id, View.GONE)
      }
      for (id in listOf(R.id.todo_row_0, R.id.todo_row_1, R.id.todo_row_2)) {
        views.setViewVisibility(id, View.GONE)
      }
    }
  }
}
