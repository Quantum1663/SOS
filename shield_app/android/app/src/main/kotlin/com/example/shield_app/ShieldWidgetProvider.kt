package com.example.shield_app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews

class ShieldWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        appWidgetIds.forEach { widgetId ->
            appWidgetManager.updateAppWidget(widgetId, buildRemoteViews(context))
        }
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        updateAllWidgets(context)
    }

    companion object {
        fun updateAllWidgets(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val widgetIds = manager.getAppWidgetIds(
                android.content.ComponentName(context, ShieldWidgetProvider::class.java)
            )
            widgetIds.forEach { widgetId ->
                manager.updateAppWidget(widgetId, buildRemoteViews(context))
            }
        }

        private fun buildRemoteViews(context: Context): RemoteViews {
            return RemoteViews(context.packageName, R.layout.shield_widget).apply {
                setOnClickPendingIntent(
                    R.id.widget_open,
                    ShortcutIntents.createActivityPendingIntent(context, ShortcutIntents.quickOpen)
                )
                setOnClickPendingIntent(
                    R.id.widget_full_panic,
                    ShortcutIntents.createActivityPendingIntent(context, ShortcutIntents.fullPanic)
                )
                setOnClickPendingIntent(
                    R.id.widget_silent_sos,
                    ShortcutIntents.createActivityPendingIntent(context, ShortcutIntents.silentSos)
                )
                setOnClickPendingIntent(
                    R.id.widget_check_in,
                    ShortcutIntents.createActivityPendingIntent(context, ShortcutIntents.checkIn)
                )
            }
        }
    }
}
