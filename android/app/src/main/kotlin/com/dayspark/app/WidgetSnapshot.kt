package com.dayspark.app

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

// v2 `widget_snapshot` reader + the native side of the pendingTaps queue.
//
// Every native widget renders from this one blob; the legacy three keys
// (today_events / pending_todos / todo_count) are only a downlevel
// fallback while dual-write is still in effect.
data class WidgetSnapshot(val json: JSONObject) {

  data class EventRow(val summary: String, val start: String, val isAllDay: Boolean)
  data class TodoRow(val id: Int?, val summary: String, val dueDate: String)
  data class UpcomingEventRow(
    val summary: String,
    val date: String,
    val start: String,
    val isAllDay: Boolean,
  )

  fun todayEvents(): List<EventRow> = json.optJSONArray("todayEvents").toObjectList { o ->
    EventRow(
      summary = o.optString("summary", ""),
      start = o.optString("start", ""),
      isAllDay = o.optBoolean("isAllDay", false),
    )
  }

  fun pendingTodos(): List<TodoRow> = json.optJSONArray("pendingTodos").toObjectList { o ->
    TodoRow(
      // Legacy-only snapshots predate `id`; taps are disabled there.
      id = if (o.has("id")) o.optInt("id") else null,
      summary = o.optString("summary", ""),
      dueDate = o.optString("dueDate", ""),
    )
  }

  fun todoCount(): Int = json.optInt("todoCount", 0)

  fun upcomingEvents(): List<UpcomingEventRow> =
    json.optJSONObject("upcoming")?.optJSONArray("events").toObjectList { o ->
      UpcomingEventRow(
        summary = o.optString("summary", ""),
        date = o.optString("date", ""),
        start = o.optString("start", ""),
        isAllDay = o.optBoolean("isAllDay", false),
      )
    }

  fun upcomingTodos(): List<TodoRow> =
    json.optJSONObject("upcoming")?.optJSONArray("todos").toObjectList { o ->
      TodoRow(
        id = if (o.has("id")) o.optInt("id") else null,
        summary = o.optString("summary", ""),
        dueDate = o.optString("dueDate", ""),
      )
    }

  // [[dayNumber, hasEvent]] pairs — presence of the pair marks the day.
  fun monthDots(): Set<Int> {
    val out = mutableSetOf<Int>()
    val arr = json.optJSONArray("monthDots") ?: return out
    for (i in 0 until arr.length()) {
      val pair = arr.optJSONArray(i) ?: continue
      if (pair.length() >= 2 && pair.optBoolean(1, false)) {
        out.add(pair.optInt(0, -1))
      }
    }
    return out
  }

  // Optimistic checkbox state: a todo renders checked while its id sits in
  // the pendingTaps queue (cleared by the app's next flush after consume).
  fun pendingTapTodoIds(): Set<Int> {
    val out = mutableSetOf<Int>()
    val arr = json.optJSONArray("pendingTaps") ?: return out
    for (i in 0 until arr.length()) {
      val o = arr.optJSONObject(i) ?: continue
      out.add(o.optInt("todoId", -1))
    }
    return out
  }

  fun ui(): UiStrings? {
    val o = json.optJSONObject("ui") ?: return null
    return UiStrings(
      locale = o.optString("locale", ""),
      title = o.optString("title", ""),
      today = o.optString("today", ""),
      events = o.optString("events", ""),
      todos = o.optString("todos", ""),
      allDay = o.optString("allDay", ""),
      todayEventsHeader = o.optString("todayEventsHeader", ""),
      noEvents = o.optString("noEvents", ""),
      allDone = o.optString("allDone", ""),
      pendingCount = o.optString("pendingCount", ""),
      quickAdd = o.optString("quickAdd", ""),
      upcoming = o.optString("upcoming", ""),
    )
  }

  fun theme(): ThemeBlock? {
    val o = json.optJSONObject("theme") ?: return null
    val colors = o.optJSONObject("colors") ?: return null
    val parsed = mutableMapOf<String, Int>()
    for (key in COLOR_KEYS) {
      val hex = colors.optString(key, "")
      if (hex.isNotEmpty()) {
        parsed[key] = parseHexColor(hex) ?: continue
      }
    }
    return ThemeBlock(dark = o.optBoolean("dark", false), colors = parsed)
  }

  fun color(key: String, fallback: Int): Int = theme()?.colors?.get(key) ?: fallback

  data class UiStrings(
    val locale: String,
    val title: String,
    val today: String,
    val events: String,
    val todos: String,
    val allDay: String,
    val todayEventsHeader: String,
    val noEvents: String,
    val allDone: String,
    val pendingCount: String,
    val quickAdd: String,
    val upcoming: String,
  )

  data class ThemeBlock(val dark: Boolean, val colors: Map<String, Int>)

  companion object {
    const val PREFS_NAME = "HomeWidgetPreferences"
    const val SNAPSHOT_KEY = "widget_snapshot"
    const val ACTION_TOGGLE_TODO = "com.dayspark.app.action.TOGGLE_TODO"
    const val EXTRA_TODO_ID = "todoId"

    private val COLOR_KEYS = listOf(
      "background",
      "surface",
      "textPrimary",
      "textSecondary",
      "accent",
      "border",
    )

    fun prefs(context: Context): SharedPreferences =
      context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun read(context: Context): WidgetSnapshot? = parse(prefs(context).getString(SNAPSHOT_KEY, null))

    fun parse(raw: String?): WidgetSnapshot? {
      if (raw.isNullOrEmpty()) return null
      return try {
        val json = JSONObject(raw)
        if (json.optInt("version", 0) < 2) null else WidgetSnapshot(json)
      } catch (e: Exception) {
        null
      }
    }

    // Append-only mutation of the shared snapshot — single-writer rule:
    // native never touches the database and never rewrites other fields.
    // Read-modify-write on the one stored JSON blob, mutating ONLY
    // pendingTaps. Same-todoId taps are last-wins (a re-tap replaces the
    // queued entry instead of double-queueing an already pending complete).
    // WHY last-wins: the app consumes via a toggle path — a duplicated
    // entry would reopen the todo it just completed. Known race (accepted
    // in docs/CONSTRAINTS.md): a flush in flight may overwrite a tap that
    // lands inside its read→write window.
    fun appendPendingTap(raw: String?, todoId: Int, atIso: String): String? {
      val json = try {
        if (raw.isNullOrEmpty()) return null
        JSONObject(raw)
      } catch (e: Exception) {
        return null
      }
      val taps = json.optJSONArray("pendingTaps") ?: JSONArray()
      val kept = JSONArray()
      for (i in 0 until taps.length()) {
        val tap = taps.optJSONObject(i) ?: continue
        if (tap.optInt("todoId", -1) != todoId) {
          kept.put(tap)
        }
      }
      kept.put(
        JSONObject()
          .put("todoId", todoId)
          .put("action", "complete")
          .put("at", atIso),
      )
      json.put("pendingTaps", kept)
      return json.toString()
    }

    fun appendPendingTap(context: Context, todoId: Int, atIso: String): Boolean {
      val editor = prefs(context).edit()
      val updated = appendPendingTap(
        prefs(context).getString(SNAPSHOT_KEY, null),
        todoId,
        atIso,
      ) ?: return false
      // commit(), not apply(): the follow-up widget refresh reads the value
      // back immediately — apply's async disk write is fine but commit keeps
      // read-after-write ordering obvious under the broadcast that follows.
      return editor.putString(SNAPSHOT_KEY, updated).commit()
    }

    fun parseHexColor(hex: String): Int? {
      val cleaned = hex.removePrefix("#")
      return try {
        when (cleaned.length) {
          6 -> (0xFF000000L or cleaned.toLong(16)).toInt()
          8 -> cleaned.toLong(16).toInt()
          else -> null
        }
      } catch (e: NumberFormatException) {
        null
      }
    }
  }
}

private inline fun <T> JSONArray?.toObjectList(transform: (JSONObject) -> T): List<T> {
  val arr = this ?: return emptyList()
  val out = mutableListOf<T>()
  for (i in 0 until arr.length()) {
    val o = arr.optJSONObject(i) ?: continue
    out.add(transform(o))
  }
  return out
}
