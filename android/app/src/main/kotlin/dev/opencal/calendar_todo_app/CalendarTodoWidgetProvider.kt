package dev.opencal.calendar_todo_app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class CalendarTodoWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onEnabled(context: Context) {
        // Called when first widget is placed
    }

    override fun onDisabled(context: Context) {
        // Called when last widget is removed
    }

    companion object {
        private fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.calendar_todo_widget)

            // Set current date
            val dateFormat = SimpleDateFormat("MMM d, yyyy", Locale.getDefault())
            views.setTextViewText(R.id.widget_date, dateFormat.format(Date()))

            // Read data from SharedPreferences (home_widget stores data here)
            val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)

            // Parse and display events
            val eventsJson = prefs.getString("today_events", "[]") ?: "[]"
            val eventsArray = JSONArray(eventsJson)
            val hasEvents = eventsArray.length() > 0

            val eventIds = listOf(R.id.event_0, R.id.event_1, R.id.event_2)
            for (i in 0..2) {
                if (i < eventsArray.length()) {
                    val event = eventsArray.getJSONObject(i)
                    val summary = event.optString("summary", "")
                    val start = event.optString("start", "")
                    val isAllDay = event.optBoolean("isAllDay", false)
                    val displayText = if (isAllDay) "$summary (All Day)" else "$summary  $start"
                    views.setTextViewText(eventIds[i], displayText)
                    views.setViewVisibility(eventIds[i], View.VISIBLE)
                } else {
                    views.setViewVisibility(eventIds[i], View.GONE)
                }
            }
            views.setViewVisibility(R.id.no_events, if (hasEvents) View.GONE else View.VISIBLE)

            // Parse and display todos
            val todosJson = prefs.getString("pending_todos", "[]") ?: "[]"
            val todosArray = JSONArray(todosJson)
            val hasTodos = todosArray.length() > 0

            val todoCount = prefs.getString("todo_count", "0") ?: "0"
            views.setTextViewText(R.id.todo_count, "$todoCount pending")

            val todoIds = listOf(R.id.todo_0, R.id.todo_1, R.id.todo_2)
            for (i in 0..2) {
                if (i < todosArray.length()) {
                    val todo = todosArray.getJSONObject(i)
                    val summary = todo.optString("summary", "")
                    val dueDate = todo.optString("dueDate", "")
                    val displayText = if (dueDate.isNotEmpty()) "\u25CB $summary  $dueDate" else "\u25CB $summary"
                    views.setTextViewText(todoIds[i], displayText)
                    views.setViewVisibility(todoIds[i], View.VISIBLE)
                } else {
                    views.setViewVisibility(todoIds[i], View.GONE)
                }
            }
            views.setViewVisibility(R.id.no_todos, if (hasTodos) View.GONE else View.VISIBLE)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
