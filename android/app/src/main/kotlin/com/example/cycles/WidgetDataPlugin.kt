package com.example.cycles

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Platform channel plugin enabling Flutter to push updated task data to the Android home widget.
 */
class WidgetDataPlugin(
    private val context: Context,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "cycles/widget")

    init {
        channel.setMethodCallHandler(this)
    }

    fun detach() {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "updateTasks" -> {
                val tasksJson = call.argument<String>("tasksJson") ?: "[]"
                val prefs = context.getSharedPreferences(
                    CycleAppWidgetProvider.PREFS_NAME,
                    Context.MODE_PRIVATE
                )
                prefs.edit()
                    .putString(CycleAppWidgetProvider.KEY_TASKS_JSON, tasksJson)
                    .apply()

                CycleAppWidgetProvider.updateAllWidgets(context)
                result.success(true)
            }
            "refreshWidget" -> {
                CycleAppWidgetProvider.updateAllWidgets(context)
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }
}
