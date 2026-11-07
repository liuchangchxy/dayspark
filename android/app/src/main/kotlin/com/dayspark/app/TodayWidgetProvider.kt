package com.dayspark.app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews

class TodayWidgetProvider : AppWidgetProvider() {
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
      val layout = when (size) {
        WidgetSize.SMALL -> R.layout.widget_today_small
        WidgetSize.MEDIUM -> R.layout.widget_today_medium
        WidgetSize.LARGE -> R.layout.widget_today_large
      }
      val views = RemoteViews(context.packageName, layout)
      WidgetSupport.applyRoot(views, R.id.today_root, theme)

      val primary = context.getColor(R.color.widget_text_primary)
      val secondary = context.getColor(R.color.widget_text_secondary)
      val accent = context.getColor(R.color.widget_accent)

      val dateIso = snapshot.todayDate().ifEmpty { WidgetSupport.todayIso(context) }
      views.setTextViewText(R.id.today_date, WidgetSupport.formatDate(dateIso))
      views.setTextViewText(R.id.today_weekday, WidgetSupport.formatWeekday(dateIso))
      WidgetSupport.textColor(views, R.id.today_date, theme, "textPrimary", primary)
      WidgetSupport.textColor(views, R.id.today_weekday, theme, "textSecondary", secondary)

      val targets = WidgetSnapshot.readPendingTargets(context)
      val timeline = snapshot.todayTimeline()
      val actions = snapshot.todayActions()
      val height = WidgetSupport.dimensionsOf(manager, appWidgetId).second
      val maxTimeline = if (size == WidgetSize.LARGE) 6 else 3
      val maxActions = if (size == WidgetSize.LARGE) 8 else 3
      val budget = when (size) {
        WidgetSize.SMALL -> 2
        WidgetSize.MEDIUM -> ((height - 120) / 48).coerceIn(2, 6)
        WidgetSize.LARGE -> ((height - 150) / 48).coerceIn(3, 14)
      }
      val timelineLimit = when (size) {
        WidgetSize.SMALL -> 1
        else -> (budget / 2).coerceIn(1, maxTimeline)
      }
      val actionLimit = when (size) {
        WidgetSize.SMALL -> 1
        else -> (budget - timelineLimit).coerceIn(1, maxActions)
      }

      for (item in timeline.take(timelineLimit)) {
        views.addView(
          R.id.today_timeline,
          timelineRow(context, item, targets, theme, ui?.allDay ?: ""),
        )
      }
      for (action in actions.take(actionLimit)) {
        views.addView(
          R.id.today_actions,
          actionRow(context, action, targets, theme),
        )
      }

      val isEmpty = timeline.isEmpty() && actions.isEmpty()
      WidgetSupport.setVisible(views, R.id.today_empty, isEmpty)
      if (isEmpty) {
        views.setTextViewText(
          R.id.today_empty,
          ui?.noPlans?.ifEmpty { context.getString(R.string.widget_no_plans) }
            ?: context.getString(R.string.widget_no_plans),
        )
        WidgetSupport.textColor(views, R.id.today_empty, theme, "textSecondary", secondary)
      }

      views.setOnClickPendingIntent(
        R.id.today_root,
        WidgetSupport.openUri(
          context,
          android.net.Uri.parse("dayspark://open/today"),
          appWidgetId,
        ),
      )

      if (size != WidgetSize.SMALL) {
        views.setOnClickPendingIntent(
          R.id.today_add_todo,
          WidgetSupport.openUri(
            context,
            WidgetSupport.quickAddUri,
            appWidgetId + 101,
          ),
        )
        WidgetSupport.textColor(views, R.id.today_add_todo, theme, "accent", accent)
      }
      if (size == WidgetSize.LARGE) {
        views.setOnClickPendingIntent(
          R.id.today_add_event,
          WidgetSupport.openUri(
            context,
            WidgetSupport.newEventUri(dateIso),
            appWidgetId + 102,
          ),
        )
        WidgetSupport.textColor(views, R.id.today_add_event, theme, "accent", accent)
      }

      return views
    }

    private fun timelineRow(
      context: Context,
      item: WidgetSnapshot.TimelineRow,
      targets: WidgetSnapshot.PendingTargets,
      theme: WidgetSnapshot.ThemeBlock?,
      allDayLabel: String,
    ): RemoteViews {
      val primary = context.getColor(R.color.widget_text_primary)
      val secondary = context.getColor(R.color.widget_text_secondary)
      val accent = context.getColor(R.color.widget_accent)
      val row = RemoteViews(context.packageName, R.layout.widget_timeline_row)
      row.setTextViewText(R.id.timeline_title, item.summary)
      val meta = WidgetSupport.formatTimeRange(
        item.start,
        item.end,
        item.isAllDay,
        allDayLabel,
      )
      row.setTextViewText(R.id.timeline_meta, meta)
      WidgetSupport.textColor(row, R.id.timeline_title, theme, "textPrimary", primary)
      WidgetSupport.textColor(row, R.id.timeline_meta, theme, "textSecondary", secondary)

      val todoId = item.todoId ?: -1
      if (item.kind == "taskAllocation" && todoId > 0) {
        row.setViewVisibility(R.id.timeline_marker, View.GONE)
        row.setViewVisibility(R.id.timeline_check, View.VISIBLE)
        val target = if (!item.occurrenceId.isNullOrEmpty()) "taskInstance" else "todo"
        val pending = WidgetSupport.isPending(
          targets,
          target,
          todoId,
          item.occurrenceId,
        )
        row.setImageViewResource(
          R.id.timeline_check,
          if (pending) R.drawable.widget_check_on else R.drawable.widget_check_off,
        )
        if (pending) {
          WidgetSupport.tint(
            row,
            R.id.timeline_check,
            theme?.colors?.get("accent") ?: accent,
          )
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
          WidgetSupport.openUri(
            context,
            WidgetSupport.todoUri(todoId),
            todoId + 201,
          ),
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
        val targetUri = if (eventId > 0) {
          WidgetSupport.eventUri(eventId)
        } else {
          android.net.Uri.parse("dayspark://open/today")
        }
        row.setOnClickPendingIntent(
          R.id.timeline_row,
          WidgetSupport.openUri(context, targetUri, eventId + 301),
        )
      }
      return row
    }

    private fun actionRow(
      context: Context,
      action: WidgetSnapshot.ActionRow,
      targets: WidgetSnapshot.PendingTargets,
      theme: WidgetSnapshot.ThemeBlock?,
    ): RemoteViews {
      val primary = context.getColor(R.color.widget_text_primary)
      val secondary = context.getColor(R.color.widget_text_secondary)
      val accent = context.getColor(R.color.widget_accent)
      val row = RemoteViews(context.packageName, R.layout.widget_todo_row)
      row.setTextViewText(R.id.todo_title, action.summary)
      WidgetSupport.textColor(row, R.id.todo_title, theme, "textPrimary", primary)

      val meta = action.deadline?.ifEmpty { null } ?: action.displayTime ?: ""
      row.setTextViewText(R.id.todo_meta, meta)
      row.setViewVisibility(
        R.id.todo_meta,
        if (meta.isEmpty()) View.GONE else View.VISIBLE,
      )
      WidgetSupport.textColor(row, R.id.todo_meta, theme, "textSecondary", secondary)

      val pending = WidgetSupport.isPending(
        targets,
        action.target,
        action.todoId,
        action.occurrenceId,
      )
      row.setImageViewResource(
        R.id.todo_check,
        if (pending) R.drawable.widget_check_on else R.drawable.widget_check_off,
      )
      if (pending) {
        WidgetSupport.tint(
          row,
          R.id.todo_check,
          theme?.colors?.get("accent") ?: accent,
        )
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
          R.id.todo_row,
          WidgetSupport.openUri(
            context,
            WidgetSupport.todoUri(action.todoId),
            action.todoId + 401,
          ),
        )
      }
      return row
    }
  }
}
