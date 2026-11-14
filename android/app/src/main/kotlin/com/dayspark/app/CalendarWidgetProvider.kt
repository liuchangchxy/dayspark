package com.dayspark.app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import java.text.DateFormatSymbols
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

// Calendar / 月历: current month plus the selected day's items. Tapping a day
// only moves `selectedDate` inside the widget; it never opens the App.
class CalendarWidgetProvider : AppWidgetProvider() {
  override fun onUpdate(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetIds: IntArray,
  ) {
    for (id in appWidgetIds) updateWidget(context, appWidgetManager, id)
  }

  override fun onAppWidgetOptionsChanged(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetId: Int,
    newOptions: Bundle,
  ) {
    updateWidget(context, appWidgetManager, appWidgetId)
  }

  override fun onDeleted(context: Context, appWidgetIds: IntArray) {
    for (id in appWidgetIds) WidgetStateStore.clear(context, id)
  }

  override fun onReceive(context: Context, intent: Intent) {
    super.onReceive(context, intent)
    if (intent.action in CLOCK_ACTIONS) {
      val manager = AppWidgetManager.getInstance(context)
      for (id in manager.getAppWidgetIds(ComponentName(context, CalendarWidgetProvider::class.java))) {
        updateWidget(context, manager, id)
      }
    }
  }

  companion object {
    private val CLOCK_ACTIONS = setOf(
      Intent.ACTION_DATE_CHANGED,
      Intent.ACTION_TIME_CHANGED,
      Intent.ACTION_TIMEZONE_CHANGED,
    )

    private val WEEKDAY_IDS = listOf(
      R.id.weekday_0,
      R.id.weekday_1,
      R.id.weekday_2,
      R.id.weekday_3,
      R.id.weekday_4,
      R.id.weekday_5,
      R.id.weekday_6,
    )

    fun updateWidget(
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
      val ui = snapshot?.ui()
      val theme = snapshot?.theme()
      val height = WidgetSupport.dimensionsOf(manager, appWidgetId).second
      val large = WidgetSupport.calendarIsLarge(height)
      val layout = if (large) {
        R.layout.widget_calendar_large
      } else {
        R.layout.widget_calendar_medium
      }
      val views = RemoteViews(context.packageName, layout)
      WidgetSupport.applyRoot(context, views, R.id.calendar_root, theme)
      if (large) {
        views.setInt(
          R.id.calendar_divider,
          "setBackgroundColor",
          WidgetSupport.borderColor(context, theme),
        )
      }

      // Every visible ink must come from the snapshot when one exists. The
      // @color fallbacks below are overridden in values-night, so using them
      // beside a snapshot-driven root puts a light-theme grid on dark paper
      // whenever the app theme and the system disagree.
      val primary = theme?.colors?.get("textPrimary")
        ?: context.getColor(R.color.widget_text_primary)
      val secondary = theme?.colors?.get("textSecondary")
        ?: context.getColor(R.color.widget_text_secondary)
      val accent = theme?.colors?.get("accent") ?: context.getColor(R.color.widget_accent)
      val error = theme?.colors?.get("error") ?: context.getColor(R.color.widget_error)

      val now = Calendar.getInstance()
      val todayIso = WidgetStateStore.todayIso()
      val state = WidgetStateStore.read(context, appWidgetId)
      val selectedIso = WidgetStateStore.normalizedSelectedDate(state)
      val selectedDate = parseIso(selectedIso) ?: Date()

      val snapshotMonth = snapshot?.month()
      val snapshotIsCurrent = snapshotMonth != null &&
        snapshotMonth.year == now.get(Calendar.YEAR) &&
        snapshotMonth.month == (now.get(Calendar.MONTH) + 1)
      val snapshotStale = snapshot?.todayIso() != todayIso
      val staleSuffix = if (snapshotIsCurrent && snapshotStale) {
        " · ${ui?.stale ?: context.getString(R.string.widget_stale)}"
      } else {
        ""
      }
      val year = if (snapshotIsCurrent) snapshotMonth!!.year else now.get(Calendar.YEAR)
      val monthNumber = if (snapshotIsCurrent) snapshotMonth!!.month else now.get(Calendar.MONTH) + 1
      val daysInMonth = Calendar.getInstance().apply {
        set(year, monthNumber - 1, 1)
      }.getActualMaximum(Calendar.DAY_OF_MONTH)
      val firstWeekday = if (snapshotIsCurrent) {
        snapshotMonth!!.firstWeekday.takeIf { it in 1..7 } ?: mondayFirstWeekday(year, monthNumber)
      } else {
        mondayFirstWeekday(year, monthNumber)
      }
      val marks = if (snapshotIsCurrent) {
        snapshotMonth!!.days.associateBy { it.day }
      } else {
        emptyMap()
      }
      val compact = !large && height > 0 && height < 230
      val dayMode = compact && state.calendarMode == "day"

      views.setTextViewText(R.id.calendar_title, WidgetSupport.monthTitle(year, monthNumber))
      WidgetSupport.textColor(views, R.id.calendar_title, theme, "accent", accent)

      val calendarUri = WidgetSupport.calendarUri(selectedIso)
      views.setOnClickPendingIntent(
        R.id.calendar_root,
        WidgetSupport.openUri(context, calendarUri, appWidgetId + 800),
      )
      views.setOnClickPendingIntent(
        R.id.calendar_title,
        WidgetSupport.openUri(context, calendarUri, appWidgetId + 801),
      )
      views.setOnClickPendingIntent(
        R.id.calendar_add,
        WidgetSupport.openUri(
          context,
          WidgetSupport.newEventUri(selectedIso),
          appWidgetId + 802,
        ),
      )
      WidgetSupport.textColor(views, R.id.calendar_add, theme, "accent", accent)

      views.setTextViewText(R.id.calendar_today, ui?.today ?: context.getString(R.string.widget_today))
      WidgetSupport.textColor(views, R.id.calendar_today, theme, "accent", accent)
      views.setViewVisibility(
        R.id.calendar_today,
        if (selectedIso != todayIso) View.VISIBLE else View.GONE,
      )
      views.setOnClickPendingIntent(
        R.id.calendar_today,
        WidgetSupport.stateIntent(
          context,
          appWidgetId,
          WidgetActionReceiver.ACTION_CALENDAR_TODAY,
        ),
      )

      views.removeAllViews(R.id.calendar_weekdays)
      views.addView(R.id.calendar_weekdays, weekdayHeader(context, theme, secondary))
      views.removeAllViews(R.id.calendar_grid)

      val leading = firstWeekday - 1
      val total = leading + daysInMonth
      val weekRows = (total + 6) / 7
      val cellDp = WidgetSupport.calendarCellHeightDp(height, weekRows, large)
      val cellLayout = WidgetSupport.calendarCellLayout(cellDp)
      var row = 0
      while (row * 7 < total && row < 6) {
        val rowView = RemoteViews(context.packageName, R.layout.widget_calendar_row)
        for (column in 0..6) {
          val day = row * 7 + column - leading + 1
          val cell = RemoteViews(context.packageName, cellLayout)
          if (day in 1..daysInMonth) {
            val mark = marks[day]
            val dateIso = isoDate(year, monthNumber, day)
            val isToday = dateIso == todayIso
            val isSelected = dateIso == selectedIso
            cell.setTextViewText(R.id.calendar_day, day.toString())
            cell.setTextColor(
              R.id.calendar_day,
              when {
                isSelected || isToday -> accent
                else -> primary
              },
            )
            if (isSelected) {
              val washAlpha = if (theme?.dark == true) 41 else 26
              cell.setInt(
                R.id.calendar_cell,
                "setBackgroundColor",
                Color.argb(washAlpha, Color.red(accent), Color.green(accent), Color.blue(accent)),
              )
            } else {
              cell.setInt(R.id.calendar_cell, "setBackgroundColor", Color.TRANSPARENT)
            }

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

            cell.setOnClickPendingIntent(
              R.id.calendar_cell,
              WidgetSupport.stateIntent(
                context,
                appWidgetId,
                WidgetActionReceiver.ACTION_SET_CALENDAR_DATE,
                WidgetActionReceiver.EXTRA_CALENDAR_DATE,
                dateIso,
              ).let { intent ->
                if (compact && !dayMode) {
                  stateIntentEnterDay(context, appWidgetId, dateIso)
                } else {
                  intent
                }
              },
            )
          } else {
            cell.setTextViewText(R.id.calendar_day, "")
            cell.setViewVisibility(R.id.calendar_dot, View.INVISIBLE)
            cell.setInt(R.id.calendar_cell, "setBackgroundColor", Color.TRANSPARENT)
          }
          rowView.addView(R.id.calendar_row, cell)
        }
        views.addView(R.id.calendar_grid, rowView)
        row++
      }

      val dayBarVisible = dayMode
      views.setViewVisibility(
        R.id.calendar_month_page,
        if (dayMode) View.GONE else View.VISIBLE,
      )
      if (large) {
        views.setViewVisibility(R.id.calendar_day_bar, View.GONE)
      } else {
        views.setViewVisibility(
          R.id.calendar_day_bar,
          if (dayBarVisible) View.VISIBLE else View.GONE,
        )
        if (dayBarVisible) {
          val back = WidgetSupport.stateIntent(
            context,
            appWidgetId,
            WidgetActionReceiver.ACTION_SET_CALENDAR_MODE,
            WidgetActionReceiver.EXTRA_CALENDAR_MODE,
            "month",
          )
          views.setTextViewText(
            R.id.calendar_back_month,
            "‹ ${ui?.backToMonth ?: context.getString(R.string.widget_back_to_month)}",
          )
          WidgetSupport.textColor(views, R.id.calendar_back_month, theme, "accent", accent)
          views.setOnClickPendingIntent(R.id.calendar_back_month, back)
          views.setTextViewText(
            R.id.calendar_day_title,
            WidgetSupport.formatDayTitle(selectedIso) + staleSuffix,
          )
          WidgetSupport.textColor(views, R.id.calendar_day_title, theme, "textPrimary", primary)
        }
      }

      val showSummaryTitle = !dayMode
      views.setViewVisibility(
        R.id.calendar_summary_title,
        if (showSummaryTitle) View.VISIBLE else View.GONE,
      )
      views.removeAllViews(R.id.calendar_summary)

      val selectedDay = Calendar.getInstance().apply { time = selectedDate }.get(Calendar.DAY_OF_MONTH)
      val dayMark = marks[selectedDay]
      // Exactly the rows the card can hold: the old nominal 2/6 rows were added
      // regardless and the overflow was silently clipped by the launcher.
      val maxRows = if (dayMode) {
        WidgetSupport.calendarDayRows(height, large)
      } else {
        WidgetSupport.calendarSummaryRows(height, cellDp, weekRows, large)
      }
      val showEmpty = dayMark == null || dayMark.items.isEmpty()
      if (!dayMode) {
        views.setTextViewText(
          R.id.calendar_summary_title,
          WidgetSupport.formatDayTitle(selectedIso) + staleSuffix,
        )
        WidgetSupport.textColor(
          views,
          R.id.calendar_summary_title,
          theme,
          "textSecondary",
          secondary,
        )
      }

      val openCalendar = WidgetSupport.openUri(context, calendarUri, appWidgetId + 803)
      if (maxRows == 0) {
        // A 4x4 pin at its minimum height fits the grid and nothing else; a
        // half-visible row is worse than none.
        views.setViewVisibility(R.id.calendar_empty, View.GONE)
      } else if (showEmpty) {
        views.setViewVisibility(R.id.calendar_empty, View.VISIBLE)
        views.setTextViewText(
          R.id.calendar_empty,
          when {
            !snapshotIsCurrent -> ui?.openToUpdate ?: context.getString(R.string.widget_open_to_update)
            else -> ui?.selectedDayEmpty ?: context.getString(R.string.widget_selected_day_empty)
          },
        )
        WidgetSupport.textColor(views, R.id.calendar_empty, theme, "textSecondary", secondary)
        views.setOnClickPendingIntent(R.id.calendar_empty, openCalendar)
      } else {
        views.setViewVisibility(R.id.calendar_empty, View.GONE)
        val items = dayMark!!.items
        // When the list is truncated one of the visible rows becomes "N more",
        // so it still fits the height that was measured.
        val itemRows = if (dayMark.itemCount > maxRows && maxRows >= 2) maxRows - 1 else maxRows
        val emitted = minOf(items.size, itemRows)
        for (index in 0 until emitted) {
          views.addView(
            R.id.calendar_summary,
            summaryRow(context, items[index], theme, primary, secondary, error, accent, ui, appWidgetId),
          )
        }
        val hidden = dayMark.itemCount - emitted
        if (hidden > 0 && maxRows >= 2) {
          val more = RemoteViews(context.packageName, R.layout.widget_calendar_summary_row)
          more.setViewVisibility(R.id.calendar_summary_marker, View.GONE)
          more.setTextViewText(R.id.calendar_summary_time, "")
          more.setTextViewText(
            R.id.calendar_summary_title,
            ui?.withCount(ui.moreCount, hidden) ?: context.getString(R.string.widget_more_count, hidden),
          )
          WidgetSupport.textColor(more, R.id.calendar_summary_title, theme, "accent", accent)
          more.setOnClickPendingIntent(R.id.calendar_summary_row, openCalendar)
          views.addView(R.id.calendar_summary, more)
        }
      }

      return views
    }

    private fun summaryRow(
      context: Context,
      item: WidgetSnapshot.MonthItemRow,
      theme: WidgetSnapshot.ThemeBlock?,
      primary: Int,
      secondary: Int,
      error: Int,
      accent: Int,
      ui: WidgetSnapshot.UiStrings?,
      appWidgetId: Int,
    ): RemoteViews {
      val row = RemoteViews(context.packageName, R.layout.widget_calendar_summary_row)
      val isDeadline = item.kind == "todoDeadline"
      val time = when {
        item.isAllDay -> ui?.allDay ?: context.getString(R.string.widget_all_day)
        isDeadline && !item.hasTime -> "□"
        else -> item.start
      }
      row.setTextViewText(R.id.calendar_summary_time, time)
      row.setTextViewText(R.id.calendar_summary_title, item.summary)
      WidgetSupport.textColor(row, R.id.calendar_summary_time, theme, "textSecondary", secondary)
      WidgetSupport.textColor(
        row,
        R.id.calendar_summary_title,
        theme,
        if (isDeadline && isOverdue(item)) "error" else "textPrimary",
        if (isDeadline && isOverdue(item)) error else primary,
      )
      row.setViewVisibility(R.id.calendar_summary_marker, View.VISIBLE)
      WidgetSupport.tint(
        row,
        R.id.calendar_summary_marker,
        if (isDeadline) secondary else WidgetSupport.parseColor(item.color, accent),
      )

      val uri = when {
        item.kind == "eventOccurrence" && (item.eventId ?: -1) > 0 ->
          WidgetSupport.eventUri(item.eventId!!)
        (item.todoId ?: -1) > 0 -> WidgetSupport.todoUri(item.todoId!!)
        else -> null
      }
      if (uri != null) {
        row.setOnClickPendingIntent(
          R.id.calendar_summary_row,
          WidgetSupport.openUri(context, uri, (uri.toString().hashCode() + appWidgetId) and 0x7FFFFFFF),
        )
      }
      return row
    }

    private fun isOverdue(item: WidgetSnapshot.MonthItemRow): Boolean {
      val due = item.startEpochMs ?: return false
      return due < System.currentTimeMillis() && item.hasTime
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

    private fun stateIntentEnterDay(
      context: Context,
      appWidgetId: Int,
      dateIso: String,
    ): android.app.PendingIntent {
      val intent = Intent(context, WidgetActionReceiver::class.java).apply {
        action = WidgetActionReceiver.ACTION_SET_CALENDAR_DATE
        data = android.net.Uri.parse("dayspark://widget-state/$appWidgetId/day/$dateIso")
        putExtra(WidgetActionReceiver.EXTRA_APP_WIDGET_ID, appWidgetId)
        putExtra(WidgetActionReceiver.EXTRA_CALENDAR_DATE, dateIso)
        putExtra(WidgetActionReceiver.EXTRA_ENTER_DAY, true)
      }
      return android.app.PendingIntent.getBroadcast(
        context,
        (appWidgetId * 149 + dateIso.hashCode()) and 0x7FFFFFFF,
        intent,
        android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE,
      )
    }

    private fun parseIso(iso: String): Date? = runCatching {
      SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { isLenient = false }.parse(iso)
    }.getOrNull()

    private fun isoDate(year: Int, month: Int, day: Int): String =
      String.format(Locale.US, "%04d-%02d-%02d", year, month, day)

    private fun mondayFirstWeekday(year: Int, month: Int): Int {
      val dow = Calendar.getInstance().apply {
        set(year, month - 1, 1)
      }.get(Calendar.DAY_OF_WEEK)
      return ((dow + 5) % 7) + 1
    }
  }
}
