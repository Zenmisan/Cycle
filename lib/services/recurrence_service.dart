import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../data/database.dart';
import '../data/sync_bridge.dart';
import 'notification_service.dart';

/// Service managing recurring task rules, next-occurrence calculations,
/// and automated spawning of recurring task instances upon completion.
class RecurrenceService {
  static const List<String> kRules = [
    'None',
    'Daily',
    'Weekdays',
    'Weekly',
    'Monthly',
    'Yearly',
  ];

  /// Extracts the recurrence rule (e.g. 'Daily', 'Weekly') from comma-separated tags,
  /// or returns 'None' if no recurrence tag is present.
  static String extractRule(String tags) {
    if (tags.trim().isEmpty) return 'None';
    final parts = tags.split(',').map((e) => e.trim());
    for (final part in parts) {
      if (part.toLowerCase().startsWith('repeat:')) {
        final ruleName = part.substring('repeat:'.length).trim();
        for (final r in kRules) {
          if (r.toLowerCase() == ruleName.toLowerCase()) {
            return r;
          }
        }
      }
    }
    return 'None';
  }

  /// Updates or removes the `repeat:<rule>` tag from a comma-separated tag string.
  static String formatTagsWithRule(String tags, String rule) {
    final cleanParts = tags
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !e.toLowerCase().startsWith('repeat:'))
        .toList();

    if (rule.isNotEmpty && rule.toLowerCase() != 'none') {
      cleanParts.add('repeat:${rule.toLowerCase()}');
    }
    return cleanParts.join(', ');
  }

  /// Calculates the next occurrence timestamp given a base date and recurrence rule.
  static DateTime calculateNextDueDate(DateTime base, String rule) {
    final r = rule.toLowerCase();
    switch (r) {
      case 'daily':
        return base.add(const Duration(days: 1));

      case 'weekdays':
        // If Friday (weekday 5), jump to Monday (+3 days).
        // If Saturday (weekday 6), jump to Monday (+2 days).
        if (base.weekday == DateTime.friday) {
          return base.add(const Duration(days: 3));
        } else if (base.weekday == DateTime.saturday) {
          return base.add(const Duration(days: 2));
        } else {
          return base.add(const Duration(days: 1));
        }

      case 'weekly':
        return base.add(const Duration(days: 7));

      case 'monthly':
        final nextMonth = base.month == 12 ? 1 : base.month + 1;
        final nextYear = base.month == 12 ? base.year + 1 : base.year;
        // Clamp to last day of month if necessary (e.g. Jan 31 -> Feb 28)
        final daysInNextMonth = DateTime(nextYear, nextMonth + 1, 0).day;
        final day = base.day > daysInNextMonth ? daysInNextMonth : base.day;
        return DateTime(nextYear, nextMonth, day, base.hour, base.minute);

      case 'yearly':
        return DateTime(base.year + 1, base.month, base.day, base.hour, base.minute);

      default:
        return base.add(const Duration(days: 1));
    }
  }

  /// When a recurring task is completed, this method automatically spawns
  /// the next task occurrence with updated due date, syncs it to CRDT,
  /// and schedules its local notification.
  static Future<Task?> spawnNextOccurrence({
    required Task completedTask,
    required AppDatabase db,
  }) async {
    final rule = extractRule(completedTask.tags);
    if (rule == 'None') return null;

    final now = DateTime.now();
    final baseDate = completedTask.due ?? now;
    final nextDue = calculateNextDueDate(baseDate, rule);
    final nextId = const Uuid().v4();

    final companion = TasksCompanion(
      id: Value(nextId),
      projectId: Value(completedTask.projectId),
      title: Value(completedTask.title),
      notes: Value(completedTask.notes),
      due: Value(nextDue),
      tags: Value(completedTask.tags),
      status: const Value('open'),
      priority: Value(completedTask.priority),
      createdAt: Value(now),
      updatedAt: Value(now),
    );

    await db.upsertTask(companion);
    final createdTask = await (db.select(db.tasks)..where((t) => t.id.equals(nextId))).getSingle();
    await applyLocalTaskEdit(createdTask);
    await NotificationService.scheduleForTask(createdTask);

    return createdTask;
  }
}
