package com.dayspark.app

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

// v5 `widget_snapshot` reader + native command queue operations.
//
// Every native widget renders from this snapshot blob; the snapshot is READ-ONLY
// for native code (Single-Writer rule). Widget actions append typed commands
// into independent SharedPreferences keys (`widget_command_<commandId>`).
data class WidgetSnapshot(val json: JSONObject) {

  val version: Int get() = json.optInt("version", 0)

  data class ActionTimelineRow(
    val kind: String,
    val summary: String,
    val start: String,
    val end: String,
    val startEpochMs: Long,
    val endEpochMs: Long,
    val isAllDay: Boolean,
    val eventId: Int? = null,
    val calendarId: Int? = null,
    val color: String? = null,
    val allocationId: String? = null,
    val todoId: Int? = null,
    val todoSyncId: String? = null,
    val occurrenceId: String? = null,
  )

  data class ActionTaskRow(
    val kind: String,
    val target: String,
    val summary: String,
    val todoId: Int,
    val todoSyncId: String?,
    val occurrenceId: String?,
    val displayTime: String?,
    val priority: Int,
    val dueEpochMs: Long?,
    val dueDate: String?,
    val startEpochMs: Long?,
  )

  data class ActionCounts(
    val dueToday: Int,
    val overdue: Int,
    val completedToday: Int,
  )

  data class ActionBlock(
    val timeline: List<ActionTimelineRow>,
    val dueToday: List<ActionTaskRow>,
    val overdue: List<ActionTaskRow>,
    val counts: ActionCounts,
  )

  data class TodoItemRow(
    val todoId: Int,
    val todoSyncId: String?,
    val summary: String,
    val priority: Int,
    val dueDate: String?,
    val dueEpochMs: Long?,
    val hasTime: Boolean,
    val recurring: Boolean,
    val tagColors: List<String>,
  )

  data class TodoModeBlock(
    val items: List<TodoItemRow>,
    val overdue: List<TodoItemRow>,
    val completedCount: Int,
    val total: Int,
    val sixThingsCap: Int,
  )

  data class TodosBlock(
    val today: TodoModeBlock,
    val inbox: TodoModeBlock,
    val all: TodoModeBlock,
  )

  data class MonthItemRow(
    val kind: String,
    val summary: String,
    val start: String,
    val end: String,
    val startEpochMs: Long?,
    val endEpochMs: Long?,
    val isAllDay: Boolean,
    val hasTime: Boolean,
    val color: String?,
    val eventId: Int?,
    val todoId: Int?,
    val todoSyncId: String?,
    val allocationId: String?,
    val occurrenceId: String?,
  )

  data class MonthDayRow(
    val day: Int,
    val hasEvent: Boolean,
    val hasTodo: Boolean,
    val hasAllocation: Boolean,
    val colors: List<String>,
    val itemCount: Int,
    val items: List<MonthItemRow>,
  )

  data class MonthRow(
    val year: Int,
    val month: Int,
    val firstWeekday: Int,
    val today: Int,
    val days: List<MonthDayRow>,
  )

  data class PendingTargets(
    val todoIds: Set<Int>,
    val instanceKeys: Set<String>,
  )

  fun todayIso(): String = json.optString("today", "")

  fun action(): ActionBlock {
    val o = json.optJSONObject("action") ?: return ActionBlock(
      emptyList(),
      emptyList(),
      emptyList(),
      ActionCounts(0, 0, 0),
    )
    val counts = o.optJSONObject("counts")
    return ActionBlock(
      timeline = o.optJSONArray("timeline").toObjectList { row ->
        ActionTimelineRow(
          kind = row.optString("kind", "eventOccurrence"),
          summary = row.optString("summary", ""),
          start = row.optString("start", ""),
          end = row.optString("end", ""),
          startEpochMs = row.optLong("startEpochMs", 0L),
          endEpochMs = row.optLong("endEpochMs", 0L),
          isAllDay = row.optBoolean("isAllDay", false),
          eventId = row.optionalInt("eventId"),
          calendarId = row.optionalInt("calendarId"),
          color = row.optionalString("color"),
          allocationId = row.optionalString("allocationId"),
          todoId = row.optionalInt("todoId"),
          todoSyncId = row.optionalString("todoSyncId"),
          occurrenceId = row.optionalString("occurrenceId"),
        )
      },
      dueToday = o.optJSONArray("dueToday").toObjectList(::taskRow),
      overdue = o.optJSONArray("overdue").toObjectList(::taskRow),
      counts = ActionCounts(
        dueToday = counts?.optInt("dueToday", 0) ?: 0,
        overdue = counts?.optInt("overdue", 0) ?: 0,
        completedToday = counts?.optInt("completedToday", 0) ?: 0,
      ),
    )
  }

  fun todos(): TodosBlock {
    val o = json.optJSONObject("todos")
    return TodosBlock(
      today = todoMode(o?.optJSONObject("today"), includeOverdue = true),
      inbox = todoMode(o?.optJSONObject("inbox"), includeOverdue = false),
      all = todoMode(o?.optJSONObject("all"), includeOverdue = false),
    )
  }

  fun month(): MonthRow? {
    val o = json.optJSONObject("month") ?: return null
    val rawDays = o.optJSONArray("days") ?: return null
    val days = mutableListOf<MonthDayRow>()
    for (i in 0 until rawDays.length()) {
      val day = rawDays.optJSONObject(i) ?: continue
      val colors = mutableListOf<String>()
      val rawColors = day.optJSONArray("colors")
      if (rawColors != null) {
        for (c in 0 until rawColors.length()) {
          val hex = rawColors.optString(c, "")
          if (hex.isNotEmpty()) colors.add(hex)
        }
      }
      days.add(
        MonthDayRow(
          day = day.optInt("day", 0),
          hasEvent = day.optBoolean("hasEvent", false),
          hasTodo = day.optBoolean("hasTodo", false),
          hasAllocation = day.optBoolean("hasAllocation", false),
          colors = colors,
          itemCount = day.optInt("itemCount", 0),
          items = day.optJSONArray("items").toObjectList { item ->
            MonthItemRow(
              kind = item.optString("kind", ""),
              summary = item.optString("summary", ""),
              start = item.optString("start", ""),
              end = item.optString("end", ""),
              startEpochMs = item.optionalLong("startEpochMs"),
              endEpochMs = item.optionalLong("endEpochMs"),
              isAllDay = item.optBoolean("isAllDay", false),
              hasTime = item.optBoolean("hasTime", false),
              color = item.optionalString("color"),
              eventId = item.optionalInt("eventId"),
              todoId = item.optionalInt("todoId"),
              todoSyncId = item.optionalString("todoSyncId"),
              allocationId = item.optionalString("allocationId"),
              occurrenceId = item.optionalString("occurrenceId"),
            )
          },
        ),
      )
    }
    return MonthRow(
      year = o.optInt("year", 0),
      month = o.optInt("month", 0),
      firstWeekday = o.optInt("firstWeekday", 1),
      today = o.optInt("today", 0),
      days = days,
    )
  }

  fun ui(): UiStrings? {
    val o = json.optJSONObject("ui") ?: return null
    return UiStrings(
      locale = o.optString("locale", ""),
      today = o.optString("today", ""),
      inbox = o.optString("inbox", ""),
      all = o.optString("all", ""),
      noTodos = o.optString("noTodos", ""),
      allTodosDone = o.optString("allTodosDone", ""),
      noPlans = o.optString("noPlans", ""),
      allPlansDone = o.optString("allPlansDone", ""),
      now = o.optString("now", ""),
      later = o.optString("later", ""),
      dueToday = o.optString("dueToday", ""),
      overdue = o.optString("overdue", ""),
      completedCount = o.optString("completedCount", "{n}"),
      moreCount = o.optString("moreCount", "{n}"),
      overdueCount = o.optString("overdueCount", "{n}"),
      selectedDayEmpty = o.optString("selectedDayEmpty", ""),
      backToMonth = o.optString("backToMonth", ""),
      openToUpdate = o.optString("openToUpdate", ""),
      stale = o.optString("stale", ""),
      addTodo = o.optString("addTodo", ""),
      addEvent = o.optString("addEvent", ""),
      quickAddHint = o.optString("quickAddHint", ""),
      quickAddToday = o.optString("quickAddToday", ""),
      quickAddInbox = o.optString("quickAddInbox", ""),
      save = o.optString("save", ""),
      saveFailed = o.optString("saveFailed", ""),
      allDay = o.optString("allDay", ""),
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
    val today: String,
    val inbox: String,
    val all: String,
    val noTodos: String,
    val allTodosDone: String,
    val noPlans: String,
    val allPlansDone: String,
    val now: String,
    val later: String,
    val dueToday: String,
    val overdue: String,
    val completedCount: String,
    val moreCount: String,
    val overdueCount: String,
    val selectedDayEmpty: String,
    val backToMonth: String,
    val openToUpdate: String,
    val stale: String,
    val addTodo: String,
    val addEvent: String,
    val quickAddHint: String,
    val quickAddToday: String,
    val quickAddInbox: String,
    val save: String,
    val saveFailed: String,
    val allDay: String,
  ) {
    fun withCount(template: String, count: Int): String =
      template.replace("{n}", count.toString())
  }

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
      "error",
      "warning",
    )

    fun prefs(context: Context): SharedPreferences =
      context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun read(context: Context): WidgetSnapshot? = parse(prefs(context).getString(SNAPSHOT_KEY, null))

    fun parse(raw: String?): WidgetSnapshot? {
      if (raw.isNullOrEmpty()) return null
      return try {
        val json = JSONObject(raw)
        if (json.optInt("version", 0) < 5) null else WidgetSnapshot(json)
      } catch (e: Exception) {
        null
      }
    }

    // Atomic single-writer command write: writes widget_command_<commandId> to prefs.
    // Does NOT mutate widget_snapshot.
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

    fun readPendingCommands(context: Context): List<Map<String, String>> {
      val prefs = prefs(context)
      val list = mutableListOf<Map<String, String>>()
      for ((key, value) in prefs.all) {
        if (key.startsWith(COMMAND_PREFIX) && value is String) {
          val commandId = key.removePrefix(COMMAND_PREFIX)
          list.add(
            mapOf(
              "commandId" to commandId,
              "raw" to value,
            ),
          )
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
      return PendingTargets(todoIds = todoIds, instanceKeys = instanceKeys)
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

    private fun taskRow(o: JSONObject): ActionTaskRow = ActionTaskRow(
      kind = o.optString("kind", "todoDeadline"),
      target = o.optString("target", if (o.optString("kind") == "taskInstance") "taskInstance" else "todo"),
      summary = o.optString("summary", ""),
      todoId = o.optInt("todoId", -1),
      todoSyncId = o.optionalString("todoSyncId"),
      occurrenceId = o.optionalString("occurrenceId"),
      displayTime = o.optionalString("displayTime"),
      priority = o.optInt("priority", 0),
      dueEpochMs = o.optionalLong("dueEpochMs"),
      dueDate = o.optionalString("dueDate"),
      startEpochMs = o.optionalLong("startEpochMs"),
    )

    private fun todoMode(o: JSONObject?, includeOverdue: Boolean): TodoModeBlock {
      if (o == null) return TodoModeBlock(emptyList(), emptyList(), 0, 0, 0)
      return TodoModeBlock(
        items = o.optJSONArray("items").toObjectList(::todoItem),
        overdue = if (includeOverdue) {
          o.optJSONArray("overdue").toObjectList(::todoItem)
        } else {
          emptyList()
        },
        completedCount = o.optInt("completedCount", 0),
        total = o.optInt("total", 0),
        sixThingsCap = o.optInt("sixThingsCap", 0),
      )
    }

    private fun todoItem(o: JSONObject): TodoItemRow {
      val colors = mutableListOf<String>()
      val rawColors = o.optJSONArray("tagColors")
      if (rawColors != null) {
        for (i in 0 until rawColors.length()) {
          val hex = rawColors.optString(i, "")
          if (hex.isNotEmpty()) colors.add(hex)
        }
      }
      return TodoItemRow(
        todoId = o.optInt("todoId", -1),
        todoSyncId = o.optionalString("todoSyncId"),
        summary = o.optString("summary", ""),
        priority = o.optInt("priority", 0),
        dueDate = o.optionalString("dueDate"),
        dueEpochMs = o.optionalLong("dueEpochMs"),
        hasTime = o.optBoolean("hasTime", false),
        recurring = o.optBoolean("recurring", false),
        tagColors = colors,
      )
    }
  }
}

private fun JSONObject.optionalInt(key: String): Int? =
  if (has(key) && !isNull(key)) optInt(key) else null

private fun JSONObject.optionalLong(key: String): Long? =
  if (has(key) && !isNull(key)) optLong(key) else null

private fun JSONObject.optionalString(key: String): String? =
  if (has(key) && !isNull(key)) optString(key) else null

private inline fun <T> JSONArray?.toObjectList(transform: (JSONObject) -> T): List<T> {
  val arr = this ?: return emptyList()
  val out = mutableListOf<T>()
  for (i in 0 until arr.length()) {
    val o = arr.optJSONObject(i) ?: continue
    out.add(transform(o))
  }
  return out
}
