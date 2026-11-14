package com.dayspark.app

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private val CHANNEL = "com.dayspark.app/widget_commands"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "getPendingCommands" -> {
          val commands = WidgetSnapshot.readPendingCommands(this)
          result.success(commands)
        }
        "ackCommand" -> {
          val commandId = call.argument<String>("commandId")
          if (commandId != null) {
            WidgetSnapshot.ackCommand(this, commandId)
            result.success(null)
          } else {
            result.error("INVALID_ARGUMENT", "commandId required", null)
          }
        }
        "hasWidgets" -> result.success(hasWidgetInstances())
        else -> result.notImplemented()
      }
    }
  }

  // Rebuilding the snapshot for zero hosts is pure waste on the path that runs
  // after every write, so the Dart side asks first.
  private fun hasWidgetInstances(): Boolean {
    val manager = AppWidgetManager.getInstance(this)
    val providers = listOf(
      TodoWidgetProvider::class.java,
      TodayWidgetProvider::class.java,
      CalendarWidgetProvider::class.java,
    )
    return providers.any { manager.getAppWidgetIds(ComponentName(this, it)).isNotEmpty() }
  }
}
