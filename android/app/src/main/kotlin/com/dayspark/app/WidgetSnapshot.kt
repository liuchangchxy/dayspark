package com.dayspark.app

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

// v3 `widget_snapshot` reader + native command queue operations (Rulings A, C, E, O).
//
// Every native widget renders from this snapshot blob; the snapshot is READ-ONLY
// for native code (Single-Writer rule). Widget actions append typed commands
// into independent SharedPreferences keys (`widget_command_<commandId>`).
data class WidgetSnapshot(val json: JSONObject) {

  val version: Int get() = json.optInt("version", 0)

  data class EventRow(val summary: String, val start: String, val isAllDay: Boolean)
  data class TodoRow(val id: Int?, val summary: String, val dueDate: String)
  data class UpcomingEventRow(
    val summary: String,
    val date: String,
    val start: String,
    val isAllDay: Boolean,
  )

  data class TimelineRow(
    val kind: String,
    val summary: String,
    val start: String,
    val end: String,
    val isAllDay: Boolean,
  )

  data class ActionRow(
    val kind: String,
    val target: String,
    val todoId: Int,
    val todoSyncId: String?,
    val occurrenceId: String?,
    val summary: String,
    val deadline: String?,
    val displayTime: String?,
  )

  data class UpcomingItemRow(
    val kind: String,
    val summary: String,
    val date: String,
    val time: String,
    val isAllDay: Boolean,
  )

  data class PendingTargets(
    val todoIds: Set<Int>,
    val instanceKeys: Set<String>,
  )

  fun todayTimeline(): List<TimelineRow> {
    val todayObj = json.optJSONObject("today")
    if (todayObj != null && todayObj.has("timeline")) {
      return todayObj.optJSONArray("timeline").toObjectList { o ->
        TimelineRow(
          kind = o.optString("kind", "eventOccurrence"),
          summary = o.optString("summary", ""),
          start = o.optString("start", ""),
          end = o.optString("end", ""),
          isAllDay = o.optBoolean("isAllDay", false),
        )
      }
    }
    return todayEvents().map {
      TimelineRow(
        kind = "eventOccurrence",
        summary = it.summary,
        start = it.start,
        end = "",
        isAllDay = it.isAllDay,
      )
    }
  }

  fun todayActions(): List<ActionRow> {
    val todayObj = json.optJSONObject("today")
    if (todayObj != null && todayObj.has("actions")) {
      return todayObj.optJSONArray("actions").toObjectList { o ->
        val target = o.optString("target", if (o.optString("kind") == "taskInstance") "taskInstance" else "todo")
        ActionRow(
          kind = o.optString("kind", "todoDeadline"),
          target = target,
          todoId = o.optInt("todoId", -1),
          todoSyncId = if (o.has("todoSyncId") && !o.isNull("todoSyncId")) o.optString("todoSyncId") else null,
          occurrenceId = if (o.has("occurrenceId") && !o.isNull("occurrenceId")) o.optString("occurrenceId") else null,
          summary = o.optString("summary", ""),
          deadline = if (o.has("deadline") && !o.isNull("deadline")) o.optString("deadline") else null,
          displayTime = if (o.has("displayTime") && !o.isNull("displayTime")) o.optString("displayTime") else null,
        )
      }
    }
    return pendingTodos().map {
      ActionRow(
        kind = "todoDeadline",
        target = "todo",
        todoId = it.id ?: -1,
        todoSyncId = null,
        occurrenceId = null,
        summary = it.summary,
        deadline = it.dueDate,
        displayTime = null,
      )
    }
  }

  fun upcomingItems(): List<UpcomingItemRow> {
    val upcomingObj = json.optJSONObject("upcoming")
    if (upcomingObj != null && upcomingObj.has("items")) {
      return upcomingObj.optJSONArray("items").toObjectList { o ->
        UpcomingItemRow(
          kind = o.optString("kind", ""),
          summary = o.optString("summary", ""),
          date = o.optString("date", ""),
          time = o.optString("time", ""),
          isAllDay = o.optBoolean("isAllDay", false),
        )
      }
    }
    val rows = mutableListOf<UpcomingItemRow>()
    for (e in upcomingEvents()) {
      rows.add(
        UpcomingItemRow(
          kind = "eventOccurrence",
          summary = e.summary,
          date = e.date,
          time = e.start,
          isAllDay = e.isAllDay,
        ),
      )
    }
    for (t in upcomingTodos()) {
      rows.add(
        UpcomingItemRow(
          kind = "todoDeadline",
          summary = t.summary,
          date = t.dueDate,
          time = "",
          isAllDay = false,
        ),
      )
    }
    return rows
  }

  fun todayEvents(): List<EventRow> = json.optJSONArray("todayEvents").toObjectList { o ->
    EventRow(
      summary = o.optString("summary", ""),
      start = o.optString("start", ""),
      isAllDay = o.optBoolean("isAllDay", false),
    )
  }

  fun pendingTodos(): List<TodoRow> = json.optJSONArray("pendingTodos").toObjectList { o ->
    TodoRow(
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
  // the legacy pendingTaps queue (for v2 backwards-compatibility).
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
    const val COMMAND_PREFIX = "widget_command_"
    const val ACTION_TOGGLE_TODO = "com.dayspark.app.action.TOGGLE_TODO"
    const val ACTION_COMPLETE_ACTION = "com.dayspark.app.action.COMPLETE_ACTION"
    const val EXTRA_TARGET = "target"
    const val EXTRA_TODO_ID = "todoId"
    const val EXTRA_TODO_SYNC_ID = "todoSyncId"
    const val EXTRA_OCCURRENCE_ID = "occurrenceId"
    const val EXTRA_SOURCE_ALLOCATION_ID = "sourceAllocationId"

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

    // Atomic single-writer command write: writes widget_command_<commandId> to prefs.
    // Does NOT mutate widget_snapshot (Ruling E).
    fun writeCommand(
      context: Context,
      target: String,
      todoId: Int,
      todoSyncId: String?,
      occurrenceId: String?,
      sourceAllocationId: String? = null,
    ): String {
      val commandId = java.util.UUID.randomUUID().toString()
      val atIso = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US).apply {
        timeZone = java.util.TimeZone.getTimeZone("UTC")
      }.format(java.util.Date())

      val obj = JSONObject().apply {
        put("version", 1)
        put("commandId", commandId)
        put("action", "complete")
        put("target", target)
        put("todoId", todoId)
        if (!todoSyncId.isNullOrEmpty()) put("todoSyncId", todoSyncId)
        if (!occurrenceId.isNullOrEmpty()) put("occurrenceId", occurrenceId)
        if (!sourceAllocationId.isNullOrEmpty()) put("sourceAllocationId", sourceAllocationId)
        put("at", atIso)
      }

      val editor = prefs(context).edit()
      editor.putString("$COMMAND_PREFIX$commandId", obj.toString())
      editor.commit()
      return commandId
    }

    fun readPendingCommands(context: Context): List<Map<String, Any?>> {
      val prefs = prefs(context)
      val list = mutableListOf<Map<String, Any?>>()
      for ((key, value) in prefs.all) {
        if (key.startsWith(COMMAND_PREFIX) && value is String) {
          try {
            val obj = JSONObject(value)
            val map = mutableMapOf<String, Any?>()
            val keys = obj.keys()
            while (keys.hasNext()) {
              val k = keys.next()
              if (!obj.isNull(k)) {
                map[k] = obj.get(k)
              } else {
                map[k] = null
              }
            }
            list.add(map)
          } catch (_: Exception) {}
        }
      }
      return list
    }

    fun ackCommand(context: Context, commandId: String): Boolean {
      val editor = prefs(context).edit()
      return editor.remove("$COMMAND_PREFIX$commandId").commit()
    }

    fun readPendingTargets(context: Context): PendingTargets {
      val prefs = prefs(context)
      val todoIds = mutableSetOf<Int>()
      val instanceKeys = mutableSetOf<String>()
      for ((key, value) in prefs.all) {
        if (key.startsWith(COMMAND_PREFIX) && value is String) {
          try {
            val obj = JSONObject(value)
            val target = obj.optString("target", "todo")
            val todoId = obj.optInt("todoId", -1)
            if (target == "taskInstance") {
              val occ = obj.optString("occurrenceId", "")
              if (todoId > 0 && occ.isNotEmpty()) {
                instanceKeys.add("$todoId:$occ")
              }
            } else if (target == "todo") {
              if (todoId > 0) {
                todoIds.add(todoId)
              }
            }
          } catch (_: Exception) {}
        }
      }
      val snap = read(context)
      if (snap != null) {
        todoIds.addAll(snap.pendingTapTodoIds())
      }
      return PendingTargets(todoIds = todoIds, instanceKeys = instanceKeys)
    }

    // Legacy v2 appendPendingTap retained for test backward compatibility.
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
