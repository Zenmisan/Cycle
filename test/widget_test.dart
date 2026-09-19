import 'package:flutter_test/flutter_test.dart';

import 'package:cycles/data/database.dart';
import 'package:drift/native.dart';
import 'package:cycles/main.dart';

void main() {
  testWidgets('shows empty state with no projects', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(CyclesApp(db: db));
    await tester.pump();
    expect(find.text('No projects yet. Tap + to add one.'), findsOneWidget);
    await db.close();
  });
}
