import 'package:flutter_test/flutter_test.dart';
import 'package:cycles/services/recurrence_service.dart';

void main() {
  group('RecurrenceService', () {
    test('extractRule extracts correct rule from tags', () {
      expect(RecurrenceService.extractRule(''), 'None');
      expect(RecurrenceService.extractRule('work, urgent'), 'None');
      expect(RecurrenceService.extractRule('work, repeat:daily'), 'Daily');
      expect(RecurrenceService.extractRule('repeat:weekly, personal'), 'Weekly');
      expect(RecurrenceService.extractRule('repeat:weekdays'), 'Weekdays');
      expect(RecurrenceService.extractRule('repeat:monthly'), 'Monthly');
      expect(RecurrenceService.extractRule('repeat:yearly'), 'Yearly');
      expect(RecurrenceService.extractRule('repeat:unknown'), 'None');
    });

    test('formatTagsWithRule formats and updates tags correctly', () {
      expect(RecurrenceService.formatTagsWithRule('work', 'Daily'), 'work, repeat:daily');
      expect(RecurrenceService.formatTagsWithRule('work, repeat:daily', 'Weekly'), 'work, repeat:weekly');
      expect(RecurrenceService.formatTagsWithRule('work, repeat:daily', 'None'), 'work');
      expect(RecurrenceService.formatTagsWithRule('', 'Monthly'), 'repeat:monthly');
      expect(RecurrenceService.formatTagsWithRule('', 'None'), '');
    });

    test('calculateNextDueDate advances daily correctly', () {
      final base = DateTime(2026, 9, 19, 10, 0);
      final next = RecurrenceService.calculateNextDueDate(base, 'Daily');
      expect(next, DateTime(2026, 9, 20, 10, 0));
    });

    test('calculateNextDueDate advances weekdays correctly', () {
      // Friday Sep 19 2026 -> Monday Sep 22 2026 (+3 days)
      final friday = DateTime(2026, 9, 18, 9, 0); // Sep 18, 2026 was Friday
      expect(friday.weekday, DateTime.friday);
      final monday = RecurrenceService.calculateNextDueDate(friday, 'Weekdays');
      expect(monday.weekday, DateTime.monday);
      expect(monday, DateTime(2026, 9, 21, 9, 0));

      // Thursday -> Friday (+1 day)
      final thursday = DateTime(2026, 9, 17, 9, 0);
      final nextDay = RecurrenceService.calculateNextDueDate(thursday, 'Weekdays');
      expect(nextDay.weekday, DateTime.friday);
      expect(nextDay, DateTime(2026, 9, 18, 9, 0));
    });

    test('calculateNextDueDate advances weekly correctly', () {
      final base = DateTime(2026, 9, 19, 14, 30);
      final next = RecurrenceService.calculateNextDueDate(base, 'Weekly');
      expect(next, DateTime(2026, 9, 26, 14, 30));
    });

    test('calculateNextDueDate advances monthly correctly', () {
      final base = DateTime(2026, 1, 15, 8, 0);
      final next = RecurrenceService.calculateNextDueDate(base, 'Monthly');
      expect(next, DateTime(2026, 2, 15, 8, 0));
    });

    test('calculateNextDueDate clamps monthly leap days gracefully', () {
      final jan31 = DateTime(2026, 1, 31, 8, 0);
      final feb = RecurrenceService.calculateNextDueDate(jan31, 'Monthly');
      // 2026 is not a leap year, February has 28 days
      expect(feb.month, 2);
      expect(feb.day, 28);
    });

    test('calculateNextDueDate advances yearly correctly', () {
      final base = DateTime(2026, 9, 19, 10, 0);
      final next = RecurrenceService.calculateNextDueDate(base, 'Yearly');
      expect(next, DateTime(2027, 9, 19, 10, 0));
    });
  });
}
