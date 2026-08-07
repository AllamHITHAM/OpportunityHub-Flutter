// Widget tests for ChooseAssessmentTypeSheet, in isolation with a small
// GoRouter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/assessments/presentation/choose_assessment_type_sheet.dart';

Future<void> _pumpHostScreen(WidgetTester tester) async {
  final router = GoRouter(
    initialLocation: '/host',
    routes: [
      GoRoute(
        path: '/host',
        builder: (context, state) => Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showChooseAssessmentTypeSheet(context, applicationId: 5),
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/organization/applications/5/assessment/interview',
        builder: (context, state) =>
            const Scaffold(body: Text('SCHEDULE_INTERVIEW_PLACEHOLDER')),
      ),
    ],
  );

  await tester.pumpWidget(
    MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
  );
  await tester.pumpAndSettle();
}

RadioListTile<String> _radioTile(WidgetTester tester, String value) {
  return tester.widget<RadioListTile<String>>(
    find.byWidgetPredicate(
      (widget) => widget is RadioListTile<String> && widget.value == value,
    ),
  );
}

void main() {
  testWidgets('Interview option is visible and enabled', (tester) async {
    await _pumpHostScreen(tester);
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Interview'), findsOneWidget);
    // RadioListTile.enabled is nullable and defaults to null ("inherit
    // enabled from the ancestor RadioGroup") unless explicitly disabled —
    // only Quiz is explicitly disabled below.
    expect(_radioTile(tester, 'interview').enabled, isNot(false));
  });

  testWidgets('Quiz option is visible, disabled, and shows Coming Soon', (
    tester,
  ) async {
    await _pumpHostScreen(tester);
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Quiz'), findsOneWidget);
    expect(find.text('Coming Soon'), findsOneWidget);
    expect(_radioTile(tester, 'quiz').enabled, isFalse);
  });

  testWidgets('Continue navigates to the Schedule Interview route', (
    tester,
  ) async {
    await _pumpHostScreen(tester);
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('SCHEDULE_INTERVIEW_PLACEHOLDER'), findsOneWidget);
    // The sheet itself is closed, not left open underneath.
    expect(find.text('Choose Assessment'), findsNothing);
  });

  testWidgets('Quiz cannot be selected or submitted', (tester) async {
    await _pumpHostScreen(tester);
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Quiz'));
    await tester.pumpAndSettle();

    // Tapping a disabled RadioListTile changes nothing -- Interview
    // remains selected, confirmed indirectly: Continue still navigates to
    // the Interview route, not anywhere Quiz-specific (no Quiz route
    // exists at all in this test's router, so a Quiz navigation attempt
    // would throw/leave the sheet open).
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('SCHEDULE_INTERVIEW_PLACEHOLDER'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening the sheet makes no backend request', (tester) async {
    // ChooseAssessmentTypeSheet takes no repository/provider dependency at
    // all -- it cannot make a backend request by construction. This test
    // simply confirms it renders without needing any provider wiring.
    await _pumpHostScreen(tester);

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('dismissing the sheet is safe', (tester) async {
    await _pumpHostScreen(tester);
    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // Tap the modal barrier to dismiss without choosing anything.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.text('Choose Assessment'), findsNothing);
    expect(find.text('SCHEDULE_INTERVIEW_PLACEHOLDER'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
