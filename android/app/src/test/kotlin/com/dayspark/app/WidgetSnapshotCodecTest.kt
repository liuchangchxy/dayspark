package com.dayspark.app

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// JVM-level codec tests: verifies v3 parsing, typed command queue operations,
// and v2 backward-compatibility contracts.
class WidgetSnapshotCodecTest {

  private fun snapshotV2Json(
    pendingTaps: String = "[]",
    todoId: Int? = 7,
  ): String {
    val todo = if (todoId != null) {
      """{"id":$todoId,"summary":"Write tests","dueDate":"9/30"}"""
    } else {
      """{"summary":"Write tests","dueDate":"9/30"}"""
    }
    return """
      {
        "version": 2,
        "generatedAt": "2026-09-24T04:00:00Z",
        "todayEvents": [{"summary":"Standup","start":"10:00","isAllDay":false}],
        "pendingTodos": [$todo],
        "todoCount": 1,
        "upcoming": {"events":[],"todos":[]},
        "pendingTaps": $pendingTaps,
        "monthDots": [[3, true], [15, true]],
        "ui": {"locale":"en","title":"DaySpark","today":"Today","events":"Events",
               "todos":"Todos","allDay":"All day","todayEventsHeader":"Today's Events",
               "noEvents":"No events","allDone":"All done","pendingCount":"1 pending",
               "quickAdd":"Quick add","upcoming":"Upcoming"},
        "theme": {"dark":true,"colors":{"background":"#121212","surface":"#1E1E1E",
                  "textPrimary":"#FFFFFF","textSecondary":"#9E9E9E",
                  "accent":"#90CAF9","border":"#333333"}}
      }
    """.trimIndent()
  }

  private fun snapshotV3Json(): String {
    return """
      {
        "version": 3,
        "generatedAt": "2026-10-07T00:00:00Z",
        "today": {
          "timeline": [
            {
              "kind": "eventOccurrence",
              "id": "event_101",
              "summary": "Team Sync",
              "start": "10:00",
              "end": "11:00",
              "isAllDay": false
            },
            {
              "kind": "taskAllocation",
              "allocationId": "alloc_201",
              "todoId": 10,
              "todoSyncId": "todo_sync_10",
              "occurrenceId": null,
              "summary": "Deep Work",
              "start": "14:00",
              "end": "15:00",
              "isAllDay": false
            }
          ],
          "actions": [
            {
              "kind": "todoDeadline",
              "todoId": 11,
              "todoSyncId": "todo_sync_11",
              "summary": "Submit Taxes",
              "deadline": "10/7",
              "target": "todo"
            },
            {
              "kind": "taskInstance",
              "todoId": 12,
              "todoSyncId": "todo_sync_12",
              "occurrenceId": "2026-10-07T09:00:00.000Z",
              "summary": "Standup Notes",
              "displayTime": "09:00",
              "target": "taskInstance"
            }
          ],
          "status": {
            "overdueCount": 1,
            "missedCount": 0,
            "unplannedCount": 3
          }
        },
        "upcoming": {
          "items": [
            {
              "kind": "eventOccurrence",
              "summary": "Board Meeting",
              "date": "10/8",
              "time": "09:00",
              "isAllDay": false
            },
            {
              "kind": "taskAllocation",
              "summary": "Write Report",
              "date": "10/9",
              "time": "14:00 - 15:30",
              "isAllDay": false
            }
          ]
        },
        "monthDots": [[7, true], [8, true]],
        "ui": {"locale":"en","title":"DaySpark","today":"Today","events":"Events",
               "todos":"Todos","allDay":"All day","todayEventsHeader":"Today's Events",
               "noEvents":"No events","allDone":"All done","pendingCount":"2 pending",
               "quickAdd":"Quick add","upcoming":"Upcoming",
               "overdue":"Overdue","missed":"Missed","unplanned":"Inbox"},
        "theme": {"dark":true,"colors":{"background":"#121212","surface":"#1E1E1E",
                  "textPrimary":"#FFFFFF","textSecondary":"#9E9E9E",
                  "accent":"#90CAF9","border":"#333333"}}
      }
    """.trimIndent()
  }

  @Test
  fun `parses v3 snapshot timeline, actions and upcoming items`() {
    val snapshot = WidgetSnapshot.parse(snapshotV3Json())
    assertNotNull(snapshot)
    assertEquals(3, snapshot!!.version)

    val timeline = snapshot.todayTimeline()
    assertEquals(2, timeline.size)
    assertEquals("eventOccurrence", timeline[0].kind)
    assertEquals("Team Sync", timeline[0].summary)
    assertEquals("10:00", timeline[0].start)
    assertEquals("taskAllocation", timeline[1].kind)
    assertEquals("Deep Work", timeline[1].summary)
    assertEquals("alloc_201", timeline[1].allocationId)
    assertEquals(10, timeline[1].todoId)
    assertEquals("todo_sync_10", timeline[1].todoSyncId)
    assertNull(timeline[1].occurrenceId)

    val actions = snapshot.todayActions()
    assertEquals(2, actions.size)
    assertEquals("todoDeadline", actions[0].kind)
    assertEquals("todo", actions[0].target)
    assertEquals(11, actions[0].todoId)
    assertEquals("Submit Taxes", actions[0].summary)

    assertEquals("taskInstance", actions[1].kind)
    assertEquals("taskInstance", actions[1].target)
    assertEquals(12, actions[1].todoId)
    assertEquals("2026-10-07T09:00:00.000Z", actions[1].occurrenceId)
    assertEquals("09:00", actions[1].displayTime)

    val upcoming = snapshot.upcomingItems()
    assertEquals(2, upcoming.size)
    assertEquals("Board Meeting", upcoming[0].summary)
    assertEquals("Write Report", upcoming[1].summary)

    assertEquals(setOf(7, 8), snapshot.monthDots())

    val ui = snapshot.ui()
    assertNotNull(ui)
    assertEquals("Overdue", ui!!.overdue)
    assertEquals("Missed", ui.missed)
    assertEquals("Inbox", ui.unplanned)
  }

  @Test
  fun `parses v3 snapshot todayStatus correctly`() {
    val snapshot = WidgetSnapshot.parse(snapshotV3Json())
    assertNotNull(snapshot)
    val status = snapshot!!.todayStatus()
    assertEquals(1, status.overdueCount)
    assertEquals(0, status.missedCount)
    assertEquals(3, status.unplannedCount)
  }

  @Test
  fun `parses v2 snapshot fields`() {
    val snapshot = WidgetSnapshot.parse(snapshotV2Json())
    assertNotNull(snapshot)
    assertEquals(1, snapshot!!.pendingTodos().size)
    assertEquals(7, snapshot.pendingTodos()[0].id)
    assertEquals(1, snapshot.todayEvents().size)
    assertEquals(setOf(3, 15), snapshot.monthDots())
    assertEquals(emptySet<Int>(), snapshot.pendingTapTodoIds())
    val theme = snapshot.theme()
    assertNotNull(theme)
    assertTrue(theme!!.dark)
    assertEquals(0xFFFFFFFF.toInt(), theme.colors["textPrimary"])

    // v3 accessors fall back cleanly for v2 snapshot
    val timeline = snapshot.todayTimeline()
    assertEquals(1, timeline.size)
    assertEquals("Standup", timeline[0].summary)

    val actions = snapshot.todayActions()
    assertEquals(1, actions.size)
    assertEquals("Write tests", actions[0].summary)
    assertEquals(7, actions[0].todoId)
  }

  @Test
  fun `rejects missing or pre-v2 snapshots`() {
    assertNull(WidgetSnapshot.parse(null))
    assertNull(WidgetSnapshot.parse(""))
    assertNull(WidgetSnapshot.parse("not json"))
    assertNull(WidgetSnapshot.parse("""{"version":1}"""))
  }

  @Test
  fun `append adds a pendingTap without touching other fields`() {
    val updated = WidgetSnapshot.appendPendingTap(
      snapshotV2Json(),
      todoId = 7,
      atIso = "2026-09-24T08:00:00Z",
    )
    assertNotNull(updated)
    val json = JSONObject(updated!!)
    assertEquals(2, json.getInt("version"))
    assertEquals("Standup", json.getJSONArray("todayEvents").getJSONObject(0).getString("summary"))
    assertEquals(1, json.getInt("todoCount"))
    val taps = json.getJSONArray("pendingTaps")
    assertEquals(1, taps.length())
    val tap = taps.getJSONObject(0)
    assertEquals(7, tap.getInt("todoId"))
    assertEquals("complete", tap.getString("action"))
    assertEquals("2026-09-24T08:00:00Z", tap.getString("at"))
  }

  @Test
  fun `re-tap on same todo is last-wins, distinct todos accumulate`() {
    var updated = WidgetSnapshot.appendPendingTap(
      snapshotV2Json(),
      todoId = 7,
      atIso = "2026-09-24T08:00:00Z",
    )!!
    updated = WidgetSnapshot.appendPendingTap(updated, 9, "2026-09-24T08:01:00Z")!!
    // Re-tap 7: the older 7 entry is replaced, 9 stays.
    updated = WidgetSnapshot.appendPendingTap(updated, 7, "2026-09-24T08:02:00Z")!!

    val taps = JSONObject(updated).getJSONArray("pendingTaps")
    assertEquals(2, taps.length())
    val first = taps.getJSONObject(0)
    val second = taps.getJSONObject(1)
    // Order: surviving 9 first (7's old slot dropped), fresh 7 appended.
    assertEquals(9, first.getInt("todoId"))
    assertEquals(7, second.getInt("todoId"))
    assertEquals("2026-09-24T08:02:00Z", second.getString("at"))
  }

  @Test
  fun `append refuses corrupt or missing blobs`() {
    assertNull(WidgetSnapshot.appendPendingTap(null, 1, "now"))
    assertNull(WidgetSnapshot.appendPendingTap("", 1, "now"))
    assertNull(WidgetSnapshot.appendPendingTap("not json", 1, "now"))
  }

  @Test
  fun `legacy snapshot without ids parses but yields null todo ids`() {
    val snapshot = WidgetSnapshot.parse(snapshotV2Json(todoId = null))
    assertNotNull(snapshot)
    assertNull(snapshot!!.pendingTodos()[0].id)
    assertTrue(snapshot.pendingTapTodoIds().isEmpty())
  }

  @Test
  fun `hex colors accept RRGGBB and AARRGGBB`() {
    assertEquals(0xFF1976D2.toInt(), WidgetSnapshot.parseHexColor("#1976D2"))
    assertEquals(0x801976D2.toInt(), WidgetSnapshot.parseHexColor("#801976D2"))
    assertNull(WidgetSnapshot.parseHexColor("#XYZ"))
    assertNull(WidgetSnapshot.parseHexColor("#12345"))
  }
}
