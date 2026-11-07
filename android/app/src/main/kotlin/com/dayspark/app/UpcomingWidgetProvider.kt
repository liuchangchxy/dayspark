package com.dayspark.app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews

class UpcomingWidgetProvider : AppWidgetProvider() {
  override fun onUpdate(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetIds: IntArray,
  ) {
    for (id in appWidgetIds) update(context, appWidgetManager, id)
  }

  override fun onAppWidgetOptionsChanged(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetId: Int,
    newOptions: Bundle,
  ) {
    update(context, appWidgetManager, appWidgetId)
  }

  companion object {
    private fun update(
      context: Context,
      manager: AppWidgetManager,
      appWidgetId: Int,
    ) {
      WidgetSupport.render(context, manager, appWidgetId) {
        build(context, manager, appWidgetId)
      }
    }

    private fun build(
      context: Context,
      manager: AppWidgetManager,
      appWidgetId: Int,
    ): RemoteViews {
      val snapshot = WidgetSnapshot.read(context)
        ?: return WidgetSupport.fallback(context, appWidgetId)
      val ui = snapshot.ui()
      val theme = snapshot.theme()
      val size = WidgetSupport.sizeOf(manager, appWidgetId)
      val layout = if (size == WidgetSize.LARGE) {
        R.layout.widget_upcoming_large
      } else {
        R.layout.widget_upcoming_medium
      }
      val views = RemoteViews(context.packageName, layout)
      WidgetSupport.applyRoot(views, R.id.upcoming_root, theme)

      val accent = context.getColor(R.color.widget_accent)
      val secondary = context.getColor(R.color.widget_text_secondary)
      val primary = context.getColor(R.color.widget_text_primary)

      views.setTextViewText(
        R.id.upcoming_title,
        ui?.upcoming?.ifEmpty { context.getString(R.string.widget_upcoming_name) }
          ?: context.getString(R.string.widget_upcoming_name),
      )
      views.setTextViewText(
        R.id.upcoming_date,
        WidgetSupport.formatDate(
          snapshot.todayDate().ifEmpty { WidgetSupport.todayIso(context) },
        ),
      )
      WidgetSupport.textColor(views, R.id.upcoming_title, theme, "accent", accent)
      WidgetSupport.textColor(views, R.id.upcoming_date, theme, "textSecondary", secondary)

      val days = snapshot.upcomingDays()
      val groups = if (days.isNotEmpty()) {
        days
      } else {
        snapshot.upcomingItems()
          .groupBy { it.date }
          .map { (date, items) -> WidgetSnapshot.UpcomingDayRow(date, items) }
      }

      val height = WidgetSupport.dimensionsOf(manager, appWidgetId).second
      val maxRows = if (size == WidgetSize.LARGE) {
        ((height - 60) / 48).coerceIn(4, 14)
      } else {
        ((height - 50) / 48).coerceIn(2, 6)
      }
      var rowCount = 0
      val todayIso = snapshot.todayDate().ifEmpty { WidgetSupport.todayIso(context) }
      val tomorrowIso = WidgetSupport.isoDate(
        java.util.Calendar.getInstance().apply { add(java.util.Calendar.DAY_OF_YEAR, 1) }.time,
      )

      if (groups.isEmpty()) {
        WidgetSupport.setVisible(views, R.id.upcoming_empty, true)
        views.setTextViewText(
          R.id.upcoming_empty,
          ui?.noUpcoming?.ifEmpty { context.getString(R.string.widget_no_upcoming) }
            ?: context.getString(R.string.widget_no_upcoming),
        )
        WidgetSupport.textColor(views, R.id.upcoming_empty, theme, "textSecondary", secondary)
      } else {
        for (day in groups) {
          if (rowCount >= maxRows) break
          val header = RemoteViews(context.packageName, R.layout.widget_upcoming_group)
          header.setTextViewText(R.id.upcoming_group, dayLabel(day.date, todayIso, tomorrowIso, ui))
          WidgetSupport.textColor(header, R.id.upcoming_group, theme, "textSecondary", secondary)
          views.addView(R.id.upcoming_groups, header)
          rowCount++

          for (item in day.items) {
            if (rowCount >= maxRows) break
            views.addView(
              R.id.upcoming_groups,
              itemRow(context, item, theme, primary, secondary, accent),
            )
            rowCount++
          }
        }
      }

      views.setOnClickPendingIntent(
        R.id.upcoming_root,
        WidgetSupport.openUri(
          context,
          WidgetSupport.calendarUri(todayIso),
          appWidgetId + 501,
        ),
      )
      views.setOnClickPendingIntent(
        R.id.upcoming_title,
        WidgetSupport.openUri(
          context,
          WidgetSupport.calendarUri(todayIso),
          appWidgetId + 502,
        ),
      )
      return views
    }

    private fun dayLabel(
      dateIso: String,
      todayIso: String,
      tomorrowIso: String,
      ui: WidgetSnapshot.UiStrings?,
    ): String {
      if (dateIso == todayIso) return ui?.today?.ifEmpty { null } ?: "Today"
      if (dateIso == tomorrowIso) return ui?.tomorrow?.ifEmpty { null } ?: "Tomorrow"
      return if (dateIso.length == 10 && dateIso.contains('-')) {
        WidgetSupport.formatDate(dateIso)
      } else {
        dateIso
      }
    }

    private fun itemRow(
      context: Context,
      item: WidgetSnapshot.UpcomingItemRow,
      theme: WidgetSnapshot.ThemeBlock?,
      primary: Int,
      secondary: Int,
      accent: Int,
    ): RemoteViews {
      val row = RemoteViews(context.packageName, R.layout.widget_upcoming_row)
      row.setTextViewText(R.id.upcoming_time, item.time)
      row.setTextViewText(R.id.upcoming_title, item.summary)
      WidgetSupport.textColor(row, R.id.upcoming_time, theme, "textSecondary", secondary)
      WidgetSupport.textColor(row, R.id.upcoming_title, theme, "textPrimary", primary)
      val markerColor = if (item.kind == "todoDeadline") {
        secondary
      } else {
        WidgetSupport.parseColor(item.color, accent)
      }
      WidgetSupport.tint(row, R.id.upcoming_marker, markerColor)

      val uri = when {
        item.eventId != null && item.eventId > 0 -> WidgetSupport.eventUri(item.eventId)
        item.todoId != null && item.todoId > 0 -> WidgetSupport.todoUri(item.todoId)
        else -> null
      }
      if (uri != null) {
        row.setOnClickPendingIntent(
          R.id.upcoming_row,
          WidgetSupport.openUri(context, uri, uri.toString().hashCode()),
        )
      }
      return row
    }
  }
}
