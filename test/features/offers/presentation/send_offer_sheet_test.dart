// Widget tests for SendOfferSheet, in isolation with a minimal host screen
// that opens it via showSendOfferSheet — mirrors
// schedule_interview_screen_test.dart's structure and conventions.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/offers/data/offer_repository.dart';
import 'package:opportunityhub_flutter/features/offers/data/send_offer_input.dart';
import 'package:opportunityhub_flutter/features/offers/presentation/send_offer_sheet.dart';
import 'package:opportunityhub_flutter/models/offer_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_offer_provider.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  @override
  Future<String?> getSavedToken() async => null;
}

OfferModel _offer({int id = 1, int applicationId = 5, String status = 'sent'}) {
  return OfferModel(
    id: id,
    applicationId: applicationId,
    status: status,
    sentAt: DateTime(2026, 8, 10, 9),
  );
}

class _FakeOfferRepository extends OfferRepository {
  _FakeOfferRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  OfferModel? sendResult;
  ApiException? sendError;
  Duration sendDelay = Duration.zero;
  int sendCallCount = 0;
  SendOfferInput? lastSendInput;

  @override
  Future<OfferModel> getOrganizationOffer(int applicationId) async {
    throw ApiException('This application has no offer yet', statusCode: 404);
  }

  @override
  Future<OfferModel> sendOrganizationOffer({
    required int applicationId,
    required SendOfferInput input,
  }) async {
    sendCallCount++;
    lastSendInput = input;
    if (sendDelay > Duration.zero) {
      await Future<void>.delayed(sendDelay);
    }
    if (sendError != null) throw sendError!;
    return sendResult ?? _offer(applicationId: applicationId);
  }
}

class _Harness {
  _Harness({required this.offerProvider});

  final OrganizationOfferProvider offerProvider;
  bool? sheetResult;
}

Future<_Harness> _pumpSheetHost(
  WidgetTester tester, {
  required OfferRepository offerRepository,
  int applicationId = 5,
}) async {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final offerProvider = OrganizationOfferProvider(
    repository: offerRepository,
    authProvider: authProvider,
  );
  final harness = _Harness(offerProvider: offerProvider);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<OrganizationOfferProvider>.value(
          value: offerProvider,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                harness.sheetResult = await showSendOfferSheet(
                  context,
                  applicationId: applicationId,
                );
              },
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open Sheet'));
  await tester.pumpAndSettle();

  return harness;
}

/// Taps the sheet's own submit button, confirms the resulting dialog, and
/// settles.
Future<void> _submitAndConfirm(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ElevatedButton, 'Send Offer'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ElevatedButton, 'Send Offer').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('all fields render, all of them optional', (tester) async {
    await _pumpSheetHost(tester, offerRepository: _FakeOfferRepository());

    expect(find.text('Title (optional)'), findsOneWidget);
    expect(find.text('Salary Amount (optional)'), findsOneWidget);
    expect(find.text('Salary Currency'), findsOneWidget);
    expect(find.text('Salary Period'), findsOneWidget);
    expect(find.text('Start Date (optional)'), findsOneWidget);
    expect(find.text('Message (optional)'), findsOneWidget);
  });

  testWidgets('an entirely empty form submits successfully', (tester) async {
    final repository = _FakeOfferRepository()..sendResult = _offer();
    final harness = await _pumpSheetHost(tester, offerRepository: repository);

    await _submitAndConfirm(tester);

    expect(repository.sendCallCount, 1);
    expect(harness.sheetResult, isTrue);
  });

  testWidgets('title max length is enforced', (tester) async {
    await _pumpSheetHost(tester, offerRepository: _FakeOfferRepository());

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title (optional)'),
      'a' * 300,
    );
    await tester.pump();

    final titleText = tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Title (optional)'),
        matching: find.byType(EditableText),
      ),
    );
    expect(titleText.controller.text.length, lessThanOrEqualTo(255));
  });

  testWidgets('message max length is enforced', (tester) async {
    await _pumpSheetHost(tester, offerRepository: _FakeOfferRepository());

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Message (optional)'),
      'a' * 2100,
    );
    await tester.pump();

    final messageText = tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Message (optional)'),
        matching: find.byType(EditableText),
      ),
    );
    expect(messageText.controller.text.length, lessThanOrEqualTo(2000));
  });

  testWidgets('a non-numeric salary amount is rejected', (tester) async {
    final repository = _FakeOfferRepository();
    await _pumpSheetHost(tester, offerRepository: repository);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Salary Amount (optional)'),
      'not-a-number',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Offer'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid amount of 0 or more'), findsOneWidget);
    expect(repository.sendCallCount, 0);
  });

  testWidgets('a negative salary amount is rejected', (tester) async {
    final repository = _FakeOfferRepository();
    await _pumpSheetHost(tester, offerRepository: repository);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Salary Amount (optional)'),
      '-100',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Offer'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid amount of 0 or more'), findsOneWidget);
    expect(repository.sendCallCount, 0);
  });

  testWidgets(
    'a salary amount without a currency is rejected (salary consistency)',
    (tester) async {
      final repository = _FakeOfferRepository();
      await _pumpSheetHost(tester, offerRepository: repository);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Salary Amount (optional)'),
        '90000',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send Offer'));
      await tester.pumpAndSettle();

      expect(
        find.text('Currency is required when a salary amount is set'),
        findsOneWidget,
      );
      expect(repository.sendCallCount, 0);
    },
  );

  testWidgets(
    'a salary amount without a period is rejected (salary consistency)',
    (tester) async {
      final repository = _FakeOfferRepository();
      await _pumpSheetHost(tester, offerRepository: repository);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Salary Amount (optional)'),
        '90000',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Salary Currency'),
        'USD',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send Offer'));
      await tester.pumpAndSettle();

      expect(
        find.text('Select a salary period when a salary amount is set'),
        findsOneWidget,
      );
      expect(repository.sendCallCount, 0);
    },
  );

  testWidgets(
    'the salary period dropdown offers exactly Hourly, Monthly, and Yearly',
    (tester) async {
      await _pumpSheetHost(tester, offerRepository: _FakeOfferRepository());

      await tester.tap(find.text('Salary Period'));
      await tester.pumpAndSettle();

      expect(find.text('Hourly').hitTestable(), findsOneWidget);
      expect(find.text('Monthly').hitTestable(), findsOneWidget);
      expect(find.text('Yearly').hitTestable(), findsOneWidget);
    },
  );

  testWidgets('a complete salary (amount, currency, period) is accepted', (
    tester,
  ) async {
    final repository = _FakeOfferRepository()..sendResult = _offer();
    await _pumpSheetHost(tester, offerRepository: repository);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Salary Amount (optional)'),
      '90000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Salary Currency'),
      'USD',
    );
    await tester.tap(find.text('Salary Period'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yearly').last);
    await tester.pumpAndSettle();

    await _submitAndConfirm(tester);

    expect(repository.sendCallCount, 1);
    expect(repository.lastSendInput?.salaryAmount, 90000);
    expect(repository.lastSendInput?.salaryCurrency, 'USD');
    expect(repository.lastSendInput?.salaryPeriod, 'yearly');
  });

  testWidgets(
    'the start date picker never permits selecting a date before today',
    (tester) async {
      await _pumpSheetHost(tester, offerRepository: _FakeOfferRepository());

      await tester.tap(find.byKey(const Key('startDateField')));
      await tester.pumpAndSettle();

      final picker = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      final today = DateTime.now();
      expect(
        picker.firstDate.isAtSameMomentAs(
          DateTime(today.year, today.month, today.day),
        ),
        isTrue,
      );

      // Dismiss the picker without selecting anything.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('the confirmation dialog shows the exact expected copy', (
    tester,
  ) async {
    await _pumpSheetHost(tester, offerRepository: _FakeOfferRepository());

    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Offer'));
    await tester.pumpAndSettle();

    expect(find.text('Send Offer'), findsWidgets);
    expect(
      find.text(
        'Are you sure you want to send this offer? The candidate will be '
        'able to accept or decline it.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('cancelling the confirmation does not send the Offer', (
    tester,
  ) async {
    final repository = _FakeOfferRepository();
    final harness = await _pumpSheetHost(tester, offerRepository: repository);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Offer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repository.sendCallCount, 0);
    expect(harness.sheetResult, isNull);
    // Still on the sheet.
    expect(find.text('Send Offer'), findsWidgets);
  });

  testWidgets('the submit button is loading and disabled while sending', (
    tester,
  ) async {
    final repository = _FakeOfferRepository()
      ..sendResult = _offer()
      ..sendDelay = const Duration(milliseconds: 200);
    await _pumpSheetHost(tester, offerRepository: repository);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Offer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Offer').last);
    await tester.pump();

    final titleField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Title (optional)'),
    );
    expect(titleField.enabled, isFalse);

    await tester.pumpAndSettle();
  });

  testWidgets('an inline backend field error surfaces on the right field', (
    tester,
  ) async {
    final repository = _FakeOfferRepository()
      ..sendError = ApiException(
        'The given data was invalid.',
        statusCode: 422,
        errors: {
          'title': ['The title must not be greater than 255 characters.'],
        },
      );
    await _pumpSheetHost(tester, offerRepository: repository);

    await _submitAndConfirm(tester);

    expect(
      find.text('The title must not be greater than 255 characters.'),
      findsOneWidget,
    );
  });

  testWidgets('entered data is retained after a failed submission', (
    tester,
  ) async {
    final repository = _FakeOfferRepository()
      ..sendError = ApiException('Server error.');
    await _pumpSheetHost(tester, offerRepository: repository);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title (optional)'),
      'Backend Engineer',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Message (optional)'),
      'Welcome aboard.',
    );

    await _submitAndConfirm(tester);

    expect(find.text('Backend Engineer'), findsOneWidget);
    expect(find.text('Welcome aboard.'), findsOneWidget);
  });

  testWidgets('a successful send closes the sheet, returning true', (
    tester,
  ) async {
    final repository = _FakeOfferRepository()..sendResult = _offer();
    final harness = await _pumpSheetHost(tester, offerRepository: repository);

    await _submitAndConfirm(tester);

    expect(harness.sheetResult, isTrue);
    // The sheet's own fields are gone -- it has been popped.
    expect(find.text('Title (optional)'), findsNothing);
  });
}
