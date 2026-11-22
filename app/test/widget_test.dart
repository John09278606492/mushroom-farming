import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mushroom_farm/main.dart';

void main() {
  testWidgets('without Firebase: login offers demo, demo shows the dashboard',
      (tester) async {
    // A tall phone-shaped screen so the whole dashboard is built.
    tester.view.physicalSize = const Size(420, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MushroomApp(firebaseReady: false));
    expect(find.text('Mushroom Farm'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);

    await tester.tap(find.text('Try demo mode'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Humidity'), findsOneWidget);
    expect(find.text('Mode'), findsOneWidget);
    expect(find.text('Demo'), findsWidgets);

    // Navigate through every tab.
    for (final tab in ['History', 'Analytics', 'Harvest', 'Settings', 'Home']) {
      await tester.tap(find.bySemanticsLabel(tab).last);
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('Devices'), findsOneWidget);

    // The bell opens the notification list.
    await tester.tap(find.bySemanticsLabel(RegExp('Notifications')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Happening now'), findsOneWidget);
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Switch to manual through the confirmation dialog.
    await tester.tap(find.text('Manual'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Switch to Manual?'), findsOneWidget);
    await tester.tap(find.text('Switch'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Sending to the controller…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('You control every device yourself'), findsOneWidget);

    // Pushed screens must still reach FarmState.
    await tester.tap(find.bySemanticsLabel('Settings').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Targets & thresholds'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.text('Humidity (mist maker)'), findsOneWidget);
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Schedules'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.text('Grow light'), findsWidgets);
    await tester.tap(find.textContaining('6:00').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Delete schedule'), findsOneWidget);

    // Dispose the farm so its timers stop.
    await tester.pumpWidget(const SizedBox());
  });
}
