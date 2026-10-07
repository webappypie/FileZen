import 'package:filezen/app/bootstrap/app_bootstrap.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('NavigationShell renders 5 tabs and allows tab navigation', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: FileZenApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify App Bar Title starts at FileZen
    expect(find.text('FileZen'), findsOneWidget);

    // Verify all 5 navigation destinations exist
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
    expect(find.text('Clean'), findsOneWidget);
    expect(find.text('Vault'), findsOneWidget);

    // Verify top action bar buttons
    expect(find.byTooltip('Universal Search'), findsOneWidget);
    expect(find.byTooltip('Notifications Center'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);

    // Switch to Files tab
    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    expect(find.text('Locations'), findsOneWidget);

    // Switch to AI tab
    await tester.tap(find.text('AI'));
    await tester.pumpAndSettle();
    expect(find.text('100% On-Device AI Processing'), findsOneWidget);

    // Switch to Clean tab
    await tester.tap(find.text('Clean'));
    await tester.pumpAndSettle();
    expect(find.text('Zero Silent Deletions Contract'), findsOneWidget);

    // Switch to Vault tab
    await tester.tap(find.text('Vault'));
    await tester.pumpAndSettle();
    expect(find.text('Vault is Locked'), findsOneWidget);

    // Switch back to Home tab
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Internal Storage'), findsOneWidget);
  });
}
