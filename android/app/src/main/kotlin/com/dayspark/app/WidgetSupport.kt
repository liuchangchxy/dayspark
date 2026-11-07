package com.dayspark.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

internal enum class WidgetSize { SMALL, MEDIUM, LARGE }

internal object WidgetSupport {
  private const val TAG = "DaySparkWidget"

  fun dimensionsOf(manager: AppWidgetManager, appWidgetId: Int): Pair<Int, Int> {
    val options = manager.getAppWidgetOptions(appWidgetId)
    val width = maxOf(
      options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH),
      options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH),
    )
    val height = maxOf(
      options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT),
      options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT),
    )
    return width to height
  }

  fun sizeOf(manager: AppWidgetManager, appWidgetId: Int): WidgetSize {
    val (width, height) = dimensionsOf(manager, appWidgetId)
    return sizeFor(width, height)
  }

  fun sizeFor(width: Int, height: Int): WidgetSize = when {
    width >= 220 && height >= 220 -> WidgetSize.LARGE
    width >= 220 && height >= 140 -> WidgetSize.MEDIUM
    else -> WidgetSize.SMALL
  }

  fun calendarIsLarge(height: Int): Boolean = height >= 360

  fun render(
    context: Context,
    manager: AppWidgetManager,
    appWidgetId: Int,
    builder: () -> RemoteViews,
  ) {
    try {
      manager.updateAppWidget(appWidgetId, builder())
    } catch (t: Throwable) {
      Log.e(TAG, "widget render failed for $appWidgetId", t)
      try {
        manager.updateAppWidget(appWidgetId, fallback(context, appWidgetId))
      } catch (fallbackError: Throwable) {
        Log.e(TAG, "widget fallback failed for $appWidgetId", fallbackError)
      }
    }
  }

  fun fallback(context: Context, appWidgetId: Int): RemoteViews {
    val views = RemoteViews(context.packageName, R.layout.widget_fallback)
    views.setOnClickPendingIntent(
      R.id.fallback_root,
      openHome(context, appWidgetId),
    )
    return views
  }

  fun openHome(context: Context, requestSeed: Int): PendingIntent =
    openUri(context, Uri.parse("dayspark://open/home"), requestSeed)

  fun openUri(context: Context, uri: Uri, requestSeed: Int): PendingIntent {
    val intent = Intent(Intent.ACTION_VIEW, uri).apply {
      setClass(context, MainActivity::class.java)
      flags =
        Intent.FLAG_ACTIVITY_NEW_TASK or
          Intent.FLAG_ACTIVITY_CLEAR_TOP or
          Intent.FLAG_ACTIVITY_SINGLE_TOP
    }
    return PendingIntent.getActivity(
      context,
      requestSeed,
      intent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
  }

  fun todoUri(todoId: Int): Uri = Uri.parse("dayspark://open/todo?id=$todoId")

  fun eventUri(eventId: Int): Uri = Uri.parse("dayspark://open/event?id=$eventId")

  fun actionUri(): Uri = Uri.parse("dayspark://open/action")

  fun todosUri(view: String): Uri = Uri.parse("dayspark://open/todos?view=$view")

  fun calendarUri(dateIso: String): Uri =
    Uri.parse("dayspark://open/calendar?date=$dateIso")

  fun quickAddUri(dateIso: String?): Uri =
    if (dateIso.isNullOrEmpty()) {
      Uri.parse("dayspark://quick-add")
    } else {
      Uri.parse("dayspark://quick-add?date=$dateIso")
    }

  fun newEventUri(dateIso: String): Uri =
    Uri.parse("dayspark://open/new-event?date=$dateIso")

  fun stateIntent(
    context: Context,
    appWidgetId: Int,
    action: String,
    extraKey: String? = null,
    extraValue: String? = null,
  ): PendingIntent {
    val intent = Intent(context, WidgetActionReceiver::class.java).apply {
      this.action = action
      data = Uri.parse("dayspark://widget-state/$appWidgetId/$action/${extraValue ?: ""}")
      putExtra(WidgetActionReceiver.EXTRA_APP_WIDGET_ID, appWidgetId)
      if (extraKey != null && extraValue != null) putExtra(extraKey, extraValue)
    }
    val requestCode = (appWidgetId * 131 + action.hashCode() + (extraValue?.hashCode() ?: 0)) and 0x7FFFFFFF
    return PendingIntent.getBroadcast(
      context,
      requestCode,
      intent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
  }

  fun template(template: String, count: Int): String =
    template.replace("{n}", count.toString())

  fun togglePendingIntent(
    context: Context,
    target: String,
    todoId: Int,
    todoSyncId: String?,
    occurrenceId: String?,
    allocationId: String?,
  ): PendingIntent {
    val occPart = occurrenceId ?: "single"
    val allocPart = allocationId ?: "none"
    val intent = Intent(context, WidgetActionReceiver::class.java).apply {
      action = WidgetSnapshot.ACTION_COMPLETE_ACTION
      data = Uri.parse("dayspark://widget-toggle/$target/$todoId/$occPart/$allocPart")
      putExtra(WidgetSnapshot.EXTRA_TARGET, target)
      putExtra(WidgetSnapshot.EXTRA_TODO_ID, todoId)
      if (!todoSyncId.isNullOrEmpty()) putExtra(WidgetSnapshot.EXTRA_TODO_SYNC_ID, todoSyncId)
      if (!occurrenceId.isNullOrEmpty()) putExtra(WidgetSnapshot.EXTRA_OCCURRENCE_ID, occurrenceId)
      if (!allocationId.isNullOrEmpty()) putExtra(WidgetSnapshot.EXTRA_SOURCE_ALLOCATION_ID, allocationId)
    }
    val requestCode = (todoId * 37 + occPart.hashCode() + allocPart.hashCode()) and 0x7FFFFFFF
    return PendingIntent.getBroadcast(
      context,
      requestCode,
      intent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
  }

  fun isPending(
    targets: WidgetSnapshot.PendingTargets,
    target: String,
    todoId: Int,
    occurrenceId: String?,
  ): Boolean {
    return if (target == "taskInstance") {
      targets.instanceKeys.contains("$todoId:${occurrenceId ?: ""}")
    } else {
      targets.todoIds.contains(todoId)
    }
  }

  fun applyRoot(views: RemoteViews, rootId: Int, theme: WidgetSnapshot.ThemeBlock?) {
    val background = theme?.colors?.get("background")
    if (background != null) {
      views.setInt(rootId, "setBackgroundColor", background)
    }
  }

  fun textColor(
    views: RemoteViews,
    viewId: Int,
    theme: WidgetSnapshot.ThemeBlock?,
    key: String,
    fallback: Int,
  ) {
    views.setTextColor(viewId, theme?.colors?.get(key) ?: fallback)
  }

  fun tint(view: RemoteViews, viewId: Int, color: Int) {
    view.setInt(viewId, "setColorFilter", color)
  }

  fun parseColor(hex: String?, fallback: Int): Int {
    if (hex.isNullOrEmpty()) return fallback
    return WidgetSnapshot.parseHexColor(hex) ?: fallback
  }

  fun dayColor(hex: String?, fallback: Int): Int = parseColor(hex, fallback)

  fun isoDate(date: Date): String =
    SimpleDateFormat("yyyy-MM-dd", Locale.US).format(date)

  fun formatDate(iso: String): String {
    val parsed = runCatching {
      SimpleDateFormat("yyyy-MM-dd", Locale.US).parse(iso)
    }.getOrNull() ?: return iso
    return SimpleDateFormat("MMM d", Locale.getDefault()).format(parsed)
  }

  fun formatDayTitle(iso: String): String {
    val parsed = runCatching {
      SimpleDateFormat("yyyy-MM-dd", Locale.US).parse(iso)
    }.getOrNull() ?: return iso
    return SimpleDateFormat("MMM d EEE", Locale.getDefault()).format(parsed)
  }

  fun isLocalToday(iso: String): Boolean = iso == isoDate(Date())

  fun rowBudget(
    height: Int,
    headerDp: Int,
    footerDp: Int,
    rowDp: Int,
    min: Int,
    max: Int,
  ): Int {
    if (height <= 0) return min
    val available = height - headerDp - footerDp
    return (available / rowDp).coerceIn(min, max)
  }

  fun formatWeekday(iso: String): String {
    val parsed = runCatching {
      SimpleDateFormat("yyyy-MM-dd", Locale.US).parse(iso)
    }.getOrNull() ?: return ""
    return SimpleDateFormat("EEEE", Locale.getDefault()).format(parsed)
  }

  fun formatTimeRange(
    start: String,
    end: String,
    isAllDay: Boolean,
    allDayLabel: String,
  ): String {
    if (isAllDay) return allDayLabel
    return when {
      start.isEmpty() -> ""
      end.isEmpty() -> start
      else -> "$start - $end"
    }
  }

  fun monthTitle(year: Int, month: Int): String {
    val calendar = Calendar.getInstance().apply {
      set(year, month - 1, 1)
    }
    return SimpleDateFormat("MMMM yyyy", Locale.getDefault()).format(calendar.time)
  }

  fun todayIso(context: Context): String = isoDate(Date())

  fun setVisible(views: RemoteViews, viewId: Int, visible: Boolean) {
    views.setViewVisibility(viewId, if (visible) View.VISIBLE else View.GONE)
  }
}
