import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../data/database.dart';

/// Service that keeps native home-screen widgets (Android AppWidget / iOS WidgetKit)
/// synchronized with the current state of open tasks in Drift.
class WidgetSyncService {
  WidgetSyncService._();
  static final WidgetSyncService instance = WidgetSyncService._();

  static const MethodChannel _channel = MethodChannel('cycles/widget');

  /// Pushes an updated snapshot of open tasks to the platform widget provider.
  Future<void> updateWidgetTasks(List<Task> allTasks) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return; // Desktop/web targets do not support mobile widgets
    }

    try {
      // Filter for active/open tasks (not completed)
      final openTasks = allTasks.where((t) => t.status != 'completed').toList();

      // Sort by priority (descending: higher priority first), then by creation
      openTasks.sort((a, b) {
        final prioCompare = b.priority.compareTo(a.priority);
        if (prioCompare != 0) return prioCompare;
        return b.createdAt.compareTo(a.createdAt);
      });

      // Take top 5 for widget display
      final widgetTasks = openTasks.take(5).map((t) => {
        'id': t.id,
        'title': t.title,
        'status': t.status,
        'priority': t.priority,
        'dueMillis': t.due?.millisecondsSinceEpoch,
      }).toList();

      final jsonString = jsonEncode(widgetTasks);

      await _channel.invokeMethod('updateTasks', {
        'tasksJson': jsonString,
        'openCount': openTasks.length,
      });
    } catch (e) {
      debugPrint('[WidgetSyncService] Failed to update home widget: $e');
    }
  }

  /// Explicitly requests the native widget layer to refresh its views.
  Future<void> refreshWidget() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    try {
      await _channel.invokeMethod('refreshWidget');
    } catch (e) {
      debugPrint('[WidgetSyncService] Failed to refresh widget: $e');
    }
  }
}
