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

// Primary today widget. Renders the v2 `widget_snapshot` blob (legacy
// three-key fallback while dual-write lives), styles from the theme block,
// wires checkbox taps into the pendingTaps queue, and deep-links the
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

      // ui block absent (corrupt partial snapshot): hide section chrome
      // instead of leaking hardcoded copy — data rows still render.
      val hasUi = ui != null
      views.setTextViewText(R.id.widget_events_header, ui?.todayEventsHeader ?: "")
      views.setTextViewText(R.id.widget_todos_header, ui?.todos ?: "")
      views.setTextViewText(
        R.id.widget_quick_add,
        ui?.quickAdd ?: "",
      )
      views.setViewVisibility(R.id.widget_quick_add, if (hasUi) View.VISIBLE else View.GONE)

      // Events (≤3 slots).
      val events = snapshot.todayEvents()
      val eventIds = listOf(R.id.event_0, R.id.event_1, R.id.event_2)
      for (i in 0..2) {
        if (i < events.size) {
          val e = events[i]
          val text = if (e.isAllDay) {
            "${e.summary}  ${ui?.allDay ?: ""}"
          } else {
            "${e.summary}  ${e.start}"
          }
          views.setTextViewText(eventIds[i], text)
          views.setViewVisibility(eventIds[i], View.VISIBLE)
          theme?.let { applyTextColor(views, eventIds[i], it, "textPrimary") }
        } else {
          views.setViewVisibility(eventIds[i], View.GONE)
        }
      }
      views.setViewVisibility(
        R.id.no_events,
        if (events.isEmpty() && hasUi) View.VISIBLE else View.GONE,
      )
      if (hasUi) views.setTextViewText(R.id.no_events, ui!!.noEvents)

      // Todos (≤3 slots) with optimistic checkbox state.
      val todos = snapshot.pendingTodos()
      val checkedIds = snapshot.pendingTapTodoIds()
      views.setTextViewText(R.id.todo_count, ui?.pendingCount ?: "${snapshot.todoCount()}")
      val rowIds = listOf(R.id.todo_row_0, R.id.todo_row_1, R.id.todo_row_2)
      val checkIds = listOf(R.id.todo_check_0, R.id.todo_check_1, R.id.todo_check_2)
      val textIds = listOf(R.id.todo_text_0, R.id.todo_text_1, R.id.todo_text_2)
      val dueIds = listOf(R.id.todo_due_0, R.id.todo_due_1, R.id.todo_due_2)
      for (i in 0..2) {
        if (i < todos.size) {
          val t = todos[i]
          views.setTextViewText(textIds[i], t.summary)
          views.setTextViewText(dueIds[i], t.dueDate)
          views.setViewVisibility(dueIds[i], if (t.dueDate.isEmpty()) View.GONE else View.VISIBLE)
          views.setViewVisibility(rowIds[i], View.VISIBLE)
          theme?.let {
            applyTextColor(views, textIds[i], it, "textPrimary")
            applyTextColor(views, dueIds[i], it, "textSecondary")
          }

          val todoId = t.id
          if (todoId != null) {
            views.setViewVisibility(checkIds[i], View.VISIBLE)
            views.setBoolean(checkIds[i], "setChecked", checkedIds.contains(todoId))
            views.setOnClickPendingIntent(
              rowIds[i],
              checkPendingIntent(context, todoId),
            )
          } else {
            // Snapshot without ids: render row, no tap target.
            views.setViewVisibility(checkIds[i], View.GONE)
            views.setOnClickPendingIntent(rowIds[i], null)
          }
        } else {
          views.setViewVisibility(rowIds[i], View.GONE)
        }
      }
      views.setViewVisibility(
        R.id.no_todos,
        if (todos.isEmpty() && hasUi) View.VISIBLE else View.GONE,
      )
      if (hasUi) views.setTextViewText(R.id.no_todos, ui!!.allDone)

      views.setOnClickPendingIntent(R.id.widget_quick_add, quickAddPendingIntent(context))
    }

    // Last-wins queue append happens in the receiver; the redraw that
    // follows this broadcast reads pendingTaps back for the checked mark.
    private fun checkPendingIntent(context: Context, todoId: Int): PendingIntent {
      val intent = Intent(context, WidgetActionReceiver::class.java).apply {
        action = WidgetSnapshot.ACTION_TOGGLE_TODO
        // Unique data URI per todo keeps the system from collapsing the
        // PendingIntents of different rows into one.
        data = Uri.parse("dayspark://widget-check/$todoId")
        putExtra(WidgetSnapshot.EXTRA_TODO_ID, todoId)
      }
      return PendingIntent.getBroadcast(
        context,
        todoId,
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
    // corrupt). Legacy keys carry data but no ui/theme/id — section chrome
    // and checkboxes are hidden rather than filled with hardcoded copy.
    private fun renderLegacyFallback(context: Context, views: RemoteViews) {
      val prefs = WidgetSnapshot.prefs(context)
      views.setViewVisibility(R.id.widget_events_header, View.GONE)
      views.setViewVisibility(R.id.widget_todos_header, View.GONE)
      views.setViewVisibility(R.id.widget_quick_add, View.GONE)
      views.setViewVisibility(R.id.no_events, View.GONE)
      views.setViewVisibility(R.id.no_todos, View.GONE)

      val eventsJson = prefs.getString("today_events", "[]") ?: "[]"
      val eventsArray = try {
        org.json.JSONArray(eventsJson)
      } catch (e: Exception) {
        org.json.JSONArray()
      }
      val eventIds = listOf(R.id.event_0, R.id.event_1, R.id.event_2)
      for (i in 0..2) {
        if (i < eventsArray.length()) {
          val event = eventsArray.getJSONObject(i)
          val summary = event.optString("summary", "")
          val start = event.optString("start", "")
          val isAllDay = event.optString("isAllDay", "false") == "true"
          // No ui block in legacy mode — keep raw fields, no formatted copy.
          val text = if (isAllDay && start.isEmpty()) summary else "$summary  $start"
          views.setTextViewText(eventIds[i], text)
          views.setViewVisibility(eventIds[i], View.VISIBLE)
        } else {
          views.setViewVisibility(eventIds[i], View.GONE)
        }
      }

      val todosJson = prefs.getString("pending_todos", "[]") ?: "[]"
      val todosArray = try {
        org.json.JSONArray(todosJson)
      } catch (e: Exception) {
        org.json.JSONArray()
      }
      val todoCount = prefs.getString("todo_count", "0") ?: "0"
      views.setTextViewText(R.id.todo_count, todoCount)
      val rowIds = listOf(R.id.todo_row_0, R.id.todo_row_1, R.id.todo_row_2)
      val checkIds = listOf(R.id.todo_check_0, R.id.todo_check_1, R.id.todo_check_2)
      val textIds = listOf(R.id.todo_text_0, R.id.todo_text_1, R.id.todo_text_2)
      val dueIds = listOf(R.id.todo_due_0, R.id.todo_due_1, R.id.todo_due_2)
      for (i in 0..2) {
        if (i < todosArray.length()) {
          val todo = todosArray.getJSONObject(i)
          views.setTextViewText(textIds[i], todo.optString("summary", ""))
          val dueDate = todo.optString("dueDate", "")
          views.setTextViewText(dueIds[i], dueDate)
          views.setViewVisibility(dueIds[i], if (dueDate.isEmpty()) View.GONE else View.VISIBLE)
          views.setViewVisibility(checkIds[i], View.GONE)
          views.setViewVisibility(rowIds[i], View.VISIBLE)
          views.setOnClickPendingIntent(rowIds[i], null)
        } else {
          views.setViewVisibility(rowIds[i], View.GONE)
        }
      }
    }
  }
}
