package com.dayspark.app

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// JVM-level codec tests: the pendingTaps append rule is the load-bearing
// native contract (append-only, last-wins per todoId, never touch other
// fields) — cheap to pin down without an emulator.
class WidgetSnapshotCodecTest {

  private fun snapshotJson(
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

  @Test
  fun `parses v2 snapshot fields`() {
    val snapshot = WidgetSnapshot.parse(snapshotJson())
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
      snapshotJson(),
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
      snapshotJson(),
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
    val snapshot = WidgetSnapshot.parse(snapshotJson(todoId = null))
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
