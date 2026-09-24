package com.dayspark.app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// Upcoming variant: compact 7-day bucket (tomorrow through day 7) straight
// from the v2 snapshot's `upcoming` block. Read-only — checkboxes and
// quick-add live on the primary widget only.
class UpcomingWidgetProvider : AppWidgetProvider() {

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
    private const val MAX_ROWS = 6

    private fun updateAppWidget(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetId: Int,
    ) {
      val views = RemoteViews(context.packageName, R.layout.upcoming_widget)
      val snapshot = WidgetSnapshot.read(context)

      views.setTextViewText(
        R.id.upcoming_date,
        SimpleDateFormat("MMM d", Locale.getDefault()).format(Date()),
      )

      if (snapshot == null) {
        views.setViewVisibility(R.id.upcoming_empty, View.VISIBLE)
        views.setTextViewText(R.id.upcoming_empty, "")
        for (rowId in ROW_IDS) {
          views.setViewVisibility(rowId, View.GONE)
        }
        appWidgetManager.updateAppWidget(appWidgetId, views)
        return
      }

      val ui = snapshot.ui()
      val theme = snapshot.theme()
      theme?.let {
        val background = it.colors["background"]
        if (background != null) {
          views.setInt(R.id.upcoming_root, "setBackgroundColor", background)
        }
        applyTextColor(views, R.id.upcoming_header, it, "accent")
        applyTextColor(views, R.id.upcoming_date, it, "textSecondary")
        applyTextColor(views, R.id.upcoming_empty, it, "textSecondary")
      }

      views.setTextViewText(R.id.upcoming_header, ui?.upcoming ?: "")
      views.setViewVisibility(R.id.upcoming_header, if (ui != null) View.VISIBLE else View.GONE)

      // Merge the two buckets into one list (events first, then todos —
      // each bucket is already time-ordered).
      val rows = mutableListOf<Pair<String, String>>()
      for (e in snapshot.upcomingEvents()) {
        if (rows.size >= MAX_ROWS) break
        val time = if (e.isAllDay) e.date else "${e.date} ${e.start}"
        rows.add(Pair(e.summary, time))
      }
      for (t in snapshot.upcomingTodos()) {
        if (rows.size >= MAX_ROWS) break
        rows.add(Pair(t.summary, t.dueDate))
      }

      for ((i, rowId) in ROW_IDS.withIndex()) {
        val textId = TEXT_IDS[i]
        val secondaryId = SECONDARY_IDS[i]
        if (i < rows.size) {
          views.setTextViewText(textId, rows[i].first)
          views.setTextViewText(secondaryId, rows[i].second)
          views.setViewVisibility(rowId, View.VISIBLE)
          theme?.let {
            applyTextColor(views, textId, it, "textPrimary")
            applyTextColor(views, secondaryId, it, "textSecondary")
          }
        } else {
          views.setViewVisibility(rowId, View.GONE)
        }
      }

      val empty = rows.isEmpty()
      views.setViewVisibility(R.id.upcoming_empty, if (empty) View.VISIBLE else View.GONE)
      if (empty && ui != null) {
        views.setTextViewText(R.id.upcoming_empty, ui.noEvents)
      }

      appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private val ROW_IDS = listOf(
      R.id.upcoming_row_0,
      R.id.upcoming_row_1,
      R.id.upcoming_row_2,
      R.id.upcoming_row_3,
      R.id.upcoming_row_4,
      R.id.upcoming_row_5,
    )
    private val TEXT_IDS = listOf(
      R.id.upcoming_text_0,
      R.id.upcoming_text_1,
      R.id.upcoming_text_2,
      R.id.upcoming_text_3,
      R.id.upcoming_text_4,
      R.id.upcoming_text_5,
    )
    private val SECONDARY_IDS = listOf(
      R.id.upcoming_secondary_0,
      R.id.upcoming_secondary_1,
      R.id.upcoming_secondary_2,
      R.id.upcoming_secondary_3,
      R.id.upcoming_secondary_4,
      R.id.upcoming_secondary_5,
    )

    private fun applyTextColor(
      views: RemoteViews,
      viewId: Int,
      theme: WidgetSnapshot.ThemeBlock,
      key: String,
    ) {
      val color = theme.colors[key] ?: return
      views.setTextColor(viewId, color)
    }
  }
}
