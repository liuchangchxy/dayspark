package com.dayspark.app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews

// Todos / 待办: a read-only snapshot of today's task list. It never shows events
// or a timeline, never completes a task and never switches lists in place:
// every row is a deep link into the App. Overdue tasks stay under today's list.
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
      val size = WidgetSupport.sizeOf(manager, appWidgetId)
      val heightDp = WidgetSupport.dimensionsOf(manager, appWidgetId).second
      WidgetSupport.render(context, manager, appWidgetId) {
        build(context, appWidgetId, size, heightDp)
      }
    }

    // Size and height are passed in rather than read from the manager so the
    // layout and its row budget can be exercised at exact card sizes in tests.
    internal fun build(
      context: Context,
      appWidgetId: Int,
      size: WidgetSize,
      heightDp: Int,
    ): RemoteViews {
      val snapshot = WidgetSnapshot.read(context)
        ?: return WidgetSupport.fallback(context, appWidgetId)
      val ui = snapshot.ui()
      val theme = snapshot.theme()
      val layout = when (size) {
        WidgetSize.SMALL -> R.layout.widget_todos_small
        WidgetSize.MEDIUM -> R.layout.widget_todos_medium
        WidgetSize.LARGE -> R.layout.widget_todos_large
      }
      val views = RemoteViews(context.packageName, layout)
      WidgetSupport.applyRoot(context, views, R.id.todos_root, theme)

      // A 110dp pin is the declared minimum and still has to hold one 48dp row:
      // the 8dp padding plus the 48dp header leaves 46dp. Tightening the padding
      // in that band is the only way to honour both the minimum size and the
      // minimum touch target; taller cards keep the normal breathing room.
      // 112 is the last height where the normal padding leaves less than one
      // measured row (it budgets 49dp): the band has to include it, otherwise
      // 112 shows no row while 111 and 113 show one.
      val tight = size == WidgetSize.SMALL && heightDp in 1 until 113
      val paddingDp = when {
        tight -> 4
        size == WidgetSize.SMALL -> 8
        else -> 12
      }
      if (tight) {
        val edge = WidgetSupport.dpToPx(context, 4)
        views.setViewPadding(R.id.todos_root, edge, edge, edge, edge)
      }

      val mode = "today"
      val block = snapshot.todos()
      val current = block.today
      val todayMode = true
      val overdueRows = current.overdue
      val todayIso = snapshot.todayIso().ifEmpty { WidgetSupport.todayIso(context) }
      val snapshotStale = todayIso != WidgetSupport.todayIso(context)
      val todayStale = snapshotStale

      val primary = context.getColor(R.color.widget_text_primary)
      val secondary = context.getColor(R.color.widget_text_secondary)
      val accent = context.getColor(R.color.widget_accent)
      val error = theme?.colors?.get("error") ?: context.getColor(R.color.widget_error)
      val warning = theme?.colors?.get("warning") ?: theme?.colors?.get("accent") ?: accent

      val total = current.total + overdueRows.size
      views.setTextViewText(
        R.id.todos_mode,
        context.getString(R.string.widget_todos_name),
      )
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
      views.setOnClickPendingIntent(
        R.id.todos_mode,
        WidgetSupport.openUri(context, listUri, appWidgetId + 602),
      )
      if (size != WidgetSize.SMALL) {
        // The list chips used to switch today / inbox / all in place. The
        // widget is a snapshot now, so the chips are retired rather than left
        // as dead controls; the header still names the list it shows.
        views.setViewVisibility(R.id.todos_chip_today, View.GONE)
        views.setViewVisibility(R.id.todos_chip_inbox, View.GONE)
        views.setViewVisibility(R.id.todos_chip_all, View.GONE)
      }

      val addDate = todayIso
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
      val effectiveHeight = if (heightDp > 0) heightDp else 220
      // The chip row still occupies 48dp in every non-small layout, so it stays
      // in the budget even though its controls are hidden.
      val chipsDp = if (size == WidgetSize.SMALL) 0 else 48
      val budget = RowBudget(effectiveHeight - paddingDp * 2 - 48 - chipsDp)
      var overdueShown = 0
      var todayShown = 0

      fun rowHeight(item: WidgetSnapshot.TodoItemRow, overdue: Boolean): Int {
        val meta = metaText(item, size, mode, overdue)
        return WidgetSupport.todoRowHeightDp(
          context,
          meta.isNotEmpty(),
          showsTags(item, size),
          title = item.summary,
          meta = meta,
        )
      }

      fun addHeader(text: String) {
        val header = RemoteViews(context.packageName, R.layout.widget_action_section)
        header.setTextViewText(R.id.action_section, text)
        WidgetSupport.textColor(header, R.id.action_section, theme, "textSecondary", secondary)
        views.addView(R.id.todos_rows, header)
      }

      fun addItem(
        item: WidgetSnapshot.TodoItemRow,
        overdue: Boolean,
        number: Int,
      ): Boolean {
        if (!budget.take(rowHeight(item, overdue))) return false
        views.addView(
          R.id.todos_rows,
          itemRow(
            context, item, theme, size, mode,
            overdue = overdue, error = error, warning = warning,
            number = number, appWidgetId = appWidgetId,
          ),
        )
        return true
      }

      val staleText = if (todayStale) {
        ui?.openToUpdate ?: context.getString(R.string.widget_open_to_update)
      } else {
        ui?.stale ?: context.getString(R.string.widget_stale)
      }
      if (snapshotStale &&
        budget.take(WidgetSupport.todoRowHeightDp(context, false, false, title = staleText))
      ) {
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
      }

      if (!todayStale) {
        val showGroups = size == WidgetSize.LARGE && todayMode
        // The Today label is only worth a line when it separates two groups;
        // a plain today list needs no header of its own.
        val showTodayHeader = showGroups && overdueRows.isNotEmpty()
        if (todayMode && overdueRows.isNotEmpty()) {
          val firstHeight = rowHeight(overdueRows.first(), true)
          // A group header with no room for a row under it is a dead label and
          // it also costs a row its space, so the two are taken together.
          val headerFits = !showGroups ||
            budget.remainingDp >= WidgetSupport.SECTION_DP + firstHeight
          if (headerFits) {
            if (showGroups) {
              budget.take(WidgetSupport.SECTION_DP)
              addHeader(ui?.overdue ?: context.getString(R.string.widget_overdue))
            }
            for (item in overdueRows) {
              if (!addItem(item, overdue = true, number = 0)) break
              overdueShown++
            }
          }
        }

        if (current.items.isNotEmpty()) {
          val firstHeight = rowHeight(current.items.first(), false)
          val headerNeeded = showTodayHeader
          val headerFits = !headerNeeded ||
            budget.remainingDp >= WidgetSupport.SECTION_DP + firstHeight
          if (headerFits) {
            if (headerNeeded) {
              budget.take(WidgetSupport.SECTION_DP)
              addHeader(ui?.today ?: context.getString(R.string.widget_today))
            }
            for (item in current.items) {
              if (!addItem(item, overdue = false, number = todayShown + 1)) break
              todayShown++
            }
          }
        }
      }

      // Today's completed rows stay under the open ones as a read-only record.
      // They are not part of `total` (open tasks), so the "more" row is not
      // affected; when the budget runs out they are simply not drawn. A tap
      // on any of them opens the item, exactly like an open row.
      var completedShown = 0
      if (!todayStale && todayMode && current.completed.isNotEmpty()) {
        for (item in current.completed) {
          if (!addItem(item, overdue = false, number = 0)) break
          completedShown++
        }
      }

      val emitted = overdueShown + todayShown
      val more = total - emitted
      val moreText = ui?.withCount(ui.moreCount, more)
        ?: context.getString(R.string.widget_more_count, more)
      if (!todayStale && more > 0 &&
        budget.take(
          WidgetSupport.todoRowHeightDp(context, hasMeta = false, hasTags = false, title = moreText),
        )
      ) {
        val moreRow = RemoteViews(context.packageName, R.layout.widget_todo_item)
        moreRow.setViewVisibility(R.id.todo_check, View.GONE)
        moreRow.setViewVisibility(R.id.todo_priority, View.GONE)
        moreRow.setViewVisibility(R.id.todo_repeat, View.GONE)
        moreRow.setViewVisibility(R.id.todo_meta, View.GONE)
        moreRow.setViewVisibility(R.id.todo_tags, View.GONE)
        moreRow.setTextViewText(R.id.todo_title, moreText)
        WidgetSupport.textColor(moreRow, R.id.todo_title, theme, "accent", accent)
        WidgetSupport.bindOpen(
          moreRow,
          WidgetRows.TODO_OPEN_IDS,
          WidgetSupport.openUri(context, listUri, appWidgetId + 604),
        )
        views.addView(R.id.todos_rows, moreRow)
      }

      // "No tasks" is a statement about the data, not about how many rows
      // happened to fit; a short card must not claim the list is empty. A card
      // whose only tasks are completed ones is not empty either: it is drawing
      // the completed rows, so "all done" would sit on top of them.
      val hasTasks = current.items.isNotEmpty() ||
        overdueRows.isNotEmpty() ||
        current.total > 0 ||
        completedShown > 0
      val empty = !todayStale && !hasTasks
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
      WidgetSupport.bindOpen(
        row,
        WidgetRows.TODO_OPEN_IDS,
        WidgetSupport.openUri(context, WidgetSupport.todosUri("today"), appWidgetId + 605),
      )
      return row
    }

    private fun metaText(
      item: WidgetSnapshot.TodoItemRow,
      size: WidgetSize,
      mode: String,
      overdue: Boolean,
    ): String = when {
      mode == "inbox" -> ""
      size == WidgetSize.SMALL -> ""
      overdue -> item.dueDate?.let { WidgetSupport.formatDate(it) } ?: ""
      mode == "all" || size == WidgetSize.LARGE ->
        item.dueDate?.let { WidgetSupport.formatDate(it) } ?: ""
      else -> ""
    }

    private fun showsTags(item: WidgetSnapshot.TodoItemRow, size: WidgetSize): Boolean =
      size == WidgetSize.LARGE && item.tagColors.isNotEmpty()

    internal fun itemRow(
      context: Context,
      item: WidgetSnapshot.TodoItemRow,
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

      val meta = metaText(item, size, mode, overdue)
      row.setTextViewText(R.id.todo_meta, meta)
      row.setViewVisibility(R.id.todo_meta, if (meta.isEmpty()) View.GONE else View.VISIBLE)
      WidgetSupport.textColor(
        row,
        R.id.todo_meta,
        theme,
        if (overdue) "error" else "textSecondary",
        if (overdue) error else secondary,
      )

      if (showsTags(item, size)) {
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
        // The circle is a read-only state glyph: completed rows keep the filled
        // check, and the tap anywhere in the row (including the circle) opens
        // the item instead of changing it.
        row.setImageViewResource(
          R.id.todo_check,
          if (item.completed) R.drawable.widget_check_on else R.drawable.widget_check_off,
        )
        if (item.completed) {
          WidgetSupport.tint(row, R.id.todo_check, theme?.colors?.get("accent") ?: accent)
        }
      } else {
        row.setViewVisibility(R.id.todo_check, View.GONE)
        row.setViewVisibility(R.id.todo_repeat, View.GONE)
      }

      if (item.todoId > 0) {
        val open = WidgetSupport.openUri(
          context,
          WidgetSupport.todoUri(item.todoId),
          (item.todoId * 37 + appWidgetId + 700) and 0x7FFFFFFF,
        )
        WidgetSupport.bindOpen(row, WidgetRows.TODO_OPEN_IDS, open)
        row.setOnClickPendingIntent(R.id.todo_check, open)
      } else {
        WidgetSupport.bindOpen(
          row,
          WidgetRows.TODO_OPEN_IDS,
          WidgetSupport.openUri(context, WidgetSupport.todosUri(mode), appWidgetId + 606),
        )
      }
      if (item.completed) {
        // Completed rows stay as a read-only record, muted and struck through;
        // their circle opens the item like every other point in the row.
        WidgetSupport.textColor(row, R.id.todo_title, theme, "textSecondary", secondary)
        row.setInt(
          R.id.todo_title,
          "setPaintFlags",
          android.graphics.Paint.STRIKE_THRU_TEXT_FLAG,
        )
      } else {
        WidgetSupport.textColor(row, R.id.todo_title, theme, "textPrimary", primary)
      }
      return row
    }
  }
}
