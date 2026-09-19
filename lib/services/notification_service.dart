import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../data/database.dart';

/// Due-date reminders — local notifications only, no server involved.
/// Scheduled/cancelled whenever a task's due date is set/changed/cleared,
/// or the task is completed/deleted (see call sites in the task detail
/// screen and `main.dart`'s task list).
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized || kIsWeb) return;
    tz_data.initializeTimeZones();

    const androidInit = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosInit = DarwinInitializationSettings();
    const linuxInit = LinuxInitializationSettings(
      defaultActionName: 'Open',
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
      linux: linuxInit,
    );
    await _plugin.initialize(settings: initSettings);

    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImpl?.requestNotificationsPermission();

    final iosImpl = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await iosImpl?.requestPermissions(alert: true, badge: true, sound: true);

    _initialized = true;
  }

  /// A stable-ish int id derived from the task's uuid, since the plugin
  /// needs an int id per notification (and we need to find it again to
  /// cancel/reschedule).
  static int _idFor(String taskId) => taskId.hashCode & 0x7fffffff;

  static Future<void> scheduleForTask(Task task) async {
    if (kIsWeb) return;
    await init();
    final id = _idFor(task.id);
    await _plugin.cancel(id: id);

    if (task.due == null || task.status == 'done') return;
    if (task.due!.isBefore(DateTime.now())) return;

    try {
      await _plugin.zonedSchedule(
        id: id,
        title: task.title,
        body: task.notes.isEmpty ? 'Due now' : task.notes,
        scheduledDate: tz.TZDateTime.from(task.due!, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'cycles_due_dates',
            'Due date reminders',
            channelDescription: 'Reminders for tasks with a due date',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
          linux: LinuxNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (e) {
      // Scheduling can fail (e.g. exact-alarm permission denied on some
      // Android versions) — don't crash the save flow over a reminder.
      debugPrint('NotificationService: failed to schedule for ${task.id}: $e');
    }
  }

  static Future<void> cancelForTask(String taskId) async {
    if (kIsWeb) return;
    await _plugin.cancel(id: _idFor(taskId));
  }
}
