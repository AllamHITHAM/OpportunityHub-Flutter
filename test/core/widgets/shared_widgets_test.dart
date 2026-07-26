// Focused, behavior-only widget tests for the Phase 1B shared UI
// components. No network requests and no Flutter-internals testing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/widgets/app_avatar.dart';
import 'package:opportunityhub_flutter/core/widgets/app_confirmation_dialog.dart';
import 'package:opportunityhub_flutter/core/widgets/app_empty_view.dart';
import 'package:opportunityhub_flutter/core/widgets/app_password_field.dart';
import 'package:opportunityhub_flutter/core/widgets/app_search_field.dart';
import 'package:opportunityhub_flutter/core/widgets/primary_button.dart';
import 'package:opportunityhub_flutter/core/widgets/status_chip.dart';

Future<void> _pumpApp(WidgetTester tester, Widget child) {
  return tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  group('PrimaryButton', () {
    testWidgets('ignores taps while isLoading', (tester) async {
      var tapCount = 0;
      await _pumpApp(
        tester,
        PrimaryButton(
          label: 'Submit',
          isLoading: true,
          onPressed: () => tapCount++,
        ),
      );

      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();

      expect(tapCount, 0);
    });
  });

  group('AppPasswordField', () {
    testWidgets('toggles password visibility', (tester) async {
      await _pumpApp(tester, const AppPasswordField());

      expect(
        (tester.widget(find.byType(TextField)) as TextField).obscureText,
        isTrue,
      );
      expect(find.byTooltip('Show password'), findsOneWidget);

      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();

      expect(
        (tester.widget(find.byType(TextField)) as TextField).obscureText,
        isFalse,
      );
      expect(find.byTooltip('Hide password'), findsOneWidget);
    });
  });

  group('AppEmptyView', () {
    testWidgets('renders its action and triggers its callback', (tester) async {
      var tapped = false;
      await _pumpApp(
        tester,
        AppEmptyView(
          message: 'No applications yet',
          actionLabel: 'Browse Opportunities',
          onAction: () => tapped = true,
        ),
      );

      expect(find.text('Browse Opportunities'), findsOneWidget);

      await tester.tap(find.text('Browse Opportunities'));
      await tester.pump();

      expect(tapped, isTrue);
    });
  });

  group('AppConfirmationDialog', () {
    testWidgets('returns true when confirmed', (tester) async {
      bool? result;

      await _pumpApp(
        tester,
        Builder(
          builder: (context) => PrimaryButton(
            label: 'Open',
            onPressed: () async {
              result = await showAppConfirmationDialog(
                context,
                title: 'Delete item?',
                message: 'This cannot be undone.',
                type: AppConfirmationType.danger,
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('resolves to false when cancelled', (tester) async {
      bool? result;

      await _pumpApp(
        tester,
        Builder(
          builder: (context) => PrimaryButton(
            label: 'Open',
            onPressed: () async {
              result = await showAppConfirmationDialog(
                context,
                title: 'Sign out?',
                message: 'You will need to log in again.',
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });
  });

  group('StatusChip', () {
    testWidgets('renders the provided label', (tester) async {
      await _pumpApp(
        tester,
        const StatusChip(label: 'Shortlisted', type: AppStatusType.success),
      );

      expect(find.text('Shortlisted'), findsOneWidget);
    });
  });

  group('AppAvatar', () {
    testWidgets('generates one initial for a one-word name', (tester) async {
      await _pumpApp(tester, const AppAvatar(name: 'John'));
      expect(find.text('J'), findsOneWidget);
    });

    testWidgets('generates two initials for a two-word name', (tester) async {
      await _pumpApp(tester, const AppAvatar(name: 'John Smith'));
      expect(find.text('JS'), findsOneWidget);
    });

    testWidgets('falls back to an icon for an empty name', (tester) async {
      await _pumpApp(tester, const AppAvatar(name: '   '));

      expect(find.byIcon(Icons.person_outline), findsOneWidget);
      expect(find.byType(Text), findsNothing);
    });
  });

  group('AppSearchField', () {
    testWidgets('shows and triggers its clear action when text exists', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'flutter developer');
      var cleared = false;

      await _pumpApp(
        tester,
        AppSearchField(controller: controller, onClear: () => cleared = true),
      );

      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(controller.text, isEmpty);
      expect(cleared, isTrue);
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('hides the clear action when there is no text', (tester) async {
      final controller = TextEditingController();

      await _pumpApp(tester, AppSearchField(controller: controller));

      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.byIcon(Icons.search), findsOneWidget);
    });
  });
}
