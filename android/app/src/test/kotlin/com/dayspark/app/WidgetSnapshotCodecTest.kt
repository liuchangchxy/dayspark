package com.dayspark.app

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// JVM-level codec tests for the v5 snapshot contract. Native widgets only ever
// read this blob; commands live in independent SharedPreferences keys.
class WidgetSnapshotCodecTest {

  private fun snapshotV5Json(): String {
    return """
      {
        "version": 5,
        "generatedAt": "2026-10-07T02:00:00.000Z",
        "today": "2026-10-07",
        "action": {
          "timeline": [
            {
              "kind": "eventOccurrence",
              "eventId": 101,
              "calendarId": 1,
              "summary": "Team Sync",
              "start": "10:00",
              "end": "11:00",
              "startEpochMs": 1791357600000,
              "endEpochMs": 1791361200000,
              "isAllDay": false,
              "color": "#2457D6"
            },
            {
              "kind": "taskAllocation",
              "allocationId": "201",
              "todoId": 10,
              "todoSyncId": "todo_sync_10",
              "occurrenceId": null,
              "summary": "Deep Work",
              "start": "14:00",
              "end": "15:00",
              "startEpochMs": 1791372000000,
              "endEpochMs": 1791375600000,
              "isAllDay": false
            }
          ],
          "dueToday": [
            {
              "kind": "todoDeadline",
              "target": "todo",
              "todoId": 11,
              "todoSyncId": "todo_sync_11",
              "occurrenceId": null,
              "summary": "Submit Taxes",
              "priority": 2,
              "dueDate": "2026-10-07",
              "dueEpochMs": 1791358800000,
              "displayTime": ""
            },
            {
              "kind": "taskInstance",
              "target": "taskInstance",
              "todoId": 12,
              "todoSyncId": "todo_sync_12",
              "occurrenceId": "occ_2026_10_07",
              "summary": "Standup Notes",
              "priority": 0,
              "displayTime": "09:00"
            }
          ],
          "overdue": [
            {
              "kind": "todoDeadline",
              "target": "todo",
              "todoId": 13,
              "todoSyncId": null,
              "occurrenceId": null,
              "summary": "Late Report",
              "priority": 1,
              "dueDate": "2026-10-05",
              "dueEpochMs": 1791187200000,
              "displayTime": ""
            }
          ],
          "counts": {"dueToday": 2, "overdue": 1, "completedToday": 3}
        },
        "todos": {
          "today": {
            "sixThingsCap": 6,
            "items": [
              {
                "todoId": 21,
                "todoSyncId": "todo_sync_21",
                "summary": "Write spec",
                "priority": 3,
                "dueDate": "2026-10-07",
                "dueEpochMs": 1791358800000,
                "hasTime": false,
                "recurring": false,
                "tagColors": ["#2457D6", "#BF3A32"]
              },
              {
                "todoId": 22,
                "todoSyncId": null,
                "summary": "Daily review",
                "priority": 0,
                "hasTime": false,
                "recurring": true,
                "tagColors": []
              }
            ],
            "overdue": [
              {
                "todoId": 23,
                "todoSyncId": null,
                "summary": "Overdue item",
                "priority": 0,
                "dueDate": "2026-10-01",
                "hasTime": false,
                "recurring": false,
                "tagColors": []
              }
            ],
            "completedCount": 2,
            "total": 2
          },
          "inbox": {
            "items": [
              {
                "todoId": 24,
                "todoSyncId": null,
                "summary": "Inbox item",
                "priority": 0,
                "hasTime": false,
                "recurring": false,
                "tagColors": []
              }
            ],
            "total": 1
          },
          "all": {
            "items": [
              {
                "todoId": 21,
                "todoSyncId": "todo_sync_21",
                "summary": "Write spec",
                "priority": 3,
                "dueDate": "2026-10-07",
                "hasTime": false,
                "recurring": false,
                "tagColors": []
              }
            ],
            "total": 4
          }
        },
        "month": {
          "year": 2026,
          "month": 10,
          "firstWeekday": 4,
          "today": 7,
          "days": [
            {
              "day": 7,
              "hasEvent": true,
              "hasTodo": true,
              "hasAllocation": false,
              "colors": ["#2457D6"],
              "itemCount": 2,
              "items": [
                {
                  "kind": "eventOccurrence",
                  "eventId": 101,
                  "summary": "Team Sync",
                  "start": "10:00",
                  "end": "11:00",
                  "startEpochMs": 1791357600000,
                  "endEpochMs": 1791361200000,
                  "isAllDay": false,
                  "hasTime": true,
                  "color": "#2457D6"
                },
                {
                  "kind": "todoDeadline",
                  "todoId": 11,
                  "summary": "Submit Taxes",
                  "start": "",
                  "hasTime": false,
                  "startEpochMs": 1791358800000
                }
              ]
            }
          ]
        },
        "ui": {
          "locale": "en",
          "today": "Today",
          "inbox": "Inbox",
          "all": "All",
          "noTodos": "No tasks",
          "allTodosDone": "All tasks done today",
          "noPlans": "No plans for today",
          "allPlansDone": "All plans done",
          "now": "Now",
          "later": "Later",
          "dueToday": "Due today",
          "overdue": "Overdue",
          "completedCount": "{n} completed",
          "moreCount": "{n} more",
          "overdueCount": "{n} overdue",
          "selectedDayEmpty": "Nothing on this day",
          "backToMonth": "Month",
          "openToUpdate": "Open DaySpark to update",
          "stale": "Data needs updating",
          "addTodo": "+ Task",
          "addEvent": "+ Event",
          "quickAddHint": "Add a task",
          "quickAddToday": "Today",
          "quickAddInbox": "Inbox",
          "save": "Save",
          "saveFailed": "Save failed",
          "allDay": "All day"
        },
        "theme": {
          "dark": true,
          "colors": {
            "background": "#121212",
            "surface": "#1E1E1E",
            "textPrimary": "#FFFFFF",
            "textSecondary": "#9E9E9E",
            "accent": "#0A84FF",
            "border": "#333333",
            "error": "#FF453A",
            "warning": "#FF9F0A"
          }
        }
      }
    """.trimIndent()
  }

  private fun snapshotV4Json(): String {
    return """
      {
        "version": 4,
        "generatedAt": "2026-10-07T02:00:00.000Z",
        "today": {"date": "2026-10-07", "timeline": [], "actions": [], "status": {}},
        "upcoming": {"items": []},
        "monthDots": [],
        "ui": {"locale": "en", "title": "DaySpark"},
        "theme": {"dark": false, "colors": {}}
      }
    """.trimIndent()
  }

  @Test
  fun `parses v5 action block`() {
    val snapshot = WidgetSnapshot.parse(snapshotV5Json())
    assertNotNull(snapshot)
    assertEquals(5, snapshot!!.version)
    assertEquals("2026-10-07", snapshot.todayIso())

    val action = snapshot.action()
    assertEquals(2, action.timeline.size)
    assertEquals("eventOccurrence", action.timeline[0].kind)
    assertEquals("Team Sync", action.timeline[0].summary)
    assertEquals(101, action.timeline[0].eventId)
    assertEquals("#2457D6", action.timeline[0].color)
    assertEquals(1791357600000L, action.timeline[0].startEpochMs)

    assertEquals("taskAllocation", action.timeline[1].kind)
    assertEquals("201", action.timeline[1].allocationId)
    assertEquals(10, action.timeline[1].todoId)
    assertNull(action.timeline[1].occurrenceId)

    assertEquals(2, action.dueToday.size)
    assertEquals("todoDeadline", action.dueToday[0].kind)
    assertEquals("todo", action.dueToday[0].target)
    assertEquals(2, action.dueToday[0].priority)
    assertEquals("taskInstance", action.dueToday[1].target)
    assertEquals("occ_2026_10_07", action.dueToday[1].occurrenceId)

    assertEquals(1, action.overdue.size)
    assertEquals(13, action.overdue[0].todoId)

    assertEquals(2, action.counts.dueToday)
    assertEquals(1, action.counts.overdue)
    assertEquals(3, action.counts.completedToday)
  }

  @Test
  fun `parses v5 todos block including recurring and tags`() {
    val todos = WidgetSnapshot.parse(snapshotV5Json())!!.todos()

    assertEquals(2, todos.today.items.size)
    assertEquals(1, todos.today.overdue.size)
    assertEquals(2, todos.today.completedCount)
    assertEquals(2, todos.today.total)
    assertEquals(6, todos.today.sixThingsCap)

    val first = todos.today.items[0]
    assertEquals(21, first.todoId)
    assertEquals(3, first.priority)
    assertEquals(listOf("#2457D6", "#BF3A32"), first.tagColors)
    assertFalse(first.recurring)

    val recurring = todos.today.items[1]
    assertTrue(recurring.recurring)
    assertNull(recurring.dueDate)

    assertEquals(1, todos.inbox.items.size)
    assertEquals(24, todos.inbox.items[0].todoId)
    assertEquals(4, todos.all.total)
    assertTrue(todos.inbox.overdue.isEmpty())
    assertTrue(todos.all.overdue.isEmpty())
  }

  @Test
  fun `parses v5 month days and items`() {
    val month = WidgetSnapshot.parse(snapshotV5Json())!!.month()
    assertNotNull(month)
    assertEquals(2026, month!!.year)
    assertEquals(10, month.month)
    assertEquals(4, month.firstWeekday)
    assertEquals(7, month.today)
    assertEquals(1, month.days.size)

    val day = month.days[0]
    assertEquals(7, day.day)
    assertTrue(day.hasEvent)
    assertTrue(day.hasTodo)
    assertFalse(day.hasAllocation)
    assertEquals(listOf("#2457D6"), day.colors)
    assertEquals(2, day.itemCount)
    assertEquals(2, day.items.size)

    val event = day.items[0]
    assertEquals("eventOccurrence", event.kind)
    assertEquals(101, event.eventId)
    assertEquals("10:00", event.start)

    val deadline = day.items[1]
    assertEquals("todoDeadline", deadline.kind)
    assertEquals(11, deadline.todoId)
    assertFalse(deadline.hasTime)
    assertEquals("", deadline.start)
  }

  @Test
  fun `rejects pre-v5 snapshots`() {
    assertNull(WidgetSnapshot.parse(null))
    assertNull(WidgetSnapshot.parse(""))
    assertNull(WidgetSnapshot.parse("not json"))
    assertNull(WidgetSnapshot.parse("""{"version":1}"""))
    assertNull(WidgetSnapshot.parse(snapshotV4Json()))
  }

  @Test
  fun `ui templates substitute counts and theme carries error plus warning`() {
    val snapshot = WidgetSnapshot.parse(snapshotV5Json())!!
    val ui = snapshot.ui()
    assertNotNull(ui)
    assertEquals("2 completed", ui!!.withCount(ui.completedCount, 2))
    assertEquals("3 more", ui.withCount(ui.moreCount, 3))
    assertEquals("1 overdue", ui.withCount(ui.overdueCount, 1))

    val theme = snapshot.theme()
    assertNotNull(theme)
    assertTrue(theme!!.dark)
    assertEquals(0xFFFF453A.toInt(), theme.colors["error"])
    assertEquals(0xFFFF9F0A.toInt(), theme.colors["warning"])
    assertEquals(0xFF0A84FF.toInt(), theme.colors["accent"])
  }

  @Test
  fun `missing blocks degrade to empty rather than crashing`() {
    val snapshot = WidgetSnapshot.parse("""{"version":5,"today":"2026-10-07"}""")
    assertNotNull(snapshot)
    assertEquals("2026-10-07", snapshot!!.todayIso())
    assertTrue(snapshot.action().timeline.isEmpty())
    assertTrue(snapshot.action().dueToday.isEmpty())
    assertEquals(0, snapshot.action().counts.dueToday)
    assertTrue(snapshot.todos().today.items.isEmpty())
    assertNull(snapshot.month())
    assertNull(snapshot.ui())
    assertNull(snapshot.theme())
  }

  @Test
  fun `normalized selected date resets outside the current month`() {
    val today = WidgetStateStore.todayIso()
    assertEquals(today, WidgetStateStore.normalizedSelectedDate(WidgetUiState()))
    assertEquals(today, WidgetStateStore.normalizedSelectedDate(WidgetUiState(selectedDate = "bad")))
    assertEquals(today, WidgetStateStore.normalizedSelectedDate(WidgetUiState(selectedDate = "2001-01-01")))
    assertEquals(today, WidgetStateStore.normalizedSelectedDate(WidgetUiState(selectedDate = today)))
  }

  @Test
  fun `hex colors accept RRGGBB and AARRGGBB`() {
    assertEquals(0xFF1976D2.toInt(), WidgetSnapshot.parseHexColor("#1976D2"))
    assertEquals(0x801976D2.toInt(), WidgetSnapshot.parseHexColor("#801976D2"))
    assertNull(WidgetSnapshot.parseHexColor("#XYZ"))
    assertNull(WidgetSnapshot.parseHexColor("#12345"))
  }

  @Test
  fun `writeCommand serializes sourceAllocationId and required fields`() {
    val obj = JSONObject().apply {
      put("version", 1)
      put("commandId", "cmd_test_1")
      put("action", "complete")
      put("target", "taskInstance")
      put("todoId", 15)
      put("todoSyncId", "sync_15")
      put("occurrenceId", "occ_2026")
      put("sourceAllocationId", "alloc_99")
      put("at", "2026-10-07T10:00:00.000Z")
    }
    assertEquals(1, obj.getInt("version"))
    assertEquals("taskInstance", obj.getString("target"))
    assertEquals(15, obj.getInt("todoId"))
    assertEquals("alloc_99", obj.getString("sourceAllocationId"))
  }
}
