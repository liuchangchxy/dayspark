package com.dayspark.app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews

// Todos / 待办: the long-lived task list. It never shows events, allocations or
// a timeline. Mode is per instance; today mode mirrors the App's overdue group.
class TodoWidgetProvider : AppWidgetProvider() {
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
      for (id in manager.getAppWidgetIds(ComponentName(context, TodoWidgetProvider::class.java))) {
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
        ?: return WidgetSupport.fallback(context, appWidgetId)
      val ui = snapshot.ui()
      val theme = snapshot.theme()
      val size = WidgetSupport.sizeOf(manager, appWidgetId)
      val layout = when (size) {
        WidgetSize.SMALL -> R.layout.widget_todos_small
        WidgetSize.MEDIUM -> R.layout.widget_todos_medium
        WidgetSize.LARGE -> R.layout.widget_todos_large
      }
      val views = RemoteViews(context.packageName, layout)
      WidgetSupport.applyRoot(context, views, R.id.todos_root, theme)

      val state = WidgetStateStore.read(context, appWidgetId)
      val mode = state.todoMode
      val block = snapshot.todos()
      val current = when (mode) {
        "inbox" -> block.inbox
        "all" -> block.all
        else -> block.today
      }
      val todayMode = mode == "today"
      val overdueRows = if (todayMode) current.overdue else emptyList()
      val todayIso = snapshot.todayIso().ifEmpty { WidgetSupport.todayIso(context) }
      val snapshotStale = todayIso != WidgetSupport.todayIso(context)
      val todayStale = snapshotStale && mode == "today"

      val primary = context.getColor(R.color.widget_text_primary)
      val secondary = context.getColor(R.color.widget_text_secondary)
      val accent = context.getColor(R.color.widget_accent)
      val error = theme?.colors?.get("error") ?: context.getColor(R.color.widget_error)
      val warning = theme?.colors?.get("warning") ?: theme?.colors?.get("accent") ?: accent

      val modeLabel = when (mode) {
        "inbox" -> ui?.inbox ?: context.getString(R.string.widget_inbox)
        "all" -> ui?.all ?: context.getString(R.string.widget_all)
        else -> ui?.today ?: context.getString(R.string.widget_today)
      }
      val total = current.total + overdueRows.size
      views.setTextViewText(R.id.todos_mode, if (size == WidgetSize.SMALL) modeLabel else context.getString(R.string.widget_todos_name))
      views.setTextViewText(R.id.todos_count, total.toString())
      WidgetSupport.textColor(views, R.id.todos_mode, theme, "textPrimary", primary)
      WidgetSupport.textColor(views, R.id.todos_count, theme, "textSecondary", secondary)

      val listUri = WidgetSupport.todosUri(mode)
      views.setOnClickPendingIntent(
        R.id.todos_root,
        WidgetSupport.openUri(context, listUri, appWidgetId + 600),
      )
      views.setOnClickPendingIntent(
        R.id.todos_count,
        WidgetSupport.openUri(context, listUri, appWidgetId + 601),
      )
      if (size == WidgetSize.SMALL) {
        views.setOnClickPendingIntent(
          R.id.todos_mode,
          WidgetSupport.stateIntent(
            context,
            appWidgetId,
            WidgetActionReceiver.ACTION_CYCLE_TODO_MODE,
          ),
        )
      } else {
        views.setOnClickPendingIntent(
          R.id.todos_mode,
          WidgetSupport.openUri(context, listUri, appWidgetId + 602),
        )
        chip(context, views, R.id.todos_chip_today, ui?.today ?: "", mode == "today", appWidgetId, "today", theme, secondary, accent)
        chip(context, views, R.id.todos_chip_inbox, ui?.inbox ?: "", mode == "inbox", appWidgetId, "inbox", theme, secondary, accent)
        chip(context, views, R.id.todos_chip_all, ui?.all ?: "", mode == "all", appWidgetId, "all", theme, secondary, accent)
      }

      val addDate = if (mode == "today") todayIso else null
      views.setOnClickPendingIntent(
        R.id.todos_add,
        WidgetSupport.openUri(
          context,
          WidgetSupport.quickAddUri(addDate),
          appWidgetId + 603,
        ),
      )
      WidgetSupport.textColor(views, R.id.todos_add, theme, "accent", accent)

      views.removeAllViews(R.id.todos_rows)
      val pending = WidgetSnapshot.readPendingTargets(context)
      val height = WidgetSupport.dimensionsOf(manager, appWidgetId).second
      val budget = when (size) {
        // A narrow pin can still be five rows tall, and a fixed budget of two
        // left most of that card blank. The chrome is 16dp of padding plus the
        // 48dp header, so the rows get whatever height is actually there.
        WidgetSize.SMALL -> WidgetSupport.rowBudget(height, 64, 0, 48, 2, 6)
        WidgetSize.MEDIUM -> WidgetSupport.rowBudget(height, 120, 0, 48, 1, 6)
        WidgetSize.LARGE -> WidgetSupport.rowBudget(height, 120, 0, 48, 3, 12)
      }.let {
        if (size == WidgetSize.LARGE && todayMode && overdueRows.isNotEmpty()) {
          (it - 1).coerceAtLeast(1)
        } else {
          it
        }
      }
      var shown = 0
      var overdueShown = 0
      var todayShown = 0

      fun addHeader(text: String) {
        val header = RemoteViews(context.packageName, R.layout.widget_action_section)
        header.setTextViewText(R.id.action_section, text)
        WidgetSupport.textColor(header, R.id.action_section, theme, "textSecondary", secondary)
        views.addView(R.id.todos_rows, header)
      }

      if (snapshotStale) {
        views.addView(
          R.id.todos_rows,
          staleRow(
            context,
            ui,
            theme,
            secondary,
            appWidgetId,
            todayMessage = todayStale,
          ),
        )
        shown++
      }

      if (!todayStale) {
        val showGroups = size == WidgetSize.LARGE && todayMode
        if (todayMode && overdueRows.isNotEmpty()) {
          if (showGroups) addHeader(ui?.overdue ?: context.getString(R.string.widget_overdue))
          for (item in overdueRows) {
            if (shown >= budget) break
            views.addView(
              R.id.todos_rows,
              itemRow(
                context, item, pending, theme, size, mode,
                overdue = true, error = error, warning = warning,
                number = 0, appWidgetId = appWidgetId,
              ),
            )
            shown++
            overdueShown++
          }
          if (showGroups && shown < budget) {
            addHeader(ui?.today ?: context.getString(R.string.widget_today))
          }
        }

        for (item in current.items) {
          if (shown >= budget) break
          todayShown++
          views.addView(
            R.id.todos_rows,
            itemRow(
              context, item, pending, theme, size, mode,
              overdue = false, error = error, warning = warning,
              number = todayShown, appWidgetId = appWidgetId,
            ),
          )
          shown++
        }
      }

      val emitted = overdueShown + todayShown
      val more = total - emitted
      if (!todayStale && more > 0 && shown < budget) {
        val moreRow = RemoteViews(context.packageName, R.layout.widget_todo_item)
        moreRow.setViewVisibility(R.id.todo_check, View.GONE)
        moreRow.setViewVisibility(R.id.todo_priority, View.GONE)
        moreRow.setViewVisibility(R.id.todo_repeat, View.GONE)
        moreRow.setViewVisibility(R.id.todo_meta, View.GONE)
        moreRow.setViewVisibility(R.id.todo_tags, View.GONE)
        moreRow.setTextViewText(
          R.id.todo_title,
          ui?.withCount(ui.moreCount, more) ?: context.getString(R.string.widget_more_count, more),
        )
        WidgetSupport.textColor(moreRow, R.id.todo_title, theme, "accent", accent)
        moreRow.setOnClickPendingIntent(
          R.id.todo_item,
          WidgetSupport.openUri(context, listUri, appWidgetId + 604),
        )
        views.addView(R.id.todos_rows, moreRow)
        shown++
      }

      val empty = !todayStale && emitted == 0
      views.setViewVisibility(R.id.todos_empty, if (empty) View.VISIBLE else View.GONE)
      if (empty) {
        val text = when {
          mode == "today" && current.completedCount > 0 ->
            ui?.allTodosDone ?: context.getString(R.string.widget_all_todos_done)
          else -> ui?.noTodos ?: context.getString(R.string.widget_no_todos)
        }
        views.setTextViewText(R.id.todos_empty, text)
        WidgetSupport.textColor(views, R.id.todos_empty, theme, "textSecondary", secondary)
      }

      return views
    }

    private fun chip(
      context: Context,
      views: RemoteViews,
      id: Int,
      label: String,
      selected: Boolean,
      appWidgetId: Int,
      mode: String,
      theme: WidgetSnapshot.ThemeBlock?,
      secondary: Int,
      accent: Int,
    ) {
      views.setTextViewText(id, label)
      views.setTextColor(
        id,
        if (selected) {
          theme?.colors?.get("accent") ?: accent
        } else {
          theme?.colors?.get("textSecondary") ?: secondary
        },
      )
      views.setOnClickPendingIntent(
        id,
        WidgetSupport.stateIntent(
          context,
          appWidgetId,
          WidgetActionReceiver.ACTION_SET_TODO_MODE,
          WidgetActionReceiver.EXTRA_TODO_MODE,
          mode,
        ),
      )
    }

    private fun staleRow(
      context: Context,
      ui: WidgetSnapshot.UiStrings?,
      theme: WidgetSnapshot.ThemeBlock?,
      secondary: Int,
      appWidgetId: Int,
      todayMessage: Boolean,
    ): RemoteViews {
      val row = RemoteViews(context.packageName, R.layout.widget_todo_item)
      row.setViewVisibility(R.id.todo_check, View.GONE)
      row.setViewVisibility(R.id.todo_priority, View.GONE)
      row.setViewVisibility(R.id.todo_repeat, View.GONE)
      row.setViewVisibility(R.id.todo_tags, View.GONE)
      row.setViewVisibility(R.id.todo_meta, View.GONE)
      row.setTextViewText(
        R.id.todo_title,
        if (todayMessage) {
          ui?.openToUpdate ?: context.getString(R.string.widget_open_to_update)
        } else {
          ui?.stale ?: context.getString(R.string.widget_stale)
        },
      )
      WidgetSupport.textColor(row, R.id.todo_title, theme, "textSecondary", secondary)
      row.setOnClickPendingIntent(
        R.id.todo_item,
        WidgetSupport.openUri(context, WidgetSupport.todosUri("today"), appWidgetId + 605),
      )
      return row
    }

    private fun itemRow(
      context: Context,
      item: WidgetSnapshot.TodoItemRow,
      pending: WidgetSnapshot.PendingTargets,
      theme: WidgetSnapshot.ThemeBlock?,
      size: WidgetSize,
      mode: String,
      overdue: Boolean,
      error: Int,
      warning: Int,
      number: Int,
      appWidgetId: Int,
    ): RemoteViews {
      val primary = context.getColor(R.color.widget_text_primary)
      val secondary = context.getColor(R.color.widget_text_secondary)
      val accent = context.getColor(R.color.widget_accent)
      val row = RemoteViews(context.packageName, R.layout.widget_todo_item)

      val title = if (number > 0 && mode == "today") "$number. ${item.summary}" else item.summary
      row.setTextViewText(R.id.todo_title, title)

      val priorityColor = when (item.priority) {
        1 -> error
        in 2..4 -> warning
        else -> null
      }
      if (size == WidgetSize.SMALL || size == WidgetSize.MEDIUM) {
        row.setViewVisibility(R.id.todo_priority, View.GONE)
      } else if (priorityColor != null) {
        row.setViewVisibility(R.id.todo_priority, View.VISIBLE)
        WidgetSupport.tint(row, R.id.todo_priority, priorityColor)
      } else {
        row.setViewVisibility(R.id.todo_priority, View.INVISIBLE)
      }

      val meta = when {
        mode == "inbox" -> ""
        size == WidgetSize.SMALL -> ""
        overdue -> item.dueDate?.let { WidgetSupport.formatDate(it) } ?: ""
        mode == "all" || size == WidgetSize.LARGE -> item.dueDate?.let { WidgetSupport.formatDate(it) } ?: ""
        else -> ""
      }
      row.setTextViewText(R.id.todo_meta, meta)
      row.setViewVisibility(R.id.todo_meta, if (meta.isEmpty()) View.GONE else View.VISIBLE)
      WidgetSupport.textColor(
        row,
        R.id.todo_meta,
        theme,
        if (overdue) "error" else "textSecondary",
        if (overdue) error else secondary,
      )

      if (size == WidgetSize.LARGE && item.tagColors.isNotEmpty()) {
        row.setViewVisibility(R.id.todo_tags, View.VISIBLE)
        val ids = intArrayOf(R.id.todo_tag_0, R.id.todo_tag_1, R.id.todo_tag_2)
        for (index in ids.indices) {
          val color = item.tagColors.getOrNull(index)
          if (color == null) {
            row.setViewVisibility(ids[index], View.GONE)
          } else {
            row.setViewVisibility(ids[index], View.VISIBLE)
            WidgetSupport.tint(row, ids[index], WidgetSupport.parseColor(color, secondary))
          }
        }
      } else {
        row.setViewVisibility(R.id.todo_tags, View.GONE)
      }

      if (item.recurring) {
        row.setViewVisibility(R.id.todo_check, View.GONE)
        row.setViewVisibility(R.id.todo_repeat, View.VISIBLE)
        WidgetSupport.textColor(row, R.id.todo_repeat, theme, "textSecondary", secondary)
      } else if (item.todoId > 0) {
        row.setViewVisibility(R.id.todo_check, View.VISIBLE)
        row.setViewVisibility(R.id.todo_repeat, View.GONE)
        val isPending = WidgetSupport.isPending(pending, "todo", item.todoId, null)
        row.setImageViewResource(
          R.id.todo_check,
          if (isPending) R.drawable.widget_check_on else R.drawable.widget_check_off,
        )
        if (isPending) {
          WidgetSupport.tint(row, R.id.todo_check, theme?.colors?.get("accent") ?: accent)
        }
        row.setOnClickPendingIntent(
          R.id.todo_check,
          WidgetSupport.togglePendingIntent(
            context,
            "todo",
            item.todoId,
            item.todoSyncId,
            null,
            null,
          ),
        )
      } else {
        row.setViewVisibility(R.id.todo_check, View.GONE)
        row.setViewVisibility(R.id.todo_repeat, View.GONE)
      }

      if (item.todoId > 0) {
        row.setOnClickPendingIntent(
          R.id.todo_item,
          WidgetSupport.openUri(
            context,
            WidgetSupport.todoUri(item.todoId),
            (item.todoId * 37 + appWidgetId + 700) and 0x7FFFFFFF,
          ),
        )
      }
      WidgetSupport.textColor(row, R.id.todo_title, theme, "textPrimary", primary)
      return row
    }
  }
}
