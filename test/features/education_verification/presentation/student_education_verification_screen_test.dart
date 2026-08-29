// Widget tests for the premium StudentEducationVerificationScreen (Phase
// 8), in isolation with a small GoRouter. Mirrors
// student_cv_screen_test.dart's/student_skills_screen_test.dart's
// conventions.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/core/utils/cv_file_open_result.dart';
import 'package:opportunityhub_flutter/core/widgets/app_widgets.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/cv/data/picked_cv_file.dart';
import 'package:opportunityhub_flutter/features/education_verification/data/education_verification_repository.dart';
import 'package:opportunityhub_flutter/features/education_verification/presentation/student_education_verification_screen.dart';
import 'package:opportunityhub_flutter/models/education_verification_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/student_education_verification_provider.dart';
import 'package:opportunityhub_flutter/providers/theme_provider.dart';
import 'package:opportunityhub_flutter/routes/app_routes.dart';

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
  DateTime? reviewedAt,
}) {
  return EducationVerificationModel(
    institutionName: status == 'not_submitted' ? null : institutionName,
    degreeOrProgram: status == 'not_submitted' ? null : degreeOrProgram,
    status: status,
    rejectionReason: rejectionReason,
    submittedAt: status == 'not_submitted' ? null : DateTime(2026, 7, 1),
    reviewedAt: reviewedAt,
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

class _FakeFileAction {
  _FakeFileAction();
  CvFileOpenResult result = const CvFileOpenResult(success: true);
  int callCount = 0;
  String? lastFileName;

  Future<CvFileOpenResult> call(Uint8List bytes, String fileName) async {
    callCount++;
    lastFileName = fileName;
    return result;
  }
}

Future<StudentEducationVerificationProvider> _pumpScreen(
  WidgetTester tester, {
  required EducationVerificationRepository repository,
  Future<PickedCvFile?> Function() pickFile = _pickNothing,
  Size size = const Size(420, 1400),
  ThemeData? theme,
  _FakeFileAction? viewDocumentFile,
  _FakeFileAction? downloadDocumentFile,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final provider = StudentEducationVerificationProvider(
    repository: repository,
    authProvider: authProvider,
    viewDocumentFile: (viewDocumentFile ?? _FakeFileAction()).call,
    downloadDocumentFile: (downloadDocumentFile ?? _FakeFileAction()).call,
  );

  final router = GoRouter(
    initialLocation: AppRoutes.studentEducationVerification,
    routes: [
      GoRoute(
        path: AppRoutes.studentEducationVerification,
        builder: (_, _) =>
            StudentEducationVerificationScreen(pickDocumentFile: pickFile),
      ),
      GoRoute(
        path: AppRoutes.studentProfile,
        builder: (_, _) => const Scaffold(body: Text('PROFILE_PLACEHOLDER')),
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
        ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ],
      child: MaterialApp.router(
        theme: theme ?? AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  return provider;
}

Future<PickedCvFile?> _pickNothing() async => null;

void main() {
  testWidgets('Loading state renders a skeleton while status is in flight', (
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
      initialLocation: AppRoutes.studentEducationVerification,
      routes: [
        GoRoute(
          path: AppRoutes.studentEducationVerification,
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
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
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
    expect(find.byType(AppCardSkeleton), findsWidgets);

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

  testWidgets('the app-bar theme toggle is reachable', (tester) async {
    final repository = _FakeEducationVerificationRepository()
      ..statusResult = _verification();

    await _pumpScreen(tester, repository: repository);

    expect(find.byType(ThemeToggleButton), findsOneWidget);
  });

  group('Not submitted', () {
    testWidgets('Shows the real status hero and the submission form', (
      tester,
    ) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification();

      await _pumpScreen(tester, repository: repository);

      expect(find.text('Not Submitted'), findsOneWidget);
      expect(find.text('Upload Academic Document'), findsOneWidget);
      expect(find.text('Select PDF'), findsOneWidget);
    });

    testWidgets('never fabricates a document card when nothing was submitted', (
      tester,
    ) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification();

      await _pumpScreen(tester, repository: repository);

      expect(find.text('Submitted Document'), findsNothing);
    });

    testWidgets('Blank fields show validation errors', (tester) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification();

      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.widgetWithText(PrimaryButton, 'Submit for Verification'));
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
      await tester.tap(find.widgetWithText(PrimaryButton, 'Submit for Verification'));
      await tester.pumpAndSettle();

      expect(find.text('Please select a PDF file.'), findsOneWidget);
      expect(repository.submitCallCount, 0);
    });

    testWidgets('A valid submission succeeds and transitions to pending', (
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
      await tester.tap(find.widgetWithText(PrimaryButton, 'Submit for Verification'));
      await tester.pumpAndSettle();

      expect(repository.submitCallCount, 1);
      expect(repository.lastInstitutionName, 'State University');
      expect(provider.verification?.status, 'pending');
      expect(
        find.text('Education verification submitted successfully'),
        findsOneWidget,
      );
      expect(find.text('Pending Review'), findsOneWidget);
    });
  });

  group('Pending', () {
    testWidgets(
      'Shows verification details, a Pending Review status, and the document card -- no form',
      (tester) async {
        final repository = _FakeEducationVerificationRepository()
          ..statusResult = _verification(status: 'pending');

        await _pumpScreen(tester, repository: repository);

        expect(find.text('Pending Review'), findsOneWidget);
        expect(find.text('State University'), findsOneWidget);
        expect(find.text('Submitted Document'), findsOneWidget);
        expect(find.text('View Document'), findsOneWidget);
        expect(find.text('Download'), findsOneWidget);
        // Phase 8.1: Replace Document is offered directly (the backend
        // already allows it), but the upload form itself stays hidden
        // until the student confirms.
        expect(find.text('Replace Document'), findsOneWidget);
        expect(find.text('Select PDF'), findsNothing);
      },
    );

    testWidgets('View Document fetches real bytes and triggers the real viewer', (
      tester,
    ) async {
      final viewFile = _FakeFileAction();
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification(status: 'pending')
        ..downloadResult = Uint8List(2048);

      await _pumpScreen(tester, repository: repository, viewDocumentFile: viewFile);

      await tester.tap(find.text('View Document'));
      await tester.pumpAndSettle();

      expect(viewFile.callCount, 1);
      expect(viewFile.lastFileName, 'State University - Education Verification.pdf');
      // No fake "downloaded" success message -- real success is silent
      // (the tab actually opened).
      expect(find.textContaining('downloaded'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Download fetches real bytes and triggers a real download, distinct from View', (
      tester,
    ) async {
      final viewFile = _FakeFileAction();
      final downloadFile = _FakeFileAction();
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification(status: 'pending')
        ..downloadResult = Uint8List(2048);

      await _pumpScreen(
        tester,
        repository: repository,
        viewDocumentFile: viewFile,
        downloadDocumentFile: downloadFile,
      );

      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();

      expect(downloadFile.callCount, 1);
      expect(viewFile.callCount, 0);
    });

    testWidgets('a real viewer failure shows its own safe error', (
      tester,
    ) async {
      final viewFile = _FakeFileAction()
        ..result = const CvFileOpenResult(
          success: false,
          errorMessage: "Couldn't open the document.",
        );
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification(status: 'pending');

      await _pumpScreen(tester, repository: repository, viewDocumentFile: viewFile);

      await tester.tap(find.text('View Document'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't open the document."), findsOneWidget);
    });

    testWidgets('shows the truthful what-happens-next panel, no promised timing', (
      tester,
    ) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification(status: 'pending');

      await _pumpScreen(tester, repository: repository, size: const Size(1440, 1000));

      expect(find.text('What Happens Next'), findsOneWidget);
      expect(find.textContaining('24 hours'), findsNothing);
      expect(find.textContaining('business days'), findsNothing);
    });
  });

  group('Replace Document (Phase 8.1)', () {
    testWidgets('tapping Replace Document shows a confirmation dialog first', (
      tester,
    ) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification(status: 'pending');

      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Replace Document'));
      await tester.pumpAndSettle();

      expect(find.text('Replace submitted document?'), findsOneWidget);
      expect(
        find.textContaining('will replace the current submission for review'),
        findsOneWidget,
      );
      expect(find.text('Continue'), findsOneWidget);
      // The upload form has not opened yet -- only the dialog has.
      expect(find.text('Select PDF'), findsNothing);
    });

    testWidgets('Cancel on the dialog opens nothing and submits nothing', (
      tester,
    ) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification(status: 'pending');

      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Replace Document'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Select PDF'), findsNothing);
      expect(find.text('View Document'), findsOneWidget);
      expect(repository.submitCallCount, 0);
    });

    testWidgets('Continue opens the real upload flow, pre-filled from the current submission', (
      tester,
    ) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification(status: 'pending');

      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Replace Document'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Select PDF'), findsOneWidget);
      final institutionField = tester.widget<TextFormField>(
        find.descendant(
          of: find.widgetWithText(AppTextField, 'Institution'),
          matching: find.byType(TextFormField),
        ),
      );
      expect(institutionField.controller?.text, 'State University');
    });

    testWidgets('Cancel inside the upload form returns to the document view', (
      tester,
    ) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification(status: 'pending');

      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Replace Document'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SecondaryButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Select PDF'), findsNothing);
      expect(find.text('View Document'), findsOneWidget);
      expect(repository.submitCallCount, 0);
    });

    testWidgets(
      'a successful replacement persists, shows a truthful confirmation, and returns to the document view',
      (tester) async {
        final repository = _FakeEducationVerificationRepository()
          ..statusResult = _verification(status: 'pending')
          ..submitResult = _verification(
            status: 'pending',
            institutionName: 'State University',
            degreeOrProgram: 'BSc (corrected)',
          );

        final provider = await _pumpScreen(
          tester,
          repository: repository,
          pickFile: () async => _fakeFile(),
        );

        await tester.tap(find.text('Replace Document'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select PDF'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(PrimaryButton, 'Replace Document'));
        await tester.pumpAndSettle();

        expect(repository.submitCallCount, 1);
        expect(find.text('Document replaced successfully.'), findsOneWidget);
        expect(provider.verification?.degreeOrProgram, 'BSc (corrected)');
        // The form collapses back to the document view -- no lingering
        // upload UI after a real success.
        expect(find.text('Select PDF'), findsNothing);
        expect(find.text('View Document'), findsOneWidget);
      },
    );

    testWidgets(
      'a replacement failure shows the real error inline and keeps the form open',
      (tester) async {
        final repository = _FakeEducationVerificationRepository()
          ..statusResult = _verification(status: 'pending')
          ..submitError = ApiException('Server error, please try again later.');

        await _pumpScreen(
          tester,
          repository: repository,
          pickFile: () async => _fakeFile(),
        );

        await tester.tap(find.text('Replace Document'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select PDF'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(PrimaryButton, 'Replace Document'));
        await tester.pumpAndSettle();

        expect(
          find.text('Server error, please try again later.'),
          findsOneWidget,
        );
        // The form stays open with the selected file preserved -- a
        // recoverable failure never silently discards the student's work.
        expect(find.text('Select PDF'), findsNothing);
        expect(find.text('Change PDF'), findsOneWidget);
        expect(repository.submitCallCount, 1);
      },
    );
  });

  group('Verification Journey (Phase 8.1)', () {
    testWidgets('not_submitted shows the journey with nothing yet complete', (
      tester,
    ) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification();

      await _pumpScreen(tester, repository: repository);

      expect(find.text('Verification Journey'), findsOneWidget);
      expect(find.text('Submitted'), findsOneWidget);
      expect(find.text('Admin Review'), findsOneWidget);
      expect(find.text('Decision'), findsOneWidget);
    });

    testWidgets('pending shows the journey with Admin Review current', (
      tester,
    ) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification(status: 'pending');

      await _pumpScreen(tester, repository: repository);

      expect(find.text('Verification Journey'), findsOneWidget);
      expect(find.text('Admin Review'), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    });

    testWidgets('verified shows the journey fully complete', (tester) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification(status: 'verified');

      await _pumpScreen(tester, repository: repository);

      expect(find.text('Verification Journey'), findsOneWidget);
      // Three completed stages -- three check icons.
      expect(find.byIcon(Icons.check_rounded), findsNWidgets(3));
    });

    testWidgets('rejected shows the journey with a rejected decision', (
      tester,
    ) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification(
          status: 'rejected',
          rejectionReason: 'Blurry.',
        );

      await _pumpScreen(tester, repository: repository);

      expect(find.text('Verification Journey'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      // Submitted + Admin Review are complete -- two checks, not three.
      expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
    });

    testWidgets('never introduces a fake fifth status or backend call', (
      tester,
    ) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification(status: 'pending');

      await _pumpScreen(tester, repository: repository);

      expect(repository.getStatusCallCount, 1);
      expect(find.textContaining('queue'), findsNothing);
      expect(find.textContaining('minutes'), findsNothing);
    });
  });

  group('Verified', () {
    testWidgets('Shows a Verified status and read-only details, no form', (
      tester,
    ) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification(
          status: 'verified',
          reviewedAt: DateTime(2026, 7, 5),
        );

      await _pumpScreen(tester, repository: repository);

      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('Upload Academic Document'), findsNothing);
      expect(find.text('Resubmit Document'), findsNothing);
      expect(find.text('Replace Document'), findsNothing);
      expect(find.text('Select PDF'), findsNothing);
      expect(find.text('Submitted Document'), findsOneWidget);
    });
  });

  group('Rejected', () {
    testWidgets('Shows the real rejection reason and a resubmission form', (
      tester,
    ) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification(
          status: 'rejected',
          rejectionReason: 'Document is unreadable.',
        );

      await _pumpScreen(tester, repository: repository);

      expect(find.text('Rejected'), findsOneWidget);
      expect(find.text('Review Feedback'), findsOneWidget);
      expect(find.text('Document is unreadable.'), findsOneWidget);
      expect(find.text('Resubmit Document'), findsOneWidget);
      expect(find.text('Select PDF'), findsOneWidget);
    });

    testWidgets('the previously-submitted document remains viewable', (
      tester,
    ) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification(
          status: 'rejected',
          rejectionReason: 'Blurry.',
        );

      await _pumpScreen(tester, repository: repository);

      expect(find.text('Submitted Document'), findsOneWidget);
      expect(find.text('View Document'), findsOneWidget);
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
      await tester.ensureVisible(find.widgetWithText(PrimaryButton, 'Resubmit'));
      await tester.tap(find.widgetWithText(PrimaryButton, 'Resubmit'));
      await tester.pumpAndSettle();

      expect(repository.submitCallCount, 1);
      expect(provider.verification?.status, 'pending');
    });
  });

  group('Profile connection', () {
    testWidgets('Back to Profile navigates to the real profile route', (
      tester,
    ) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification(status: 'pending');

      await _pumpScreen(tester, repository: repository, size: const Size(1440, 1000));

      await tester.tap(find.text('Back to Profile'));
      await tester.pumpAndSettle();

      expect(find.text('PROFILE_PLACEHOLDER'), findsOneWidget);
    });
  });

  group('Responsive layout', () {
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

    testWidgets('No overflow on a tablet viewport', (tester) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification(status: 'rejected', rejectionReason: 'Blurry.');

      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(900, 1000),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('No overflow on a desktop viewport and uses a 2-column layout', (
      tester,
    ) async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification(status: 'pending');

      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(1440, 1000),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('What Happens Next'), findsOneWidget);
      expect(find.text('Part of Your Profile'), findsOneWidget);
    });
  });

  testWidgets('honors reduced motion without throwing', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final repository = _FakeEducationVerificationRepository()
      ..statusResult = _verification(status: 'pending');
    await _pumpScreen(tester, repository: repository);

    expect(tester.takeException(), isNull);
    expect(find.text('Pending Review'), findsOneWidget);
  });

  testWidgets('renders correctly in Dark Mode', (tester) async {
    final repository = _FakeEducationVerificationRepository()
      ..statusResult = _verification(
        status: 'rejected',
        rejectionReason: 'Document is unreadable.',
      );

    await _pumpScreen(
      tester,
      repository: repository,
      theme: AppTheme.darkTheme,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Document is unreadable.'), findsOneWidget);
  });

  testWidgets('never uses AI-styled text on this non-AI screen', (
    tester,
  ) async {
    final repository = _FakeEducationVerificationRepository()
      ..statusResult = _verification(status: 'pending');

    await _pumpScreen(tester, repository: repository);

    expect(find.textContaining('AI'), findsNothing);
  });
}
