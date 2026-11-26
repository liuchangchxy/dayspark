package com.dayspark.app

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Looper
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

// The provider-level contract: which pending intent a real tap on a real
// inflated row fires. A layout test can prove the row is 48dp tall while every
// point outside the checkbox is still dead, so these tests dispatch touches and
// read the started activity / sent broadcast instead of inspecting the XML.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class WidgetRowIntentTest {
  private val application: Application get() = RuntimeEnvironment.getApplication()
  private val context: Context get() = application

  @Before
  fun resetPrefs() {
    WidgetSnapshot.prefs(context).edit().clear().commit()
  }

  private fun todoItem(
    id: Int,
    recurring: Boolean = false,
    tags: List<String> = emptyList(),
    dueDate: String? = "2026-11-16",
    completed: Boolean = false,
  ): WidgetSnapshot.TodoItemRow = WidgetSnapshot.TodoItemRow(
    todoId = id,
    todoSyncId = null,
    summary = "Task $id",
    priority = 0,
    dueDate = dueDate,
    dueEpochMs = null,
    hasTime = false,
    recurring = recurring,
    tagColors = tags,
    completed = completed,
  )

  private fun itemRow(
    item: WidgetSnapshot.TodoItemRow,
    size: WidgetSize = WidgetSize.LARGE,
  ): View = apply(
    TodoWidgetProvider.itemRow(
      context,
      item,
      null,
      size,
      "all",
      overdue = false,
      error = 0xFFFF0000.toInt(),
      warning = 0xFFFFAA00.toInt(),
      number = 0,
      appWidgetId = 1,
    ),
    widthDp = 360,
  )

  private fun apply(
    views: RemoteViews,
    widthDp: Int,
    heightDp: Int = 0,
    ctx: Context = context,
  ): View {
    val parent = FrameLayout(ctx)
    val root = views.apply(ctx, parent)
    parent.addView(root)
    // Clicks are posted to the handler, so the view must live in a window and
    // the main looper has to run before a tap has any effect.
    val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
    activity.setContentView(parent)
    val width = WidgetSupport.dpToPx(ctx, widthDp)
    if (heightDp > 0) {
      val height = WidgetSupport.dpToPx(ctx, heightDp)
      parent.measure(exactly(width), exactly(height))
      parent.layout(0, 0, width, height)
    } else {
      root.measure(exactly(width), View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
      root.layout(0, 0, root.measuredWidth, root.measuredHeight)
      parent.measure(exactly(width), exactly(root.measuredHeight))
      parent.layout(0, 0, parent.measuredWidth, parent.measuredHeight)
    }
    return root
  }

  private fun scaledContext(scale: Float): Context {
    val config = Configuration(application.resources.configuration).apply { fontScale = scale }
    return application.createConfigurationContext(config)
  }

  private fun exactly(value: Int): Int = View.MeasureSpec.makeMeasureSpec(value, View.MeasureSpec.EXACTLY)

  private fun boundsIn(root: View, view: View): IntArray {
    var x = 0
    var y = 0
    var current: View = view
    while (current !== root) {
      x += current.left
      y += current.top
      val parent = current.parent as? View ?: break
      current = parent
    }
    return intArrayOf(x, y, x + view.width, y + view.height)
  }

  private fun tap(root: View, x: Float, y: Float) {
    val now = SystemClock.uptimeMillis()
    val down = MotionEvent.obtain(now, now, MotionEvent.ACTION_DOWN, x, y, 0)
    val up = MotionEvent.obtain(now, now, MotionEvent.ACTION_UP, x, y, 0)
    root.dispatchTouchEvent(down)
    root.dispatchTouchEvent(up)
    shadowOf(Looper.getMainLooper()).idle()
    down.recycle()
    up.recycle()
  }

  private fun startedUri(): String? = shadowOf(application).nextStartedActivity?.dataString

  private fun completeIntents(): List<Intent> = shadowOf(application).broadcastIntents
    .filter { it.action == "com.dayspark.app.action.COMPLETE_ACTION" }

  @Test
  fun `every point of a row including the checkbox opens the same todo`() {
    val row = itemRow(todoItem(42))
    val xs = listOf(
      1f,
      row.width * 0.15f,
      row.width * 0.35f,
      row.width * 0.55f,
      row.width * 0.75f,
      row.width * 0.95f,
      row.width - 1f,
    )
    val ys = listOf(1f, row.height * 0.25f, row.height * 0.5f, row.height * 0.75f, row.height - 1f)
    var taps = 0
    for (x in xs) {
      for (y in ys) {
        val before = completeIntents().size
        tap(row, x, y)
        assertEquals(
          "tap at $x,$y must open todo 42",
          "dayspark://open/todo?id=42",
          startedUri(),
        )
        assertEquals("a row tap must not complete anything", before, completeIntents().size)
        taps++
      }
    }
    assertTrue("grid must exercise the row", taps >= 20)
  }

  @Test
  fun `checkbox centre and edges open the same todo and never queue a command`() {
    val row = itemRow(todoItem(42))
    val check = row.findViewById<View>(R.id.todo_check)
    assertTrue("checkbox must be visible", check.isShown)
    val box = boundsIn(row, check)
    val points = listOf(
      (box[0] + box[2]) / 2f to (box[1] + box[3]) / 2f,
      box[0] + 1f to (box[1] + box[3]) / 2f,
      box[2] - 1f to (box[1] + box[3]) / 2f,
      (box[0] + box[2]) / 2f to box[1] + 1f,
      (box[0] + box[2]) / 2f to box[3] - 1f,
    )
    for ((x, y) in points) {
      tap(row, x, y)
      assertEquals("checkbox tap at $x,$y must open the todo", "dayspark://open/todo?id=42", startedUri())
    }
    assertTrue("the widget is read-only: no complete command", completeIntents().isEmpty())
  }

  @Test
  fun `a recurring row has no checkbox and opens from every point`() {
    val row = itemRow(todoItem(7, recurring = true))
    assertFalse(row.findViewById<View>(R.id.todo_check).isShown)
    assertTrue(row.findViewById<View>(R.id.todo_repeat).isShown)
    val xs = listOf(1f, row.width * 0.2f, row.width * 0.5f, row.width * 0.8f, row.width - 1f)
    val ys = listOf(1f, row.height * 0.5f, row.height - 1f)
    for (x in xs) {
      for (y in ys) {
        tap(row, x, y)
        assertEquals("tap at $x,$y must open the recurring todo", "dayspark://open/todo?id=7", startedUri())
      }
    }
    assertTrue("a recurring row must never send a complete", completeIntents().isEmpty())
  }

  @Test
  fun `two rows carry the action of their own todo`() {
    val first = itemRow(todoItem(11))
    val second = itemRow(todoItem(12))
    tap(first, first.width * 0.6f, first.height / 2f)
    assertEquals("dayspark://open/todo?id=11", startedUri())
    tap(second, second.width * 0.6f, second.height / 2f)
    assertEquals("dayspark://open/todo?id=12", startedUri())
  }

  @Test
  fun `every visible informational child carries the row action`() {
    val row = itemRow(todoItem(9, tags = listOf("#ff0000", "#00ff00")))
    val ids = listOf(
      R.id.todo_item,
      R.id.todo_title,
      R.id.todo_meta,
      R.id.todo_tags,
      R.id.todo_tag_0,
      R.id.todo_tag_1,
    )
    for (id in ids) {
      val child = row.findViewById<View>(id)
      val name = context.resources.getResourceEntryName(id)
      assertTrue("$name must be visible", child.isShown)
      assertTrue("$name must carry the open action", child.hasOnClickListeners())
    }
    val check = row.findViewById<View>(R.id.todo_check)
    assertTrue(check.hasOnClickListeners())
    assertTrue("checkbox must have a click action", check.performClick())
    assertEquals("the checkbox opens the item", "dayspark://open/todo?id=9", startedUri())
    assertTrue("the checkbox never completes anything", completeIntents().isEmpty())
  }

  private fun actionTask(
    id: Int,
    completed: Boolean = false,
    target: String = "todo",
    occurrenceId: String? = null,
    kind: String = "todoDeadline",
  ): WidgetSnapshot.ActionTaskRow = WidgetSnapshot.ActionTaskRow(
    kind = kind,
    target = target,
    summary = "Task $id",
    todoId = id,
    todoSyncId = null,
    occurrenceId = occurrenceId,
    displayTime = null,
    priority = 0,
    dueEpochMs = null,
    dueDate = null,
    startEpochMs = null,
    completed = completed,
  )

  private fun allocation(
    todoId: Int,
    occurrenceId: String? = null,
    completed: Boolean = false,
  ): WidgetSnapshot.ActionTimelineRow =
    WidgetSnapshot.ActionTimelineRow(
      kind = "taskAllocation",
      summary = "Task $todoId",
      start = "09:00",
      end = "10:00",
      startEpochMs = System.currentTimeMillis() - 60_000,
      endEpochMs = System.currentTimeMillis() + 60_000,
      isAllDay = false,
      allocationId = "alloc-$todoId-${occurrenceId ?: "single"}",
      todoId = todoId,
      occurrenceId = occurrenceId,
      completed = completed,
    )

  private fun event(eventId: Int): WidgetSnapshot.ActionTimelineRow =
    WidgetSnapshot.ActionTimelineRow(
      kind = "eventOccurrence",
      summary = "Event $eventId",
      start = "11:00",
      end = "12:00",
      startEpochMs = System.currentTimeMillis() + 60_000,
      endEpochMs = System.currentTimeMillis() + 120_000,
      isAllDay = false,
      eventId = eventId,
      calendarId = 1,
      color = "#3b82f6",
    )

  @Test
  fun `a completed row keeps its checked box and opens the item`() {
    val row = itemRow(todoItem(42, completed = true))
    val check = row.findViewById<View>(R.id.todo_check)
    assertTrue("a completed row still shows its checkbox", check.isShown)
    val box = boundsIn(row, check)
    tap(row, (box[0] + box[2]) / 2f, (box[1] + box[3]) / 2f)
    assertEquals("dayspark://open/todo?id=42", startedUri())
    assertTrue("a completed row must not queue uncomplete", completeIntents().isEmpty())
  }

  @Test
  fun `a completed today task row opens the item too`() {
    val row = apply(
      TodayWidgetProvider.taskRow(
        context,
        actionTask(21, completed = true),
        null,
        0xFFFF0000.toInt(),
      ),
      360,
    )
    val box = boundsIn(row, row.findViewById(R.id.todo_check))
    tap(row, (box[0] + box[2]) / 2f, (box[1] + box[3]) / 2f)
    assertEquals("dayspark://open/todo?id=21", startedUri())
    assertTrue(completeIntents().isEmpty())
  }

  @Test
  fun `a completed recurring occurrence opens its own todo`() {
    val row = apply(
      TodayWidgetProvider.taskRow(
        context,
        actionTask(
          31,
          completed = true,
          target = "taskInstance",
          occurrenceId = "2026-10-07T08:00:00.000Z",
          kind = "taskInstance",
        ),
        null,
        0xFFFF0000.toInt(),
      ),
      360,
    )
    val check = row.findViewById<View>(R.id.todo_check)
    val box = boundsIn(row, check)
    tap(row, (box[0] + box[2]) / 2f, (box[1] + box[3]) / 2f)
    assertEquals("dayspark://open/todo?id=31", startedUri())
    assertTrue("no occurrence command may be queued", completeIntents().isEmpty())
  }

  @Test
  fun `today task row opens its todo from every point including the checkbox`() {
    val row = apply(
      TodayWidgetProvider.taskRow(
        context,
        actionTask(21),
        null,
        0xFFFF0000.toInt(),
      ),
      360,
    )
    tap(row, row.width * 0.6f, row.height / 2f)
    assertEquals("dayspark://open/todo?id=21", startedUri())
    val box = boundsIn(row, row.findViewById(R.id.todo_check))
    tap(row, (box[0] + box[2]) / 2f, (box[1] + box[3]) / 2f)
    assertEquals("dayspark://open/todo?id=21", startedUri())
    assertTrue(completeIntents().isEmpty())
  }

  @Test
  fun `timeline allocation row opens the todo from the title and the check`() {
    val row = apply(
      TodayWidgetProvider.timelineRow(
        context,
        allocation(22),
        null,
        "",
      ),
      360,
    )
    tap(row, row.width * 0.7f, row.height / 2f)
    assertEquals("dayspark://open/todo?id=22", startedUri())
    val box = boundsIn(row, row.findViewById(R.id.timeline_check))
    tap(row, (box[0] + box[2]) / 2f, (box[1] + box[3]) / 2f)
    assertEquals("dayspark://open/todo?id=22", startedUri())
    assertTrue(completeIntents().isEmpty())
  }

  @Test
  fun `a completed timeline allocation still opens its todo`() {
    val row = apply(
      TodayWidgetProvider.timelineRow(
        context,
        allocation(24, "2026-11-17T01:00:00.000Z", completed = true),
        null,
        "",
      ),
      360,
    )
    val check = row.findViewById<View>(R.id.timeline_check)
    assertTrue("a completed block keeps its checked box", check.isShown)
    val title = row.findViewById<android.widget.TextView>(R.id.timeline_title)
    assertTrue(
      "a completed block is struck through",
      title.paintFlags and android.graphics.Paint.STRIKE_THRU_TEXT_FLAG != 0,
    )
    val box = boundsIn(row, check)
    tap(row, (box[0] + box[2]) / 2f, (box[1] + box[3]) / 2f)
    assertEquals("dayspark://open/todo?id=24", startedUri())
    assertTrue("no uncomplete command may be queued", completeIntents().isEmpty())
  }

  @Test
  fun `recurring allocation checks open their own todo and queue nothing`() {
    fun openUriFor(occurrence: String): String? {
      val row = apply(
        TodayWidgetProvider.timelineRow(
          context,
          allocation(23, occurrence),
          null,
          "",
        ),
        360,
      )
      val box = boundsIn(row, row.findViewById(R.id.timeline_check))
      tap(row, (box[0] + box[2]) / 2f, (box[1] + box[3]) / 2f)
      return startedUri()
    }

    assertEquals("dayspark://open/todo?id=23", openUriFor("2026-11-16"))
    assertEquals("dayspark://open/todo?id=23", openUriFor("2026-11-17"))
    assertTrue("occurrence taps are links, not commands", completeIntents().isEmpty())
  }

  @Test
  fun `timeline event row opens the event from every visible region`() {
    val row = apply(
      TodayWidgetProvider.timelineRow(
        context,
        event(55),
        null,
        "",
      ),
      360,
    )
    assertFalse(row.findViewById<View>(R.id.timeline_check).isShown)
    // Bubbling would also pass this test, so the binding itself is asserted:
    // an event row must not depend on a non-clickable child letting the tap
    // through, which is the failure mode G1 removed.
    for (id in WidgetRows.TIMELINE_OPEN_IDS) {
      val child = row.findViewById<View>(id)
      val name = context.resources.getResourceEntryName(id)
      assertTrue("$name must carry the event action", child.hasOnClickListeners())
    }
    val points = listOf(1f, row.width * 0.2f, row.width * 0.5f, row.width * 0.8f, row.width - 1f)
    for (x in points) {
      tap(row, x, row.height / 2f)
      assertEquals("tap at $x must open event 55", "dayspark://open/event?id=55", startedUri())
    }
    assertTrue("an event row must never complete a todo", completeIntents().isEmpty())
  }

  private fun writeTodoSnapshot(
    items: Int,
    overdue: Int = 0,
    completed: Int = 0,
    summary: String = "Task",
    tags: Boolean = true,
    done: Int = 0,
  ) {
    val today = JSONArray()
    for (i in 1..items) {
      today.put(
        JSONObject()
          .put("todoId", i)
          .put("summary", "$summary $i")
          .put("priority", 0)
          .put("dueDate", "2026-11-16")
          .put("hasTime", false)
          .put("recurring", false)
          .put("tagColors", if (tags) JSONArray().put("#ff0000") else JSONArray()),
      )
    }
    val late = JSONArray()
    for (i in 1..overdue) {
      late.put(
        JSONObject()
          .put("todoId", 100 + i)
          .put("summary", "Late $i")
          .put("priority", 1)
          .put("dueDate", "2026-11-10")
          .put("hasTime", false)
          .put("recurring", false),
      )
    }
    val doneRows = JSONArray()
    for (i in 1..done) {
      doneRows.put(
        JSONObject()
          .put("todoId", 200 + i)
          .put("summary", "Done $i")
          .put("priority", 0)
          .put("dueDate", "2026-11-16")
          .put("hasTime", false)
          .put("recurring", false)
          .put("completed", true),
      )
    }
    val empty = JSONObject()
      .put("items", JSONArray())
      .put("overdue", JSONArray())
      .put("completedCount", 0)
      .put("total", 0)
    val todos = JSONObject()
      .put(
        "today",
        JSONObject()
          .put("items", today)
          .put("overdue", late)
          .put("completed", doneRows)
          .put("completedCount", completed)
          .put("total", items + overdue)
          .put("sixThingsCap", 6),
      )
      .put("inbox", empty)
      .put("all", empty)
    val snapshot = JSONObject()
      .put("version", 5)
      .put("today", WidgetStateStore.todayIso())
      .put("todos", todos)
    WidgetSnapshot.prefs(context).edit()
      .putString(WidgetSnapshot.SNAPSHOT_KEY, snapshot.toString())
      .commit()
  }

  private fun writeActionSnapshot(
    due: Int,
    completed: Int,
    completedRows: Int = 0,
    overdue: Int = 0,
  ) {
    fun rows(count: Int, prefix: String, offset: Int): JSONArray {
      val array = JSONArray()
      for (i in 1..count) {
        array.put(
          JSONObject()
            .put("kind", "todoDeadline")
            .put("target", "todo")
            .put("summary", "$prefix $i")
            .put("todoId", offset + i)
            .put("priority", 0),
        )
      }
      return array
    }
    val done = JSONArray()
    for (i in 1..completedRows) {
      done.put(
        JSONObject()
          .put("kind", "todoDeadline")
          .put("target", "todo")
          .put("summary", "Done $i")
          .put("todoId", 500 + i)
          .put("priority", 0)
          .put("completed", true),
      )
    }
    val action = JSONObject()
      .put("timeline", JSONArray())
      .put("dueToday", rows(due, "Task", 0))
      .put("overdue", rows(overdue, "Late", 100))
      .put("completed", done)
      .put(
        "counts",
        JSONObject()
          .put("dueToday", due)
          .put("overdue", overdue)
          .put("completedToday", completed),
      )
    val snapshot = JSONObject()
      .put("version", 5)
      .put("today", WidgetStateStore.todayIso())
      .put("action", action)
    WidgetSnapshot.prefs(context).edit()
      .putString(WidgetSnapshot.SNAPSHOT_KEY, snapshot.toString())
      .commit()
  }

  private fun assertRowsFit(root: View, rowsId: Int, ctx: Context = context): LinearLayout {
    val rows = root.findViewById<LinearLayout>(rowsId)
    assertNotNull(rows)
    val density = ctx.resources.displayMetrics.density
    var used = 0
    for (index in 0 until rows.childCount) {
      val child = rows.getChildAt(index)
      assertTrue("child $index must be measured", child.height > 0)
      used += child.height
    }
    assertTrue(
      "rows use ${used / density} dp of ${rows.height / density} dp",
      used <= rows.height,
    )
    if (rows.childCount > 0) {
      val last = rows.getChildAt(rows.childCount - 1)
      assertTrue(
        "last row bottom ${last.bottom} exceeds container ${rows.height}",
        last.bottom <= rows.height,
      )
    }
    return rows
  }

  @Test
  fun `large 4x2 shows only rows that fit instead of clipping the third`() {
    writeTodoSnapshot(items = 6)
    val root = apply(TodoWidgetProvider.build(context, 1, WidgetSize.LARGE, 224), 360, 224)
    val rows = assertRowsFit(root, R.id.todos_rows)
    assertEquals("two 48dp rows fit in 104dp", 2, rows.childCount)
    assertEquals(
      "a plain today list draws no group header",
      LinearLayout::class.java,
      rows.getChildAt(0).javaClass,
    )
  }

  @Test
  fun `large 4x4 fills the card without overflow`() {
    writeTodoSnapshot(items = 6)
    val root = apply(TodoWidgetProvider.build(context, 1, WidgetSize.LARGE, 344), 360, 344)
    val rows = assertRowsFit(root, R.id.todos_rows)
    assertEquals("four rows fit in 224dp", 4, rows.childCount)
  }

  @Test
  fun `small card at its declared minimum keeps one full row`() {
    writeTodoSnapshot(items = 6)
    val root = apply(TodoWidgetProvider.build(context, 1, WidgetSize.SMALL, 110), 180, 110)
    assertEquals(
      "the tight card must shrink its padding to keep a row",
      WidgetSupport.dpToPx(context, 4),
      root.paddingTop,
    )
    val rows = assertRowsFit(root, R.id.todos_rows)
    assertEquals(1, rows.childCount)
    assertTrue("a real row must be at least 48dp", rows.getChildAt(0).height >= 48)
  }

  @Test
  fun `completed today rows stay visible and their checkbox opens them`() {
    writeTodoSnapshot(items = 1, done = 1)
    val root = apply(TodoWidgetProvider.build(context, 1, WidgetSize.LARGE, 344), 360, 344)
    val rows = assertRowsFit(root, R.id.todos_rows)
    assertEquals("one open row and one completed row", 2, rows.childCount)
    val done = rows.getChildAt(1)
    val check = done.findViewById<View>(R.id.todo_check)
    assertTrue("a completed row keeps a checked box", check.isShown)
    val title = done.findViewById<android.widget.TextView>(R.id.todo_title)
    assertTrue(
      "a completed title is struck through",
      title.paintFlags and android.graphics.Paint.STRIKE_THRU_TEXT_FLAG != 0,
    )
    val box = boundsIn(done, check)
    tap(done, (box[0] + box[2]) / 2f, (box[1] + box[3]) / 2f)
    assertEquals("dayspark://open/todo?id=201", startedUri())
    assertTrue("read-only: no uncomplete command", completeIntents().isEmpty())
  }

  @Test
  fun `a card whose only tasks are completed shows the completed row, not a done label`() {
    writeTodoSnapshot(items = 0, done = 1, completed = 1)
    val root = apply(TodoWidgetProvider.build(context, 1, WidgetSize.LARGE, 344), 360, 344)
    val rows = assertRowsFit(root, R.id.todos_rows)
    assertEquals("the completed row is the only content", 1, rows.childCount)
    assertEquals(
      "a drawn undo row must not sit under an empty-state label",
      View.GONE,
      root.findViewById<View>(R.id.todos_empty).visibility,
    )
  }

  @Test
  fun `a card with tasks but no room never claims it is empty`() {
    writeTodoSnapshot(items = 6)
    val root = apply(TodoWidgetProvider.build(context, 1, WidgetSize.MEDIUM, 140), 240, 140)
    val rows = assertRowsFit(root, R.id.todos_rows)
    assertEquals(0, rows.childCount)
    assertEquals(View.GONE, root.findViewById<View>(R.id.todos_empty).visibility)
  }

  @Test
  fun `large today groups only draw a header with a row underneath it`() {
    writeTodoSnapshot(items = 3, overdue = 2)
    val short = apply(TodoWidgetProvider.build(context, 1, WidgetSize.LARGE, 224), 360, 224)
    val shortRows = assertRowsFit(short, R.id.todos_rows)
    assertEquals("overdue header plus one overdue row", 2, shortRows.childCount)

    val tall = apply(TodoWidgetProvider.build(context, 1, WidgetSize.LARGE, 344), 360, 344)
    val tallRows = assertRowsFit(tall, R.id.todos_rows)
    assertEquals(
      "two overdue rows and one today row, each group under its header",
      5,
      tallRows.childCount,
    )
  }

  @Test
  fun `today widget draws the completed row last and never instead of an open task`() {
    writeActionSnapshot(due = 1, completed = 1, completedRows = 1, overdue = 1)
    val root = apply(TodayWidgetProvider.build(context, 1, WidgetSize.LARGE, 344), 360, 344)
    val rows = assertRowsFit(root, R.id.action_rows)
    val titles = (0 until rows.childCount).mapNotNull { index ->
      rows.getChildAt(index).findViewById<android.widget.TextView>(R.id.todo_title)?.text?.toString()
    }
    assertEquals(
      "open due row, open overdue row, then the completed row",
      listOf("Task 1", "Late 1", "Done 1"),
      titles,
    )
    val done = rows.getChildAt(rows.childCount - 1)
    val box = boundsIn(done, done.findViewById(R.id.todo_check))
    tap(done, (box[0] + box[2]) / 2f, (box[1] + box[3]) / 2f)
    assertEquals("dayspark://open/todo?id=501", startedUri())
    assertTrue("read-only: no uncomplete command", completeIntents().isEmpty())
  }

  @Test
  fun `completed rows never displace an open overdue task on a short card`() {
    writeActionSnapshot(due = 1, completed = 2, completedRows = 2, overdue = 1)
    val root = apply(TodayWidgetProvider.build(context, 1, WidgetSize.LARGE, 224), 360, 224)
    val rows = assertRowsFit(root, R.id.action_rows)
    val titles = (0 until rows.childCount).mapNotNull { index ->
      rows.getChildAt(index).findViewById<android.widget.TextView>(R.id.todo_title)?.text?.toString()
    }
    assertTrue("the open due row is drawn", titles.contains("Task 1"))
    assertTrue(
      "an open overdue task must outrank the undo rows: $titles",
      titles.contains("Late 1"),
    )
    assertFalse("the undo row is what gets dropped", titles.contains("Done 1"))
  }

  @Test
  fun `today widget drops the footer rather than hiding a task row`() {
    writeActionSnapshot(due = 2, completed = 3)
    val root = apply(TodayWidgetProvider.build(context, 1, WidgetSize.LARGE, 224), 360, 224)
    val rows = assertRowsFit(root, R.id.action_rows)
    assertEquals("header plus both task rows", 3, rows.childCount)
    assertEquals(View.GONE, root.findViewById<View>(R.id.action_completed).visibility)
  }

  @Test
  fun `today widget keeps the footer when every row still fits beside it`() {
    writeActionSnapshot(due = 2, completed = 3)
    val root = apply(TodayWidgetProvider.build(context, 1, WidgetSize.LARGE, 344), 360, 344)
    val rows = assertRowsFit(root, R.id.action_rows)
    assertEquals(3, rows.childCount)
    val footer = root.findViewById<View>(R.id.action_completed)
    assertEquals(View.VISIBLE, footer.visibility)
    assertTrue("footer must be fully inside the card", footer.bottom <= root.height)
  }

  @Test
  fun `the footer is a fallback only and is never drawn beside a completed row`() {
    // Tall enough for the open row, the completed row and the footer: the row
    // wins and the footer stays hidden, so the same completion is not stated
    // twice.
    writeActionSnapshot(due = 1, completed = 1, completedRows = 1)
    val tall = apply(TodayWidgetProvider.build(context, 1, WidgetSize.LARGE, 344), 360, 344)
    val tallRows = assertRowsFit(tall, R.id.action_rows)
    val tallTitles = (0 until tallRows.childCount).mapNotNull { index ->
      tallRows.getChildAt(index).findViewById<android.widget.TextView>(R.id.todo_title)?.text?.toString()
    }
    assertTrue("the undo row is drawn", tallTitles.contains("Done 1"))
    assertEquals(
      "no footer beside a drawn undo row",
      View.GONE,
      tall.findViewById<View>(R.id.action_completed).visibility,
    )

    // A completion with no row to draw (the count is known but the row was
    // filtered out of this card): the footer is the only thing left, and when
    // it is drawn it must be fully inside the card.
    writeActionSnapshot(due = 1, completed = 1, completedRows = 0)
    val counted = apply(TodayWidgetProvider.build(context, 1, WidgetSize.LARGE, 344), 360, 344)
    assertRowsFit(counted, R.id.action_rows)
    val footer = counted.findViewById<View>(R.id.action_completed)
    assertEquals("the footer is the fallback", View.VISIBLE, footer.visibility)
    assertTrue(
      "a drawn footer must be fully inside the card: bottom ${footer.bottom} > ${counted.height}",
      footer.bottom <= counted.height,
    )
  }

  @Test
  fun `today widget small card shows a row and no footer`() {
    writeActionSnapshot(due = 3, completed = 1)
    val root = apply(TodayWidgetProvider.build(context, 1, WidgetSize.SMALL, 120), 180, 120)
    val rows = assertRowsFit(root, R.id.action_rows)
    assertEquals(1, rows.childCount)
    assertEquals(View.GONE, root.findViewById<View>(R.id.action_completed).visibility)
  }

  @Test
  fun `row budget spends in dp and never overdraws`() {
    val budget = RowBudget(104)
    assertTrue(budget.take(WidgetSupport.SECTION_DP))
    assertTrue(budget.take(48))
    assertFalse("a second full row does not fit after the header", budget.take(48))
    assertTrue(budget.remainingDp in 0 until 48)
  }

  // The budget used to be an arithmetic model of text growth, so at 1.5/2.0 the
  // last row was charged 48dp while the real row needed 51/64 and lost its
  // bottom. Asserting the model against itself cannot see that; these build the
  // real widget at the real scale and measure what the container produced.
  @Test
  fun `rows keep their full height at accessibility font scales`() {
    for (scale in listOf(1.3f, 1.5f, 2f)) {
      for (heightDp in listOf(224, 264, 344, 348)) {
        writeTodoSnapshot(items = 6)
        val ctx = scaledContext(scale)
        val root = apply(
          TodoWidgetProvider.build(ctx, 1, WidgetSize.LARGE, heightDp),
          widthDp = 360,
          heightDp = heightDp,
          ctx = ctx,
        )
        val rows = assertRowsFit(root, R.id.todos_rows, ctx)
        assertTrue("scale=$scale height=${heightDp}dp: no row was laid out", rows.childCount > 0)
        val floor = WidgetSupport.dpToPx(ctx, 48)
        for (index in 0 until rows.childCount) {
          val child = rows.getChildAt(index)
          if (child.findViewById<View>(R.id.todo_item) != null &&
            child.findViewById<View>(R.id.action_section) == null
          ) {
            assertTrue(
              "scale=$scale height=${heightDp}dp: row $index is ${child.height}px " +
                "but a touch target needs ${floor}px",
              child.height >= floor,
            )
          }
        }
      }
    }
  }

  // A fixed measurement sample can only be right for the scripts it contains:
  // Latin is 51dp at 1.5, zh 54, Arabic 58, Tibetan 67. Budgeting every row
  // from one sample squeezed the taller scripts under 48dp on a device. The
  // height is measured from the row's own text now, so this asserts each script
  // keeps its own full height at 420dpi, and that a row was actually laid out.
  @Test
  @Config(qualifiers = "420dpi")
  fun `every script keeps its full row height at accessibility font scales`() {
    val scripts = listOf(
      "latin" to "Buy milk",
      "zh" to "买牛奶",
      "ar" to "شراء الحليب",
      "hi" to "दूध खरीदें",
      "bo" to "ཞོ་འཐུང་",
      "th" to "ซื้อนม",
      "ko" to "우유 사기",
    )
    for ((script, summary) in scripts) {
      for (scale in listOf(1.5f, 2f)) {
        for (heightDp in listOf(220, 234, 261, 322, 344)) {
          writeTodoSnapshot(items = 6, summary = summary, tags = false)
          val ctx = scaledContext(scale)
          val root = apply(
            TodoWidgetProvider.build(ctx, 1, WidgetSize.LARGE, heightDp),
            widthDp = 360,
            heightDp = heightDp,
            ctx = ctx,
          )
          val rows = assertRowsFit(root, R.id.todos_rows, ctx)
          assertTrue(
            "$script scale=$scale height=${heightDp}dp: no row was laid out",
            rows.childCount > 0,
          )
          val floor = WidgetSupport.dpToPx(ctx, 48)
          for (index in 0 until rows.childCount) {
            val child = rows.getChildAt(index)
            if (child.findViewById<View>(R.id.action_section) != null) continue
            assertTrue(
              "$script scale=$scale height=${heightDp}dp: row $index is ${child.height}px " +
                "but a touch target needs ${floor}px",
              child.height >= floor,
            )
          }
        }
      }
    }
  }

  @Test
  fun `the 112dp boundary still shows one full row`() {
    writeTodoSnapshot(items = 6)
    for (heightDp in listOf(110, 111, 112, 113, 114)) {
      val root = apply(TodoWidgetProvider.build(context, 1, WidgetSize.SMALL, heightDp), 180, heightDp)
      val rows = assertRowsFit(root, R.id.todos_rows)
      assertTrue(
        "a ${heightDp}dp card must keep the same one row as its neighbours, got ${rows.childCount}",
        rows.childCount >= 1,
      )
    }
  }

  @Test
  fun `a todo row without an id still opens the list and hides its checkbox`() {
    val row = itemRow(todoItem(0))
    assertFalse("no id means no checkbox to press", row.findViewById<View>(R.id.todo_check).isShown)
    tap(row, row.width * 0.6f, row.height / 2f)
    assertEquals("dayspark://open/todos?view=all", startedUri())
    assertTrue("an id-less row must not complete anything", completeIntents().isEmpty())
  }

  @Test
  fun `a today task row without an id binds the action list instead of dying`() {
    val row = apply(
      TodayWidgetProvider.taskRow(
        context,
        actionTask(0),
        null,
        0xFFFF0000.toInt(),
      ),
      360,
    )
    assertFalse("no id means no checkbox to press", row.findViewById<View>(R.id.todo_check).isShown)
    tap(row, row.width * 0.6f, row.height / 2f)
    assertEquals("dayspark://open/action", startedUri())
    assertTrue(completeIntents().isEmpty())
  }

  @Test
  fun `a calendar summary row without an id opens the selected day`() {
    val row = apply(
      CalendarWidgetProvider.summaryRowForTest(
        context,
        WidgetSnapshot.MonthItemRow(
          kind = "other",
          summary = "No link",
          start = "10:00",
          end = "11:00",
          startEpochMs = null,
          endEpochMs = null,
          isAllDay = false,
          hasTime = true,
          color = "#3b82f6",
          eventId = null,
          todoId = null,
          todoSyncId = null,
          allocationId = null,
          occurrenceId = null,
        ),
        appWidgetId = 1,
        selectedIso = "2026-11-16",
      ),
      360,
    )
    tap(row, row.width * 0.6f, row.height / 2f)
    assertEquals("dayspark://open/calendar?date=2026-11-16", startedUri())
  }

  @Test
  fun `the budgeted row height is never less than the laid out row`() {
    for (scale in listOf(1f, 1.3f, 1.5f, 2f)) {
      val ctx = scaledContext(scale)
      val budgeted = WidgetSupport.todoRowHeightDp(
        ctx,
        hasMeta = true,
        hasTags = true,
        title = "Task 1",
        meta = "Nov 16",
      )
      writeTodoSnapshot(items = 2)
      val root = TodoWidgetProvider.build(ctx, 1, WidgetSize.LARGE, 344)
        .apply(ctx, FrameLayout(ctx))
      val parent = FrameLayout(ctx)
      parent.addView(root)
      parent.measure(exactly(WidgetSupport.dpToPx(ctx, 360)), exactly(WidgetSupport.dpToPx(ctx, 344)))
      parent.layout(0, 0, parent.measuredWidth, parent.measuredHeight)
      val rows = root.findViewById<View>(R.id.todos_rows)
      val first = (rows as android.view.ViewGroup).getChildAt(0)
      val laidOutDp = Math.ceil(first.height / ctx.resources.displayMetrics.density.toDouble()).toInt()
      assertTrue(
        "scale=$scale: budgeted ${budgeted}dp must cover the real ${laidOutDp}dp row",
        budgeted >= laidOutDp,
      )
    }
  }

  private fun legacyCompleteIntent(
    todoId: Int,
    command: String = "complete",
  ): Intent = Intent(context, WidgetActionReceiver::class.java).apply {
    action = "com.dayspark.app.action.COMPLETE_ACTION"
    putExtra("target", "todo")
    putExtra("action", command)
    putExtra("todoId", todoId)
  }

  private fun writeLegacyCommand(todoId: Int) {
    val command = JSONObject()
      .put("version", 1)
      .put("commandId", "legacy-$todoId")
      .put("action", "complete")
      .put("target", "todo")
      .put("todoId", todoId)
      .put("at", "2026-11-25T00:00:00.000Z")
    WidgetSnapshot.prefs(context).edit()
      .putString("${WidgetSnapshot.COMMAND_PREFIX}legacy-$todoId", command.toString())
      .commit()
  }

  private fun pendingCount(): Int = WidgetSnapshot.readPendingCommands(context).size

  // Legacy broadcasts (from a widget instance placed by an older build) must
  // not resurrect the removed write path. They land in a safe no-op.
  @Test
  fun `a legacy complete broadcast no longer writes a command`() {
    WidgetActionReceiver().onReceive(context, legacyCompleteIntent(42))
    assertEquals(0, pendingCount())
    assertNull(startedUri())
  }

  @Test
  fun `a legacy uncomplete broadcast no longer writes a command`() {
    WidgetActionReceiver().onReceive(context, legacyCompleteIntent(42, command = "uncomplete"))
    assertEquals(0, pendingCount())
  }

  @Test
  fun `a legacy broadcast does not cancel a queued command either`() {
    writeLegacyCommand(42)
    assertEquals(1, pendingCount())
    WidgetActionReceiver().onReceive(context, legacyCompleteIntent(42))
    assertEquals("the read-only widget must not touch the command queue", 1, pendingCount())
  }

  @Test
  fun `legacy mode and calendar-date broadcasts do not change widget state`() {
    val legacyState = """{"todoMode":"all","selectedDate":"2026-11-25","calendarMode":"day"}"""
    WidgetSnapshot.prefs(context).edit()
      .putString("widget_state_1", legacyState)
      .commit()
    val receiver = WidgetActionReceiver()
    receiver.onReceive(
      context,
      Intent(context, WidgetActionReceiver::class.java).apply {
        action = "com.dayspark.app.action.SET_TODO_MODE"
        putExtra("appWidgetId", 1)
        putExtra("todoMode", "all")
      },
    )
    receiver.onReceive(
      context,
      Intent(context, WidgetActionReceiver::class.java).apply {
        action = "com.dayspark.app.action.SET_CALENDAR_DATE"
        putExtra("appWidgetId", 1)
        putExtra("calendarDate", "2026-11-25")
        putExtra("enterDay", true)
      },
    )
    assertEquals(
      "legacy state broadcasts must not be handled by the read-only receiver",
      legacyState,
      WidgetSnapshot.prefs(context).getString("widget_state_1", null),
    )
  }
}
