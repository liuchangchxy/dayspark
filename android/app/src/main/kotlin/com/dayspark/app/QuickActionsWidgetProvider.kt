package com.dayspark.app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.os.Bundle
import android.widget.RemoteViews

class QuickActionsWidgetProvider : AppWidgetProvider() {
  override fun onUpdate(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetIds: IntArray,
  ) {
    for (id in appWidgetIds) update(context, appWidgetManager, id)
  }

  override fun onAppWidgetOptionsChanged(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetId: Int,
    newOptions: Bundle,
  ) {
    update(context, appWidgetManager, appWidgetId)
  }

  companion object {
    private fun update(
      context: Context,
      manager: AppWidgetManager,
      appWidgetId: Int,
    ) {
      WidgetSupport.render(context, manager, appWidgetId) {
        build(context, manager, appWidgetId)
      }
    }

    private fun build(
      context: Context,
      manager: AppWidgetManager,
      appWidgetId: Int,
    ): RemoteViews {
      val size = WidgetSupport.sizeOf(manager, appWidgetId)
      val layout = if (size == WidgetSize.SMALL) {
        R.layout.widget_quick_small
      } else {
        R.layout.widget_quick_medium
      }
      val views = RemoteViews(context.packageName, layout)
      views.setOnClickPendingIntent(
        R.id.quick_add_todo,
        WidgetSupport.openUri(context, WidgetSupport.quickAddUri, appWidgetId + 801),
      )
      views.setOnClickPendingIntent(
        R.id.quick_add_event,
        WidgetSupport.openUri(
          context,
          WidgetSupport.newEventUri(WidgetSupport.todayIso(context)),
          appWidgetId + 802,
        ),
      )
      if (size != WidgetSize.SMALL) {
        views.setOnClickPendingIntent(
          R.id.quick_today,
          WidgetSupport.openUri(
            context,
            android.net.Uri.parse("dayspark://open/today"),
            appWidgetId + 803,
          ),
        )
        views.setOnClickPendingIntent(
          R.id.quick_calendar,
          WidgetSupport.openUri(
            context,
            WidgetSupport.calendarUri(WidgetSupport.todayIso(context)),
            appWidgetId + 804,
          ),
        )
      }
      return views
    }
  }
}
