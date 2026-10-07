import 'package:filezen/core/widgets/empty_view.dart';
import 'package:filezen/core/widgets/error_view.dart';
import 'package:filezen/core/widgets/loading_view.dart';
import 'package:filezen/core/widgets/offline_banner.dart';
import 'package:filezen/core/widgets/permission_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrapWithMaterial(Widget child) {
    return MaterialApp(
      home: Scaffold(body: child),
    );
  }

  testWidgets('LoadingView displays message and indicator', (tester) async {
    await tester.pumpWidget(
      wrapWithMaterial(
        const LoadingView(message: 'Indexing files...', progress: 0.5),
      ),
    );

    expect(find.text('Indexing files...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('EmptyView displays title, subtitle, and triggers action', (tester) async {
    bool actionTriggered = false;

    await tester.pumpWidget(
      wrapWithMaterial(
        EmptyView(
          icon: Icons.folder_open,
          title: 'No Files Found',
          subtitle: 'This directory is completely empty',
          actionLabel: 'Create File',
          onAction: () => actionTriggered = true,
        ),
      ),
    );

    expect(find.text('No Files Found'), findsOneWidget);
    expect(find.text('This directory is completely empty'), findsOneWidget);
    expect(find.text('Create File'), findsOneWidget);

    await tester.tap(find.text('Create File'));
    expect(actionTriggered, isTrue);
  });

  testWidgets('ErrorView displays message and triggers retry', (tester) async {
    bool retryTriggered = false;

    await tester.pumpWidget(
      wrapWithMaterial(
        ErrorView(
          title: 'Read Failure',
          message: 'Unable to read directory contents',
          recoverySuggestion: 'Check storage permissions',
          onRetry: () => retryTriggered = true,
        ),
      ),
    );

    expect(find.text('Read Failure'), findsOneWidget);
    expect(find.text('Unable to read directory contents'), findsOneWidget);
    expect(find.text('Check storage permissions'), findsOneWidget);

    await tester.tap(find.text('Try Again'));
    expect(retryTriggered, isTrue);
  });

  testWidgets('PermissionView displays rationale and triggers grant', (tester) async {
    bool grantTriggered = false;

    await tester.pumpWidget(
      wrapWithMaterial(
        PermissionView(
          title: 'Storage Required',
          rationale: 'Access needed to browse and manage local files',
          onGrant: () => grantTriggered = true,
        ),
      ),
    );

    expect(find.text('Storage Required'), findsOneWidget);
    expect(find.text('Access needed to browse and manage local files'), findsOneWidget);

    await tester.tap(find.text('Grant Access'));
    expect(grantTriggered, isTrue);
  });

  testWidgets('OfflineBanner renders offline text', (tester) async {
    await tester.pumpWidget(
      wrapWithMaterial(
        const OfflineBanner(),
      ),
    );

    expect(find.text('Offline mode active • Local file management works 100% offline'), findsOneWidget);
  });
}
