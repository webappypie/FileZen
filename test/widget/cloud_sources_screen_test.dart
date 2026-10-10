import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:filezen/app/theme/app_theme.dart';
import 'package:filezen/features/cloud/presentation/screens/cloud_sources_screen.dart';

void main() {
  testWidgets('CloudSourcesScreen is honest that cloud drives are unavailable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const CloudSourcesScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cloud Sources'), findsOneWidget);
    expect(find.text('Cloud Drives Are Not Available Yet'), findsOneWidget);
    expect(find.textContaining('Nothing is uploaded or synced'), findsOneWidget);

    // No way to add or browse fake accounts.
    expect(find.text('Add Account'), findsNothing);
    expect(find.text('Connect Account'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
