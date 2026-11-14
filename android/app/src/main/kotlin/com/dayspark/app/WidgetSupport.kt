package com.dayspark.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
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
    val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
    val maxWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH)
    val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
    val maxHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
    // A widget in portrait is always at least as wide as in landscape and at
    // least as tall as it is in landscape, so the portrait size is min(width)
    // and max(height). This launcher reports the pair the other way round —
    // a 1x5 pin came back as 116x163 with a 238x333 landscape size — and the
    // widget was drawn at the larger size anyway. Taking min width and max
    // height picks the frame the launcher actually draws, whichever way it
    // labels the two, and keeps a wide short widget from sizing itself as if
    // it spanned the landscape columns.
    val width = minWidth.takeIf { it > 0 } ?: maxWidth
    val height = maxOf(minHeight, maxHeight)
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

  // Calendar geometry. The month grid used to be a fixed 27/32dp cell whatever
  // the card height, so a taller widget wasted the extra space and a 4x4 card
  // clipped the selected day's list instead of shrinking it. Both are derived
  // from the real height now: cells take an equal share of what is left after
  // the card's chrome and two list rows, and the list gets exactly the rows
  // that still fit.
  private const val CALENDAR_HEADER_DP = 48
  private const val CALENDAR_WEEKDAYS_DP = 24
  private const val CALENDAR_TITLE_DP = 18
  private const val CALENDAR_LIST_ROW_DP = 48
  private const val CALENDAR_CELL_MAX_DP = 44

  // 24dp exists only for the case the declared minimum creates: a 250dp card
  // with a six-week month cannot hold 6 * 27dp plus the chrome, and a clipped
  // week row is worse than a small one.
  private const val CALENDAR_CELL_TIGHT_DP = 24
  private val CALENDAR_CELL_STEPS = intArrayOf(24, 27, 32, 36, 40, 44)

  fun calendarChromeDp(large: Boolean): Int =
    (if (large) 24 else 16) +
      CALENDAR_HEADER_DP +
      CALENDAR_WEEKDAYS_DP +
      (if (large) 13 else 0) +
      CALENDAR_TITLE_DP

  fun calendarMinCellDp(large: Boolean): Int = if (large) 32 else 27

  // Snapped to a layout that exists: the cell is a fixed-height RemoteViews
  // layout, so a computed 34 would render at 36 and overflow the grid budget.
  fun calendarCellHeightDp(height: Int, rows: Int, large: Boolean): Int {
    val min = calendarMinCellDp(large)
    if (height <= 0 || rows <= 0) return min
    val chrome = calendarChromeDp(large)
    if (chrome + min * rows > height) {
      // Not even the nominal grid fits. Give the grid every dp the card has and
      // let the day list take what is left (usually nothing).
      val tight = (height - chrome) / rows
      return CALENDAR_CELL_STEPS.lastOrNull { it <= tight && it >= CALENDAR_CELL_TIGHT_DP }
        ?: CALENDAR_CELL_TIGHT_DP
    }
    val raw = (height - chrome - 2 * CALENDAR_LIST_ROW_DP) / rows
    val clamped = raw.coerceIn(min, CALENDAR_CELL_MAX_DP)
    return CALENDAR_CELL_STEPS.lastOrNull { it in min..clamped } ?: min
  }

  fun calendarSummaryRows(
    height: Int,
    cellDp: Int,
    rows: Int,
    large: Boolean,
  ): Int {
    val nominal = if (large) 2 else 1
    if (height <= 0) return nominal
    val remaining = height - calendarChromeDp(large) - cellDp * rows
    return (remaining / CALENDAR_LIST_ROW_DP).coerceIn(0, if (large) 6 else 2)
  }

  // Day mode replaces the grid with the day bar, so the list owns the height.
  // Only the compact (non-large) card has a day mode, so there is one geometry.
  fun calendarDayRows(height: Int): Int {
    if (height <= 0) return 2
    val remaining = height -
      16 -
      CALENDAR_HEADER_DP -
      CALENDAR_LIST_ROW_DP -
      CALENDAR_TITLE_DP
    return (remaining / CALENDAR_LIST_ROW_DP).coerceIn(1, 6)
  }

  fun calendarCellLayout(cellDp: Int): Int = when {
    cellDp <= 24 -> R.layout.widget_calendar_cell_24
    cellDp <= 27 -> R.layout.widget_calendar_cell_small
    cellDp <= 32 -> R.layout.widget_calendar_cell
    cellDp <= 36 -> R.layout.widget_calendar_cell_36
    cellDp <= 40 -> R.layout.widget_calendar_cell_40
    else -> R.layout.widget_calendar_cell_44
  }

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

  fun applyRoot(
    context: Context,
    views: RemoteViews,
    rootId: Int,
    theme: WidgetSnapshot.ThemeBlock?,
  ) {
    // The root is a rounded, hairline-bordered surface, so a flat colour would
    // square off its corners. Two drawables keep the shape while letting the
    // snapshot's brightness pick the paper: every text colour already comes from
    // the snapshot, and a root that followed values-night instead could put dark
    // ink on dark paper whenever the app and the system disagree. With no
    // snapshot there is nothing to follow, so the system's own mode is used.
    val dark = theme?.dark ?: isSystemDark(context)
    val res = if (dark) R.drawable.widget_root_bg_dark else R.drawable.widget_root_bg
    views.setInt(rootId, "setBackgroundResource", res)
  }

  fun isSystemDark(context: Context): Boolean =
    (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
      Configuration.UI_MODE_NIGHT_YES

  fun borderColor(context: Context, theme: WidgetSnapshot.ThemeBlock?): Int =
    theme?.colors?.get("border")
      ?: context.getColor(
        if (isSystemDark(context)) R.color.widget_border_dark else R.color.widget_border_light,
      )

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

  // Action card chrome: root padding, the 48dp date header and one 24dp header
  // per section that will actually be drawn. The footer is 48dp and only there
  // when the completed line is visible.
  fun actionChromeDp(small: Boolean, sectionHeaders: Int): Int =
    (if (small) 16 else 24) + 48 + sectionHeaders * 24

  fun actionFooterDp(completedCount: Int): Int = if (completedCount > 0) 48 else 0

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
