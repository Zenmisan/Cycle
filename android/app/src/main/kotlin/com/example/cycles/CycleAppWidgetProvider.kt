package com.example.cycles

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject

/**
 * AppWidgetProvider for Cycles Home-Screen Widget.
 * Displays open task count and the top active tasks with tap-to-open interaction.
 */
class CycleAppWidgetProvider : AppWidgetProvider() {

    companion object {
        const val PREFS_NAME = "cycles_widget_prefs"
        const val KEY_TASKS_JSON = "tasks_json"
        const val KEY_OPEN_COUNT = "open_count"

        /**
         * Triggers an immediate refresh of all active Cycles widgets on the home screen.
         */
        fun updateAllWidgets(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val thisWidget = ComponentName(context, CycleAppWidgetProvider::class.java)
            val allWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)
            for (widgetId in allWidgetIds) {
                updateWidget(context, appWidgetManager, widgetId)
            }
        }

        private fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.cycle_widget)
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val tasksJsonStr = prefs.getString(KEY_TASKS_JSON, "[]") ?: "[]"

            val taskTitles = mutableListOf<String>()
            try {
                val jsonArray = JSONArray(tasksJsonStr)
                for (i in 0 until jsonArray.length()) {
                    val obj = jsonArray.optJSONObject(i)
                    if (obj != null) {
                        val title = obj.optString("title", "")
                        if (title.isNotEmpty()) {
                            taskTitles.add(title)
                        }
                    }
                }
            } catch (_: Exception) {
                // Ignore parsing errors, fallback to empty
            }

            val count = taskTitles.size
            views.setTextViewText(R.id.widget_badge, "$count OPEN")

            // Toggle empty state vs task list
            if (taskTitles.isEmpty()) {
                views.setViewVisibility(R.id.widget_empty_state, View.VISIBLE)
                views.setViewVisibility(R.id.widget_task_container, View.GONE)
            } else {
                views.setViewVisibility(R.id.widget_empty_state, View.GONE)
                views.setViewVisibility(R.id.widget_task_container, View.VISIBLE)

                // Task row 1
                if (taskTitles.size >= 1) {
                    views.setViewVisibility(R.id.widget_task_row_1, View.VISIBLE)
                    views.setTextViewText(R.id.widget_task_text_1, taskTitles[0])
                } else {
                    views.setViewVisibility(R.id.widget_task_row_1, View.GONE)
                }

                // Task row 2
                if (taskTitles.size >= 2) {
                    views.setViewVisibility(R.id.widget_task_row_2, View.VISIBLE)
                    views.setTextViewText(R.id.widget_task_text_2, taskTitles[1])
                } else {
                    views.setViewVisibility(R.id.widget_task_row_2, View.GONE)
                }

                // Task row 3
                if (taskTitles.size >= 3) {
                    views.setViewVisibility(R.id.widget_task_row_3, View.VISIBLE)
                    views.setTextViewText(R.id.widget_task_text_3, taskTitles[2])
                } else {
                    views.setViewVisibility(R.id.widget_task_row_3, View.GONE)
                }
            }

            // Tap anywhere on the widget to open Cycles main activity
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }
}
