// Widget tests for StudentEducationVerificationScreen, in isolation with a
// small GoRouter. Mirrors student_cv_screen_test.dart's/
// student_skills_screen_test.dart's conventions.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/core/widgets/app_widgets.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/cv/data/picked_cv_file.dart';
import 'package:opportunityhub_flutter/features/education_verification/data/education_verification_repository.dart';
import 'package:opportunityhub_flutter/features/education_verification/presentation/student_education_verification_screen.dart';
import 'package:opportunityhub_flutter/models/education_verification_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/student_education_verification_provider.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  @override
  Future<String?> getSavedToken() async => null;
}

EducationVerificationModel _verification({
  String status = 'not_submitted',
  String? institutionName = 'State University',
  String? degreeOrProgram = 'BSc Computer Science',
  String? rejectionReason,
}) {
  return EducationVerificationModel(
    institutionName: status == 'not_submitted' ? null : institutionName,
    degreeOrProgram: status == 'not_submitted' ? null : degreeOrProgram,
    status: status,
    rejectionReason: rejectionReason,
    submittedAt: status == 'not_submitted' ? null : DateTime(2026, 7, 1),
  );
}

PickedCvFile _fakeFile() =>
    PickedCvFile(filename: 'proof.pdf', bytes: Uint8List.fromList([1, 2, 3]));

class _FakeEducationVerificationRepository
    extends EducationVerificationRepository {
  _FakeEducationVerificationRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  EducationVerificationModel? statusResult;
  ApiException? statusError;
  Duration statusDelay = Duration.zero;
  int getStatusCallCount = 0;

  EducationVerificationModel? submitResult;
  ApiException? submitError;
  int submitCallCount = 0;
  String? lastInstitutionName;
  String? lastDegreeOrProgram;

  Uint8List? downloadResult;
  ApiException? downloadError;

  @override
  Future<EducationVerificationModel> getStatus() async {
    getStatusCallCount++;
    if (statusDelay > Duration.zero) {
      await Future<void>.delayed(statusDelay);
    }
    if (statusError != null) throw statusError!;
    return statusResult ?? _verification();
  }

  @override
  Future<EducationVerificationModel> submit({
    required String institutionName,
    required String degreeOrProgram,
    required PickedCvFile file,
  }) async {
    submitCallCount++;
    lastInstitutionName = institutionName;
    lastDegreeOrProgram = degreeOrProgram;
    if (submitError != null) throw submitError!;
    return submitResult ??
        _verification(
          status: 'pending',
          institutionName: institutionName,
          degreeOrProgram: degreeOrProgram,
        );
  }

  @override
  Future<Uint8List> downloadDocument() async {
    if (downloadError != null) throw downloadError!;
    return downloadResult ?? Uint8List.fromList([0x25, 0x50, 0x44, 0x46]);
  }
}

Future<StudentEducationVerificationProvider> _pumpScreen(
  WidgetTester tester, {
  required EducationVerificationRepository repository,
  Future<PickedCvFile?> Function() pickFile = _pickNothing,
  Size size = const Size(420, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final provider = StudentEducationVerificationProvider(
    repository: repository,
    authProvider: authProvider,
  );

  final router = GoRouter(
    initialLocation: '/student/education-verification',
    routes: [
      GoRoute(
        path: '/student/education-verification',
        builder: (_, _) =>
            StudentEducationVerificationScreen(pickDocumentFile: pickFile),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<StudentEducationVerificationProvider>.value(
          value: provider,
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  return provider;
}

Future<PickedCvFile?> _pickNothing() async => null;

void main() {
  testWidgets('Loading state renders while status is in flight', (
    tester,
  ) async {
    final repository = _FakeEducationVerificationRepository()
      ..statusResult = _verification()
      ..statusDelay = const Duration(milliseconds: 200);

    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final provider = StudentEducationVerificationProvider(
      repository: repository,
      authProvider: authProvider,
    );
    final router = GoRouter(
      initialLocation: '/student/education-verification',
      routes: [
        GoRoute(
          path: '/student/education-verification',
          builder: (_, _) => StudentEducationVerificationScreen(
            pickDocumentFile: _pickNothing,
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<StudentEducationVerificationProvider>.value(
            value: provider,
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(provider.isLoading, isTrue);

    await tester.pumpAndSettle();
  });

  testWidgets(
    'Error state with no verification shows AppErrorView and a working retry',
    (tester) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusError = ApiException('Server error, please try again later.');

      final provider = await _pumpScreen(tester, repository: repository);

      expect(
        find.text('Server error, please try again later.'),
        findsOneWidget,
      );

      repository.statusError = null;
      repository.statusResult = _verification();
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();

      expect(provider.verification?.isNotSubmitted, isTrue);
    },
  );

  group('Not submitted', () {
    testWidgets('Shows the submission form', (tester) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification();

      await _pumpScreen(tester, repository: repository);

      expect(find.text('Submit Education Proof'), findsOneWidget);
      expect(find.text('Select PDF'), findsOneWidget);
    });

    testWidgets('Blank fields show validation errors', (tester) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification();

      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.widgetWithText(PrimaryButton, 'Submit'));
      await tester.pumpAndSettle();

      expect(find.text('Institution is required'), findsOneWidget);
      expect(find.text('Degree / Program is required'), findsOneWidget);
      expect(repository.submitCallCount, 0);
    });

    testWidgets('No file selected shows an error and blocks submission', (
      tester,
    ) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification();

      await _pumpScreen(tester, repository: repository);

      await tester.enterText(
        find.widgetWithText(AppTextField, 'Institution'),
        'State University',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Degree / Program'),
        'BSc',
      );
      await tester.tap(find.widgetWithText(PrimaryButton, 'Submit'));
      await tester.pumpAndSettle();

      expect(find.text('Please select a PDF file.'), findsOneWidget);
      expect(repository.submitCallCount, 0);
    });

    testWidgets('A valid submission succeeds and shows pending state', (
      tester,
    ) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification();

      final provider = await _pumpScreen(
        tester,
        repository: repository,
        pickFile: () async => _fakeFile(),
      );

      await tester.enterText(
        find.widgetWithText(AppTextField, 'Institution'),
        'State University',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Degree / Program'),
        'BSc Computer Science',
      );
      await tester.tap(find.text('Select PDF'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(PrimaryButton, 'Submit'));
      await tester.pumpAndSettle();

      expect(repository.submitCallCount, 1);
      expect(repository.lastInstitutionName, 'State University');
      expect(provider.verification?.status, 'pending');
      expect(
        find.text('Education verification submitted successfully'),
        findsOneWidget,
      );
    });
  });

  group('Pending', () {
    testWidgets('Shows submitted details, a Pending badge, and a hint', (
      tester,
    ) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification(status: 'pending');

      await _pumpScreen(tester, repository: repository);

      expect(find.text('State University'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Awaiting Admin review.'), findsOneWidget);
      expect(find.text('View Document'), findsOneWidget);
    });

    testWidgets('View Document downloads and confirms success', (tester) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification(status: 'pending')
        ..downloadResult = Uint8List(2048);

      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('View Document'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Document downloaded'), findsOneWidget);
    });
  });

  group('Verified', () {
    testWidgets('Shows a Verified badge and read-only details, no form', (
      tester,
    ) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification(status: 'verified');

      await _pumpScreen(tester, repository: repository);

      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('Submit Education Proof'), findsNothing);
      expect(find.text('Resubmit Document'), findsNothing);
      expect(find.text('Select PDF'), findsNothing);
    });
  });

  group('Rejected', () {
    testWidgets('Shows the rejection reason and a resubmission form', (
      tester,
    ) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification(
          status: 'rejected',
          rejectionReason: 'Document is unreadable.',
        );

      await _pumpScreen(tester, repository: repository);

      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text('Document is unreadable.'), findsOneWidget);
      expect(find.text('Resubmit Document'), findsOneWidget);
      expect(find.text('Select PDF'), findsOneWidget);
    });

    testWidgets('Fields are pre-filled with the previous submission', (
      tester,
    ) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification(
          status: 'rejected',
          institutionName: 'Old University',
          degreeOrProgram: 'BSc Old',
          rejectionReason: 'Blurry.',
        );

      await _pumpScreen(tester, repository: repository);

      final institutionField = tester.widget<TextFormField>(
        find.descendant(
          of: find.widgetWithText(AppTextField, 'Institution'),
          matching: find.byType(TextFormField),
        ),
      );
      expect(institutionField.controller?.text, 'Old University');
    });

    testWidgets('Resubmitting succeeds and moves to pending', (tester) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification(
          status: 'rejected',
          rejectionReason: 'Blurry.',
        );

      final provider = await _pumpScreen(
        tester,
        repository: repository,
        pickFile: () async => _fakeFile(),
      );

      await tester.tap(find.text('Select PDF'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(PrimaryButton, 'Resubmit'));
      await tester.pumpAndSettle();

      expect(repository.submitCallCount, 1);
      expect(provider.verification?.status, 'pending');
    });
  });

  testWidgets('No overflow at a narrow 320-wide viewport', (tester) async {
    final repository = _FakeEducationVerificationRepository()
      ..statusResult = _verification(status: 'pending');

    await _pumpScreen(
      tester,
      repository: repository,
      size: const Size(320, 700),
    );

    expect(tester.takeException(), isNull);
  });
}
