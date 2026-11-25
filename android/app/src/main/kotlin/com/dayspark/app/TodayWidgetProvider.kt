package com.dayspark.app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import java.util.Date

// Action / 今日行动: Now, Later, Due today, Overdue and a completed footer.
// Events carry a calendar colour; allocations and todos carry a checkbox.
class TodayWidgetProvider : AppWidgetProvider() {
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

  override fun onReceive(context: Context, intent: Intent) {
    super.onReceive(context, intent)
    if (intent.action in CLOCK_ACTIONS) refreshAll(context)
  }

  companion object {
    private val CLOCK_ACTIONS = setOf(
      Intent.ACTION_DATE_CHANGED,
      Intent.ACTION_TIME_CHANGED,
      Intent.ACTION_TIMEZONE_CHANGED,
    )

    fun updateWidget(
      context: Context,
      manager: AppWidgetManager,
      appWidgetId: Int,
    ) {
      val size = WidgetSupport.sizeOf(manager, appWidgetId)
      val heightDp = WidgetSupport.dimensionsOf(manager, appWidgetId).second
      WidgetSupport.render(context, manager, appWidgetId) {
        build(context, appWidgetId, size, heightDp)
      }
    }

    private fun refreshAll(context: Context) {
      val manager = AppWidgetManager.getInstance(context)
      for (id in manager.getAppWidgetIds(
        ComponentName(context, TodayWidgetProvider::class.java),
      )) {
        updateWidget(context, manager, id)
      }
    }

    internal fun build(
      context: Context,
      appWidgetId: Int,
      size: WidgetSize,
      heightDp: Int,
    ): RemoteViews {
      val snapshot = WidgetSnapshot.read(context)
        ?: return WidgetSupport.fallback(context, appWidgetId)
      val block = snapshot.action()
      val ui = snapshot.ui()
      val theme = snapshot.theme()
      val layout = when (size) {
        WidgetSize.SMALL -> R.layout.widget_action_small
        WidgetSize.MEDIUM -> R.layout.widget_action_medium
        WidgetSize.LARGE -> R.layout.widget_action_large
      }
      val views = RemoteViews(context.packageName, layout)
      WidgetSupport.applyRoot(context, views, R.id.action_root, theme)

      val primary = context.getColor(R.color.widget_text_primary)
      val secondary = context.getColor(R.color.widget_text_secondary)
      val accent = context.getColor(R.color.widget_accent)
      val error = theme?.colors?.get("error") ?: context.getColor(R.color.widget_error)

      val dateIso = snapshot.todayIso().ifEmpty { WidgetSupport.todayIso(context) }
      val stale = dateIso != WidgetSupport.todayIso(context)
      views.setTextViewText(R.id.action_date, WidgetSupport.formatDate(dateIso))
      views.setTextViewText(R.id.action_weekday, WidgetSupport.formatWeekday(dateIso))
      WidgetSupport.textColor(views, R.id.action_date, theme, "textPrimary", primary)
      WidgetSupport.textColor(views, R.id.action_weekday, theme, "textSecondary", secondary)

      val root = WidgetSupport.openUri(context, WidgetSupport.actionUri(), appWidgetId + 500)
      views.setOnClickPendingIntent(R.id.action_root, root)
      views.setOnClickPendingIntent(R.id.action_date, root)
      views.setOnClickPendingIntent(R.id.action_weekday, root)

      val overdueCount = block.counts.overdue
      // A pinned small card is only ~100dp wide inside its padding: a 24sp date
      // plus a weekday plus an overdue badge plus the "+" leaves nothing, and
      // the header came out clipped on a real launcher. Small keeps the date at
      // the 17sp step and drops the weekday and the badge — the overdue rows
      // themselves now carry that information.
      if (size == WidgetSize.SMALL) {
        views.setTextViewTextSize(
          R.id.action_date,
          TypedValue.COMPLEX_UNIT_SP,
          17f,
        )
        views.setViewVisibility(R.id.action_weekday, View.GONE)
      }
      views.setViewVisibility(R.id.action_overdue_chip, View.GONE)

      views.setOnClickPendingIntent(
        R.id.action_add_todo,
        WidgetSupport.openUri(
          context,
          WidgetSupport.quickAddUri(dateIso),
          appWidgetId + 501,
        ),
      )
      WidgetSupport.textColor(views, R.id.action_add_todo, theme, "accent", accent)
      // Medium and large use a worded button; small is a bare "+" and keeps it.
      ui?.addTodo?.takeIf { it.isNotEmpty() && size != WidgetSize.SMALL }?.let {
        views.setTextViewText(R.id.action_add_todo, it)
      }
      if (size != WidgetSize.SMALL) {
        views.setOnClickPendingIntent(
          R.id.action_add_event,
          WidgetSupport.openUri(
            context,
            WidgetSupport.newEventUri(dateIso),
            appWidgetId + 502,
          ),
        )
        WidgetSupport.textColor(views, R.id.action_add_event, theme, "accent", accent)
        ui?.addEvent?.takeIf { it.isNotEmpty() }?.let {
          views.setTextViewText(R.id.action_add_event, it)
        }
      }

      views.removeAllViews(R.id.action_rows)
      val nowMs = Date().time
      val current = block.timeline
        .filter { it.startEpochMs <= nowMs && nowMs < it.endEpochMs }
        .sortedBy { it.startEpochMs }
      val later = block.timeline
        .filter { it.startEpochMs > nowMs }
        .sortedBy { it.startEpochMs }

      val allDayLabel = ui?.allDay ?: ""
      fun timelinePlanned(item: WidgetSnapshot.ActionTimelineRow): PlannedRow {
        val meta = WidgetSupport.formatTimeRange(item.start, item.end, item.isAllDay, allDayLabel)
        return PlannedRow(
          timelineRow(context, item, theme, allDayLabel),
          WidgetSupport.timelineRowHeightDp(context, title = item.summary, meta = meta),
        )
      }
      val currentRows = current.map { timelinePlanned(it) }
      val laterRows = later.map { timelinePlanned(it) }
      val dueRows = block.dueToday.map {
        PlannedRow(taskRow(context, it, theme, error), taskRowHeight(context, it))
      }
      val overdueRows = block.overdue.map {
        PlannedRow(taskRow(context, it, theme, error), taskRowHeight(context, it))
      }
      // Completed rows remain as a read-only record of today's work; a tap
      // opens the item like every other row. They come from their own snapshot
      // key and are drawn only after every open group.
      val completedRows = block.completed.map {
        PlannedRow(taskRow(context, it, theme, error), taskRowHeight(context, it))
      }
      val allRows = currentRows + laterRows + dueRows + overdueRows
      val allRowsWithCompleted = allRows + completedRows

      val completedCount = block.counts.completedToday
      val effectiveHeight = if (heightDp > 0) heightDp else 220
      val paddingDp = if (size == WidgetSize.SMALL) 8 else 12
      // Section headers are spent from the same budget as the rows below them;
      // only the root padding, the date header and the footer are fixed chrome.
      val rowsAvailable = effectiveHeight - paddingDp * 2 - 48
      // Rows are placed first and the completed footer is only a fallback for a
      // card with no room to draw the completed rows themselves, so the footer
      // is decided after them rather than reserved up front.
      val budget = RowBudget(rowsAvailable)
      var shown = 0
      var completedShown = 0

      fun addSection(
        title: String,
        rows: List<PlannedRow>,
        sectionColor: Int? = null,
      ): Boolean {
        if (rows.isEmpty()) return false
        val headerDp = if (size == WidgetSize.SMALL) 0 else WidgetSupport.SECTION_DP
        if (budget.remainingDp < headerDp + rows.first().heightDp) return false
        if (headerDp > 0) {
          budget.take(headerDp)
          val header = RemoteViews(context.packageName, R.layout.widget_action_section)
          header.setTextViewText(R.id.action_section, title)
          if (sectionColor != null) {
            header.setTextColor(R.id.action_section, sectionColor)
          } else {
            WidgetSupport.textColor(header, R.id.action_section, theme, "textSecondary", secondary)
          }
          views.addView(R.id.action_rows, header)
        }
        for (row in rows) {
          if (!budget.take(row.heightDp)) break
          views.addView(R.id.action_rows, row.views)
          shown++
        }
        return true
      }

      if (stale) {
        // A snapshot from another day must never be rendered as today.
      } else if (size == WidgetSize.SMALL) {
        // Small has no room for section headers, so it shows the app's own
        // order — now, later, due today, overdue — and fills whatever rows the
        // frame has. Picking only the first of now/later/due hid the overdue
        // list entirely on a frame that was several rows tall.
        for (row in allRowsWithCompleted) {
          if (!budget.take(row.heightDp)) break
          views.addView(R.id.action_rows, row.views)
          if (row in completedRows) completedShown++ else shown++
        }
      } else {
        addSection(ui?.now ?: "", currentRows, theme?.colors?.get("accent") ?: accent)
        addSection(ui?.later ?: "", laterRows)
        addSection(ui?.dueToday ?: "", dueRows)
        val overdueAdded = addSection(ui?.overdue ?: "", overdueRows, error)
        val overdueShown = overdueAdded && shown > 0
        val overdueText = ui?.withCount(ui.overdueCount, overdueCount) ?: "$overdueCount"
        val overdueRowDp = WidgetSupport.todoRowHeightDp(
          context, hasMeta = false, hasTags = false, title = overdueText,
        )
        if (overdueCount > 0 && !overdueShown && budget.take(overdueRowDp)) {
          val summary = RemoteViews(context.packageName, R.layout.widget_todo_item)
          summary.setViewVisibility(R.id.todo_check, View.GONE)
          summary.setViewVisibility(R.id.todo_priority, View.GONE)
          summary.setViewVisibility(R.id.todo_repeat, View.GONE)
          summary.setViewVisibility(R.id.todo_meta, View.GONE)
          summary.setViewVisibility(R.id.todo_tags, View.GONE)
          summary.setTextViewText(R.id.todo_title, overdueText)
          summary.setTextColor(R.id.todo_title, error)
          WidgetSupport.bindOpen(
            summary,
            WidgetRows.TODO_OPEN_IDS,
            WidgetSupport.openUri(context, WidgetSupport.actionUri(), appWidgetId + 503),
          )
          views.addView(R.id.action_rows, summary)
          shown++
        }
        for (row in completedRows) {
          if (!budget.take(row.heightDp)) break
          views.addView(R.id.action_rows, row.views)
          completedShown++
        }
      }

      // The footer is a 48dp fixed view in every layout, so it is only drawn
      // when a full 48dp is still unspent.
      val reserveFooter = completedCount > 0 &&
        completedShown == 0 &&
        budget.take(48)
      if (!stale && reserveFooter) {
        views.setViewVisibility(R.id.action_completed, View.VISIBLE)
        views.setTextViewText(
          R.id.action_completed,
          ui?.withCount(ui.completedCount, completedCount)
            ?: context.getString(R.string.widget_completed_count, completedCount),
        )
        WidgetSupport.textColor(views, R.id.action_completed, theme, "textSecondary", secondary)
        views.setOnClickPendingIntent(R.id.action_completed, root)
      } else {
        views.setViewVisibility(R.id.action_completed, View.GONE)
      }

      // Emptiness comes from the data, not from how many rows fit: an honest
      // short card is blank, a wrong "no plans" label is not.
      val empty = stale || (allRows.isEmpty() && completedCount == 0)
      views.setViewVisibility(R.id.action_empty, if (empty) View.VISIBLE else View.GONE)
      if (empty) {
        val text = when {
          stale -> ui?.openToUpdate ?: context.getString(R.string.widget_open_to_update)
          else -> ui?.noPlans ?: context.getString(R.string.widget_no_plans)
        }
        views.setTextViewText(R.id.action_empty, text)
        WidgetSupport.textColor(views, R.id.action_empty, theme, "textSecondary", secondary)
      }

      return views
    }

    private class PlannedRow(val views: RemoteViews, val heightDp: Int)

    private fun taskMeta(action: WidgetSnapshot.ActionTaskRow): String =
      action.displayTime?.takeIf { it.isNotEmpty() }
        ?: action.dueDate?.let { WidgetSupport.formatDate(it) }
        ?: ""

    private fun taskRowHeight(
      context: Context,
      action: WidgetSnapshot.ActionTaskRow,
    ): Int {
      val meta = taskMeta(action)
      return WidgetSupport.todoRowHeightDp(
        context,
        meta.isNotEmpty(),
        hasTags = false,
        title = action.summary,
        meta = meta,
      )
    }

    internal fun timelineRow(
      context: Context,
      item: WidgetSnapshot.ActionTimelineRow,
      theme: WidgetSnapshot.ThemeBlock?,
      allDayLabel: String,
    ): RemoteViews {
      val primary = context.getColor(R.color.widget_text_primary)
      val secondary = context.getColor(R.color.widget_text_secondary)
      val accent = context.getColor(R.color.widget_accent)
      val row = RemoteViews(context.packageName, R.layout.widget_timeline_row)
      row.setTextViewText(R.id.timeline_title, item.summary)
      val meta = WidgetSupport.formatTimeRange(item.start, item.end, item.isAllDay, allDayLabel)
      row.setTextViewText(R.id.timeline_meta, meta)
      WidgetSupport.textColor(row, R.id.timeline_title, theme, "textPrimary", primary)
      WidgetSupport.textColor(row, R.id.timeline_meta, theme, "textSecondary", secondary)

      val todoId = item.todoId ?: -1
      if (item.kind == "taskAllocation" && todoId > 0) {
        row.setViewVisibility(R.id.timeline_marker, View.GONE)
        row.setViewVisibility(R.id.timeline_check, View.VISIBLE)
        // The circle is a state glyph, not a control: read-only snapshot.
        row.setImageViewResource(
          R.id.timeline_check,
          if (item.completed) R.drawable.widget_check_on else R.drawable.widget_check_off,
        )
        if (item.completed) {
          WidgetSupport.tint(row, R.id.timeline_check, theme?.colors?.get("accent") ?: accent)
          WidgetSupport.textColor(row, R.id.timeline_title, theme, "textSecondary", secondary)
          row.setInt(
            R.id.timeline_title,
            "setPaintFlags",
            android.graphics.Paint.STRIKE_THRU_TEXT_FLAG,
          )
        }
        val open = WidgetSupport.openUri(context, WidgetSupport.todoUri(todoId), appWidgetIdSeed(todoId, 201))
        WidgetSupport.bindOpen(row, WidgetRows.TIMELINE_OPEN_IDS, open)
        // The check sits inside the row; bind it too so the whole row opens.
        row.setOnClickPendingIntent(R.id.timeline_check, open)
      } else {
        row.setViewVisibility(R.id.timeline_marker, View.VISIBLE)
        row.setViewVisibility(R.id.timeline_check, View.GONE)
        WidgetSupport.tint(
          row,
          R.id.timeline_marker,
          WidgetSupport.parseColor(item.color, accent),
        )
        val eventId = item.eventId ?: -1
        val uri = if (eventId > 0) {
          WidgetSupport.eventUri(eventId)
        } else {
          WidgetSupport.actionUri()
        }
        WidgetSupport.bindOpen(
          row,
          WidgetRows.TIMELINE_OPEN_IDS,
          WidgetSupport.openUri(context, uri, appWidgetIdSeed(eventId, 202)),
        )
      }
      return row
    }

    internal fun taskRow(
      context: Context,
      action: WidgetSnapshot.ActionTaskRow,
      theme: WidgetSnapshot.ThemeBlock?,
      error: Int,
    ): RemoteViews {
      val primary = context.getColor(R.color.widget_text_primary)
      val secondary = context.getColor(R.color.widget_text_secondary)
      val accent = context.getColor(R.color.widget_accent)
      val row = RemoteViews(context.packageName, R.layout.widget_todo_item)
      row.setTextViewText(R.id.todo_title, action.summary)
      WidgetSupport.textColor(row, R.id.todo_title, theme, "textPrimary", primary)
      row.setViewVisibility(R.id.todo_priority, View.GONE)
      row.setViewVisibility(R.id.todo_repeat, View.GONE)
      row.setViewVisibility(R.id.todo_tags, View.GONE)

      val meta = taskMeta(action)
      row.setTextViewText(R.id.todo_meta, meta)
      row.setViewVisibility(
        R.id.todo_meta,
        if (meta.isEmpty()) View.GONE else View.VISIBLE,
      )
      WidgetSupport.textColor(row, R.id.todo_meta, theme, "textSecondary", secondary)

      row.setImageViewResource(
        R.id.todo_check,
        if (action.completed) R.drawable.widget_check_on else R.drawable.widget_check_off,
      )
      if (action.completed) {
        WidgetSupport.tint(row, R.id.todo_check, theme?.colors?.get("accent") ?: accent)
        WidgetSupport.textColor(row, R.id.todo_title, theme, "textSecondary", secondary)
        row.setInt(
          R.id.todo_title,
          "setPaintFlags",
          android.graphics.Paint.STRIKE_THRU_TEXT_FLAG,
        )
      }
      if (action.todoId > 0) {
        val open = WidgetSupport.openUri(
          context,
          WidgetSupport.todoUri(action.todoId),
          appWidgetIdSeed(action.todoId, 203),
        )
        WidgetSupport.bindOpen(row, WidgetRows.TODO_OPEN_IDS, open)
        // Read-only: the checkbox is state, so the tap opens the item.
        row.setOnClickPendingIntent(R.id.todo_check, open)
      } else {
        // A row without an id still has to be honest: no checkbox to press and
        // a tap that lands on the task list rather than doing nothing.
        row.setViewVisibility(R.id.todo_check, View.GONE)
        WidgetSupport.bindOpen(
          row,
          WidgetRows.TODO_OPEN_IDS,
          WidgetSupport.openUri(context, WidgetSupport.actionUri(), appWidgetIdSeed(0, 204)),
        )
      }
      return row
    }

    private fun appWidgetIdSeed(id: Int, salt: Int): Int =
      (id * 31 + salt) and 0x7FFFFFFF
  }
}
