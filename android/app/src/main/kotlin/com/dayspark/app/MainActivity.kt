package com.dayspark.app

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
        else -> result.notImplemented()
      }
    }
  }
}
