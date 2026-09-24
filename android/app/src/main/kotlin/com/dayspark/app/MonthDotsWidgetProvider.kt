package com.dayspark.app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.view.View
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

// Month-dots variant: a 7×N grid of day dots for the current month. Dot
// source is the snapshot's monthDots array ([[dayNumber, hasEvent]] —
// todayEvents/upcoming buckets cannot reconstruct a month, so Dart feeds
// this explicitly). Convention: has-event day = accent fill, today (no
// event) = textPrimary fill, empty day = border tint. The grid shows the
// whole month, not just the covered range.
class MonthDotsWidgetProvider : AppWidgetProvider() {

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
      val views = RemoteViews(context.packageName, R.layout.month_dots_widget)
      val snapshot = WidgetSnapshot.read(context)
      val theme = snapshot?.theme()

      val cal = Calendar.getInstance()
      val year = cal.get(Calendar.YEAR)
      val month = cal.get(Calendar.MONTH)
      val todayDay = cal.get(Calendar.DAY_OF_MONTH)
      val daysInMonth = cal.getActualMaximum(Calendar.DAY_OF_MONTH)
      cal.set(year, month, 1)
      // Sunday=1 … Saturday=7 → 0-based Monday-first grid offset (Sunday
      // lands in the last column).
      val firstDow = cal.get(Calendar.DAY_OF_WEEK)
      val leadingBlanks = (firstDow + 5) % 7

      views.setTextViewText(
        R.id.month_label,
        SimpleDateFormat("MMMM yyyy", Locale.getDefault()).format(Date()),
      )

      theme?.let {
        val background = it.colors["background"]
        if (background != null) {
          views.setInt(R.id.month_root, "setBackgroundColor", background)
        }
        applyTextColor(views, R.id.month_label, it, "accent")
      }

      val eventDays = snapshot?.monthDots() ?: emptySet<Int>()
      val accent = theme?.colors?.get("accent") ?: 0xFF1976D2.toInt()
      val todayColor = theme?.colors?.get("textPrimary") ?: 0xFF333333.toInt()
      val emptyColor = theme?.colors?.get("border") ?: 0xFFE0E0E0.toInt()

      views.removeAllViews(R.id.month_rows)

      var rowIndex = 0
      while (rowIndex < MAX_ROWS) {
        val row = RemoteViews(context.packageName, R.layout.widget_month_row)
        for (column in 0..6) {
          val dayNumber = rowIndex * 7 + column - leadingBlanks + 1
          val cell = RemoteViews(context.packageName, R.layout.widget_month_cell)
          if (dayNumber in 1..daysInMonth) {
            cell.setViewVisibility(R.id.month_dot, View.VISIBLE)
            val color = when {
              dayNumber in eventDays -> accent
              dayNumber == todayDay -> todayColor
              else -> emptyColor
            }
            cell.setInt(R.id.month_dot, "setColorFilter", color)
          } else {
            cell.setViewVisibility(R.id.month_dot, View.INVISIBLE)
          }
          row.addView(R.id.month_row_container, cell)
        }
        views.addView(R.id.month_rows, row)
        if ((rowIndex + 1) * 7 - leadingBlanks >= daysInMonth) break
        rowIndex++
      }

      appWidgetManager.updateAppWidget(appWidgetId, views)
    }

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
