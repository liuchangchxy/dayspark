package com.dayspark.app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import java.text.DateFormatSymbols
import java.util.Calendar
import java.util.Locale

class CalendarWidgetProvider : AppWidgetProvider() {
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
    private val WEEKDAY_IDS = listOf(
      R.id.weekday_0,
      R.id.weekday_1,
      R.id.weekday_2,
      R.id.weekday_3,
      R.id.weekday_4,
      R.id.weekday_5,
      R.id.weekday_6,
    )

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
      val theme = snapshot?.theme()
      val size = WidgetSupport.sizeOf(manager, appWidgetId)
      val large = size == WidgetSize.LARGE
      val layout = if (large) {
        R.layout.widget_calendar_large
      } else {
        R.layout.widget_calendar_medium
      }
      val views = RemoteViews(context.packageName, layout)
      WidgetSupport.applyRoot(views, R.id.calendar_root, theme)

      val primary = context.getColor(R.color.widget_text_primary)
      val secondary = context.getColor(R.color.widget_text_secondary)
      val accent = context.getColor(R.color.widget_accent)

      val now = Calendar.getInstance()
      val month = snapshot?.month()
      val year = month?.year?.takeIf { it > 0 } ?: now.get(Calendar.YEAR)
      val monthNumber = month?.month?.takeIf { it in 1..12 }
        ?: (now.get(Calendar.MONTH) + 1)
      val daysInMonth = Calendar.getInstance().apply {
        set(year, monthNumber - 1, 1)
      }.getActualMaximum(Calendar.DAY_OF_MONTH)
      val firstWeekday = month?.firstWeekday?.takeIf { it in 1..7 }
        ?: mondayFirstWeekday(year, monthNumber)
      val isCurrentMonth = year == now.get(Calendar.YEAR) &&
        monthNumber == (now.get(Calendar.MONTH) + 1)
      val todayDay = if (isCurrentMonth) now.get(Calendar.DAY_OF_MONTH) else -1
      val marks = month?.days?.associateBy { it.day } ?: emptyMap()

      views.setTextViewText(
        R.id.calendar_title,
        WidgetSupport.monthTitle(year, monthNumber),
      )
      WidgetSupport.textColor(views, R.id.calendar_title, theme, "accent", accent)

      views.addView(R.id.calendar_weekdays, weekdayHeader(context, theme, secondary))
      views.removeAllViews(R.id.calendar_grid)

      val leading = firstWeekday - 1
      val total = leading + daysInMonth
      val cellLayout = if (large) {
        R.layout.widget_calendar_cell
      } else {
        R.layout.widget_calendar_cell_small
      }
      var row = 0
      while (row * 7 < total && row < 6) {
        val rowView = RemoteViews(context.packageName, R.layout.widget_calendar_row)
        for (column in 0..6) {
          val day = row * 7 + column - leading + 1
          val cell = RemoteViews(context.packageName, cellLayout)
          if (day in 1..daysInMonth) {
            val mark = marks[day]
            val isToday = day == todayDay
            cell.setTextViewText(R.id.calendar_day, day.toString())
            WidgetSupport.textColor(
              cell,
              R.id.calendar_day,
              theme,
              if (isToday) "accent" else "textPrimary",
              if (isToday) accent else primary,
            )

            val dotColor = when {
              mark?.hasEvent == true || mark?.hasAllocation == true ->
                WidgetSupport.parseColor(mark?.colors?.firstOrNull(), accent)
              mark?.hasTodo == true -> secondary
              else -> null
            }
            if (dotColor != null) {
              cell.setViewVisibility(R.id.calendar_dot, View.VISIBLE)
              WidgetSupport.tint(cell, R.id.calendar_dot, dotColor)
            } else {
              cell.setViewVisibility(R.id.calendar_dot, View.INVISIBLE)
            }

            val dateIso = WidgetSupport.isoDate(
              Calendar.getInstance().apply {
                set(year, monthNumber - 1, day, 0, 0, 0)
                set(Calendar.MILLISECOND, 0)
              }.time,
            )
            cell.setOnClickPendingIntent(
              R.id.calendar_cell,
              WidgetSupport.openUri(
                context,
                WidgetSupport.calendarUri(dateIso),
                dateIso.hashCode(),
              ),
            )
          } else {
            cell.setTextViewText(R.id.calendar_day, "")
            cell.setViewVisibility(R.id.calendar_dot, View.INVISIBLE)
          }
          rowView.addView(R.id.calendar_row, cell)
        }
        views.addView(R.id.calendar_grid, rowView)
        row++
      }

      views.setOnClickPendingIntent(
        R.id.calendar_add,
        WidgetSupport.openUri(
          context,
          WidgetSupport.newEventUri(
            WidgetSupport.isoDate(
              Calendar.getInstance().apply {
                set(year, monthNumber - 1, todayDay.takeIf { it > 0 } ?: 1, 0, 0, 0)
                set(Calendar.MILLISECOND, 0)
              }.time,
            ),
          ),
          appWidgetId + 601,
        ),
      )
      WidgetSupport.textColor(views, R.id.calendar_add, theme, "accent", accent)

      if (large) {
        renderTodaySummary(context, views, snapshot, theme, primary, secondary, accent)
        views.setTextViewText(
          R.id.calendar_summary_title,
          snapshot?.ui()?.today?.ifEmpty { null }
            ?: context.getString(R.string.widget_today),
        )
        WidgetSupport.textColor(
          views,
          R.id.calendar_summary_title,
          theme,
          "textSecondary",
          secondary,
        )
      }

      views.setOnClickPendingIntent(
        R.id.calendar_title,
        WidgetSupport.openUri(
          context,
          WidgetSupport.calendarUri(WidgetSupport.todayIso(context)),
          appWidgetId + 602,
        ),
      )
      return views
    }

    private fun renderTodaySummary(
      context: Context,
      views: RemoteViews,
      snapshot: WidgetSnapshot?,
      theme: WidgetSnapshot.ThemeBlock?,
      primary: Int,
      secondary: Int,
      accent: Int,
    ) {
      views.removeAllViews(R.id.calendar_summary)
      val ui = snapshot?.ui()
      val timeline = snapshot?.todayTimeline() ?: emptyList()
      val actions = snapshot?.todayActions() ?: emptyList()
      val rows = mutableListOf<RemoteViews>()

      for (item in timeline.take(4)) {
        val row = RemoteViews(context.packageName, R.layout.widget_calendar_summary_row)
        row.setTextViewText(
          R.id.calendar_summary_time,
          WidgetSupport.formatTimeRange(
            item.start,
            item.end,
            item.isAllDay,
            ui?.allDay ?: "",
          ),
        )
        row.setTextViewText(R.id.calendar_summary_title, item.summary)
        WidgetSupport.textColor(
          row,
          R.id.calendar_summary_time,
          theme,
          "textSecondary",
          secondary,
        )
        WidgetSupport.textColor(
          row,
          R.id.calendar_summary_title,
          theme,
          "textPrimary",
          primary,
        )
        val uri = when {
          item.kind == "taskAllocation" && (item.todoId ?: -1) > 0 ->
            WidgetSupport.todoUri(item.todoId!!)
          (item.eventId ?: -1) > 0 -> WidgetSupport.eventUri(item.eventId!!)
          else -> null
        }
        if (uri != null) {
          row.setOnClickPendingIntent(
            R.id.calendar_summary_row,
            WidgetSupport.openUri(context, uri, uri.toString().hashCode()),
          )
        }
        rows.add(row)
      }

      for (action in actions.take(4)) {
        val row = RemoteViews(context.packageName, R.layout.widget_calendar_summary_row)
        row.setTextViewText(
          R.id.calendar_summary_time,
          action.deadline?.ifEmpty { null } ?: action.displayTime ?: "",
        )
        row.setTextViewText(R.id.calendar_summary_title, action.summary)
        WidgetSupport.textColor(
          row,
          R.id.calendar_summary_time,
          theme,
          "textSecondary",
          secondary,
        )
        WidgetSupport.textColor(
          row,
          R.id.calendar_summary_title,
          theme,
          "textPrimary",
          primary,
        )
        if (action.todoId > 0) {
          row.setOnClickPendingIntent(
            R.id.calendar_summary_row,
            WidgetSupport.openUri(
              context,
              WidgetSupport.todoUri(action.todoId),
              action.todoId + 701,
            ),
          )
        }
        rows.add(row)
      }

      if (rows.isEmpty()) {
        val row = RemoteViews(context.packageName, R.layout.widget_calendar_summary_row)
        row.setTextViewText(R.id.calendar_summary_time, "")
        row.setTextViewText(
          R.id.calendar_summary_title,
          ui?.noPlans?.ifEmpty { null } ?: context.getString(R.string.widget_no_plans),
        )
        WidgetSupport.textColor(
          row,
          R.id.calendar_summary_title,
          theme,
          "textSecondary",
          secondary,
        )
        rows.add(row)
      }

      for (row in rows) views.addView(R.id.calendar_summary, row)
    }

    private fun weekdayHeader(
      context: Context,
      theme: WidgetSnapshot.ThemeBlock?,
      secondary: Int,
    ): RemoteViews {
      val header = RemoteViews(context.packageName, R.layout.widget_calendar_weekdays)
      val symbols = DateFormatSymbols(Locale.getDefault()).shortWeekdays
      val mondayFirst = intArrayOf(2, 3, 4, 5, 6, 7, 1)
      for (i in mondayFirst.indices) {
        val label = symbols.getOrNull(mondayFirst[i]) ?: ""
        header.setTextViewText(WEEKDAY_IDS[i], label)
        WidgetSupport.textColor(header, WEEKDAY_IDS[i], theme, "textSecondary", secondary)
      }
      return header
    }

    private fun mondayFirstWeekday(year: Int, month: Int): Int {
      val dow = Calendar.getInstance().apply {
        set(year, month - 1, 1)
      }.get(Calendar.DAY_OF_WEEK)
      return ((dow + 5) % 7) + 1
    }
  }
}
