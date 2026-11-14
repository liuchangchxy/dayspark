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
      WidgetSupport.render(context, manager, appWidgetId) {
        build(context, manager, appWidgetId)
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

    private fun build(
      context: Context,
      manager: AppWidgetManager,
      appWidgetId: Int,
    ): RemoteViews {
      val snapshot = WidgetSnapshot.read(context)
        ?: return WidgetSupport.fallback(context, appWidgetId)
      val block = snapshot.action()
      val ui = snapshot.ui()
      val theme = snapshot.theme()
      val size = WidgetSupport.sizeOf(manager, appWidgetId)
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
      val pending = WidgetSnapshot.readPendingTargets(context)
      val nowMs = Date().time
      val current = block.timeline
        .filter { it.startEpochMs <= nowMs && nowMs < it.endEpochMs }
        .sortedBy { it.startEpochMs }
      val later = block.timeline
        .filter { it.startEpochMs > nowMs }
        .sortedBy { it.startEpochMs }

      val currentRows = current.map { timelineRow(context, it, pending, theme, ui?.allDay ?: "") }
      val laterRows = later.map { timelineRow(context, it, pending, theme, ui?.allDay ?: "") }
      val dueRows = block.dueToday.map { taskRow(context, it, pending, theme, error) }
      val overdueRows = block.overdue.map { taskRow(context, it, pending, theme, error) }

      val height = WidgetSupport.dimensionsOf(manager, appWidgetId).second
      val completedCount = block.counts.completedToday
      // Chrome is what the card spends before the first row: padding, the 48dp
      // header and a 24dp header per section that will actually be drawn. The
      // old fixed allowance reserved three section headers and a 44dp footer
      // whatever the card held, so a tall card cut off rows it had room for.
      val sectionHeaders = if (size == WidgetSize.SMALL) {
        0
      } else {
        listOf(currentRows, laterRows, dueRows, overdueRows).count { it.isNotEmpty() }
      }
      val chrome = WidgetSupport.actionChromeDp(size == WidgetSize.SMALL, sectionHeaders)
      val footer = WidgetSupport.actionFooterDp(completedCount)
      val budget = when (size) {
        // Small is a single column here but the launcher can still give it
        // several rows; one fixed row left the rest of the card empty.
        WidgetSize.SMALL -> WidgetSupport.rowBudget(height, chrome, footer, 48, 1, 8)
        WidgetSize.MEDIUM -> WidgetSupport.rowBudget(height, chrome, footer, 48, 1, 6)
        WidgetSize.LARGE -> WidgetSupport.rowBudget(height, chrome, footer, 48, 2, 14)
      }
      var shown = 0

      fun addSection(
        title: String,
        rows: List<RemoteViews>,
        sectionColor: Int? = null,
      ): Boolean {
        if (rows.isEmpty() || shown >= budget) return false
        if (size != WidgetSize.SMALL) {
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
          if (shown >= budget) break
          views.addView(R.id.action_rows, row)
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
        val rows = currentRows + laterRows + dueRows + overdueRows
        for (row in rows) {
          if (shown >= budget) break
          views.addView(R.id.action_rows, row)
          shown++
        }
      } else {
        var overdueShown = false
        addSection(ui?.now ?: "", currentRows, theme?.colors?.get("accent") ?: accent)
        addSection(ui?.later ?: "", laterRows)
        addSection(ui?.dueToday ?: "", dueRows)
        val overdueAdded = addSection(ui?.overdue ?: "", overdueRows, error)
        overdueShown = overdueAdded && shown > 0
        if (overdueCount > 0 && !overdueShown && shown < budget) {
          val summary = RemoteViews(context.packageName, R.layout.widget_todo_item)
          summary.setViewVisibility(R.id.todo_check, View.GONE)
          summary.setViewVisibility(R.id.todo_priority, View.GONE)
          summary.setViewVisibility(R.id.todo_repeat, View.GONE)
          summary.setViewVisibility(R.id.todo_meta, View.GONE)
          summary.setViewVisibility(R.id.todo_tags, View.GONE)
          summary.setTextViewText(
            R.id.todo_title,
            ui?.withCount(ui.overdueCount, overdueCount) ?: "$overdueCount",
          )
          summary.setTextColor(R.id.todo_title, error)
          summary.setOnClickPendingIntent(
            R.id.todo_item,
            WidgetSupport.openUri(context, WidgetSupport.actionUri(), appWidgetId + 503),
          )
          views.addView(R.id.action_rows, summary)
          shown++
        }
      }

      if (!stale && completedCount > 0) {
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

      val empty = stale || (shown == 0 && completedCount == 0)
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

    private fun timelineRow(
      context: Context,
      item: WidgetSnapshot.ActionTimelineRow,
      pending: WidgetSnapshot.PendingTargets,
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
        val target = if (!item.occurrenceId.isNullOrEmpty()) "taskInstance" else "todo"
        val isPending = WidgetSupport.isPending(pending, target, todoId, item.occurrenceId)
        row.setImageViewResource(
          R.id.timeline_check,
          if (isPending) R.drawable.widget_check_on else R.drawable.widget_check_off,
        )
        if (isPending) {
          WidgetSupport.tint(row, R.id.timeline_check, theme?.colors?.get("accent") ?: accent)
        }
        row.setOnClickPendingIntent(
          R.id.timeline_check,
          WidgetSupport.togglePendingIntent(
            context,
            target,
            todoId,
            item.todoSyncId,
            item.occurrenceId,
            item.allocationId,
          ),
        )
        row.setOnClickPendingIntent(
          R.id.timeline_row,
          WidgetSupport.openUri(context, WidgetSupport.todoUri(todoId), appWidgetIdSeed(todoId, 201)),
        )
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
        row.setOnClickPendingIntent(
          R.id.timeline_row,
          WidgetSupport.openUri(context, uri, appWidgetIdSeed(eventId, 202)),
        )
      }
      return row
    }

    private fun taskRow(
      context: Context,
      action: WidgetSnapshot.ActionTaskRow,
      pending: WidgetSnapshot.PendingTargets,
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

      val meta = action.displayTime?.takeIf { it.isNotEmpty() }
        ?: action.dueDate?.let { WidgetSupport.formatDate(it) }
        ?: ""
      row.setTextViewText(R.id.todo_meta, meta)
      row.setViewVisibility(
        R.id.todo_meta,
        if (meta.isEmpty()) View.GONE else View.VISIBLE,
      )
      WidgetSupport.textColor(row, R.id.todo_meta, theme, "textSecondary", secondary)

      val isPending = WidgetSupport.isPending(
        pending,
        action.target,
        action.todoId,
        action.occurrenceId,
      )
      row.setImageViewResource(
        R.id.todo_check,
        if (isPending) R.drawable.widget_check_on else R.drawable.widget_check_off,
      )
      if (isPending) {
        WidgetSupport.tint(row, R.id.todo_check, theme?.colors?.get("accent") ?: accent)
      }
      if (action.todoId > 0) {
        row.setOnClickPendingIntent(
          R.id.todo_check,
          WidgetSupport.togglePendingIntent(
            context,
            action.target,
            action.todoId,
            action.todoSyncId,
            action.occurrenceId,
            null,
          ),
        )
        row.setOnClickPendingIntent(
          R.id.todo_item,
          WidgetSupport.openUri(context, WidgetSupport.todoUri(action.todoId), appWidgetIdSeed(action.todoId, 203)),
        )
      }
      return row
    }

    private fun appWidgetIdSeed(id: Int, salt: Int): Int =
      (id * 31 + salt) and 0x7FFFFFFF
  }
}
