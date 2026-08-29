// Widget tests for AdminEducationVerificationsScreen, in isolation with a
// small GoRouter. Mirrors admin_skills_screen_test.dart's conventions.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/core/utils/document_file_open_result.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_education_verifications_repository.dart';
import 'package:opportunityhub_flutter/features/admin/presentation/admin_education_verifications_screen.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/models/admin_education_verification_model.dart';
import 'package:opportunityhub_flutter/providers/admin_education_verifications_provider.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';

/// A real, valid 1x1 transparent PNG — used wherever a test needs
/// `Image.memory` to actually decode and render, not merely receive some
/// bytes.
final Uint8List _tinyPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUB'
  'AScY42YAAAAASUVORK5CYII=',
);

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  @override
  Future<String?> getSavedToken() async => null;
}

AdminEducationVerificationModel _verification({
  int id = 1,
  String status = 'pending',
  String studentName = 'Jane Student',
  String studentEmail = 'jane@example.com',
}) {
  return AdminEducationVerificationModel(
    id: id,
    institutionName: 'State University',
    degreeOrProgram: 'BSc Computer Science',
    status: status,
    studentName: studentName,
    studentEmail: studentEmail,
    submittedAt: DateTime(2026, 7, 1),
  );
}

class _FakeAdminEducationVerificationsRepository
    extends AdminEducationVerificationsRepository {
  _FakeAdminEducationVerificationsRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<AdminEducationVerificationModel>? loadResult;
  ApiException? loadError;
  Duration loadDelay = Duration.zero;
  int getVerificationsCallCount = 0;

  ApiException? verifyError;
  final List<int> verifiedIds = [];

  ApiException? rejectError;
  final List<int> rejectedIds = [];
  final List<String> rejectReasons = [];

  EducationVerificationDocument? downloadResult;
  ApiException? downloadError;
  Duration downloadDelay = Duration.zero;
  int downloadCallCount = 0;

  @override
  Future<List<AdminEducationVerificationModel>> getVerifications() async {
    getVerificationsCallCount++;
    if (loadDelay > Duration.zero) {
      await Future<void>.delayed(loadDelay);
    }
    if (loadError != null) throw loadError!;
    return loadResult ?? [];
  }

  @override
  Future<void> verify(int verificationId) async {
    verifiedIds.add(verificationId);
    if (verifyError != null) throw verifyError!;
  }

  @override
  Future<void> reject(int verificationId, {required String reason}) async {
    rejectedIds.add(verificationId);
    rejectReasons.add(reason);
    if (rejectError != null) throw rejectError!;
  }

  @override
  Future<EducationVerificationDocument> downloadDocument(
    int verificationId,
  ) async {
    downloadCallCount++;
    if (downloadDelay > Duration.zero) {
      await Future<void>.delayed(downloadDelay);
    }
    if (downloadError != null) throw downloadError!;
    return downloadResult ??
        EducationVerificationDocument(
          bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]),
          contentType: 'application/pdf',
        );
  }
}

/// A fake platform document opener, injected in place of the real
/// `document_file_opener.dart` — see the equivalent class in
/// `admin_education_verifications_provider_test.dart` for the rationale.
class _FakeDocumentFileAction {
  _FakeDocumentFileAction();

  DocumentFileOpenResult result = const DocumentFileOpenResult(success: true);
  int callCount = 0;
  Uint8List? lastBytes;
  String? lastFileName;
  String? lastMimeType;

  Future<DocumentFileOpenResult> call(
    Uint8List bytes,
    String fileName,
    String mimeType,
  ) async {
    callCount++;
    lastBytes = bytes;
    lastFileName = fileName;
    lastMimeType = mimeType;
    return result;
  }
}

Future<AdminEducationVerificationsProvider> _pumpScreen(
  WidgetTester tester, {
  required AdminEducationVerificationsRepository repository,
  Size size = const Size(420, 1400),
  DocumentFileAction? viewDocumentFile,
  DocumentFileAction? downloadDocumentFile,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final provider = AdminEducationVerificationsProvider(
    repository: repository,
    authProvider: authProvider,
    // Defaults to a fake reporting success, standing in for the real
    // platform-resolved opener (`document_file_opener.dart`) — a widget
    // test has no real browser/device to actually open a viewer in, and
    // without a fake here the real IO implementation would hit
    // `path_provider`'s platform channel, which isn't mocked by default
    // and would throw. Tests exercising a specific view/download outcome
    // inject their own fake instead.
    viewDocumentFile: viewDocumentFile ?? _FakeDocumentFileAction().call,
    downloadDocumentFile:
        downloadDocumentFile ?? _FakeDocumentFileAction().call,
  );

  final router = GoRouter(
    initialLocation: '/admin/education-verifications',
    routes: [
      GoRoute(
        path: '/admin/education-verifications',
        builder: (_, _) => const AdminEducationVerificationsScreen(),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<AdminEducationVerificationsProvider>.value(
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

void main() {
  testWidgets('Loading state renders while verifications are in flight', (
    tester,
  ) async {
    final repository = _FakeAdminEducationVerificationsRepository()
      ..loadResult = [_verification()]
      ..loadDelay = const Duration(milliseconds: 200);

    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final provider = AdminEducationVerificationsProvider(
      repository: repository,
      authProvider: authProvider,
    );
    final router = GoRouter(
      initialLocation: '/admin/education-verifications',
      routes: [
        GoRoute(
          path: '/admin/education-verifications',
          builder: (_, _) => const AdminEducationVerificationsScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<AdminEducationVerificationsProvider>.value(
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
    expect(find.text('Jane Student'), findsNothing);

    await tester.pumpAndSettle();
  });

  testWidgets(
    'Error state with no verifications shows AppErrorView and a working retry',
    (tester) async {
      final repository = _FakeAdminEducationVerificationsRepository()
        ..loadError = ApiException('Server error, please try again later.');

      final provider = await _pumpScreen(tester, repository: repository);

      expect(
        find.text('Server error, please try again later.'),
        findsOneWidget,
      );

      repository.loadError = null;
      repository.loadResult = [_verification()];
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();

      expect(find.text('Jane Student'), findsOneWidget);
      expect(provider.verifications, hasLength(1));
    },
  );

  testWidgets('Empty state shows AppEmptyView', (tester) async {
    final repository = _FakeAdminEducationVerificationsRepository()
      ..loadResult = [];

    await _pumpScreen(tester, repository: repository);

    expect(find.text('No Submissions Yet'), findsOneWidget);
  });

  testWidgets('Lists each submission with student identity and details', (
    tester,
  ) async {
    final repository = _FakeAdminEducationVerificationsRepository()
      ..loadResult = [_verification(id: 1)];

    await _pumpScreen(tester, repository: repository);

    expect(find.text('Jane Student'), findsOneWidget);
    expect(find.text('jane@example.com'), findsOneWidget);
    expect(find.text('State University'), findsOneWidget);
    expect(find.text('BSc Computer Science'), findsOneWidget);
  });

  testWidgets('Verify and Reject actions are visible only when pending', (
    tester,
  ) async {
    final repository = _FakeAdminEducationVerificationsRepository()
      ..loadResult = [_verification(id: 1, status: 'verified')];

    await _pumpScreen(tester, repository: repository);

    expect(
      find.byKey(const Key('verify-education-verification-1')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('reject-education-verification-1')),
      findsNothing,
    );
    expect(find.text('View Document'), findsOneWidget);
  });

  group('View Document (document preview fix)', () {
    testWidgets(
      'A PDF is handed to the platform opener; no SnackBar on success '
      '(the viewer/tab is the confirmation)',
      (tester) async {
        final repository = _FakeAdminEducationVerificationsRepository()
          ..loadResult = [_verification(id: 1)]
          ..downloadResult = EducationVerificationDocument(
            bytes: Uint8List(2048),
            contentType: 'application/pdf',
          );
        final fakeView = _FakeDocumentFileAction();

        await _pumpScreen(
          tester,
          repository: repository,
          viewDocumentFile: fakeView.call,
        );

        await tester.tap(find.text('View Document'));
        await tester.pumpAndSettle();

        expect(repository.downloadCallCount, 1);
        expect(fakeView.callCount, 1);
        expect(fakeView.lastMimeType, 'application/pdf');
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets(
      'A blocked/failed platform open shows the real error, not a false '
      'success',
      (tester) async {
        final repository = _FakeAdminEducationVerificationsRepository()
          ..loadResult = [_verification(id: 1)]
          ..downloadResult = EducationVerificationDocument(
            bytes: Uint8List(2048),
            contentType: 'application/pdf',
          );
        final fakeView = _FakeDocumentFileAction()
          ..result = const DocumentFileOpenResult(
            success: false,
            errorMessage:
                "Couldn't open the document — your browser may have "
                'blocked the new tab.',
          );

        await _pumpScreen(
          tester,
          repository: repository,
          viewDocumentFile: fakeView.call,
        );

        await tester.tap(find.text('View Document'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            "Couldn't open the document — your browser may have blocked "
            'the new tab.',
          ),
          findsOneWidget,
        );
        // Stayed on the verification page -- the row is still here.
        expect(find.text('Jane Student'), findsOneWidget);
      },
    );

    testWidgets(
      'An image document opens an in-app preview with a Back action, no '
      'overflow',
      (tester) async {
        final repository = _FakeAdminEducationVerificationsRepository()
          ..loadResult = [_verification(id: 1)]
          ..downloadResult = EducationVerificationDocument(
            bytes: _tinyPngBytes,
            contentType: 'image/png',
          );

        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.text('View Document'));
        await tester.pumpAndSettle();

        expect(find.text('Document Preview'), findsOneWidget);
        expect(find.byType(InteractiveViewer), findsOneWidget);
        expect(find.byType(Image), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Back returns to the verification list, not a broken/blank page.
        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(find.text('Jane Student'), findsOneWidget);
      },
    );

    testWidgets(
      'An unsupported content-type offers an explicit Download Document '
      'fallback, not a silent/broken preview',
      (tester) async {
        final repository = _FakeAdminEducationVerificationsRepository()
          ..loadResult = [_verification(id: 1)]
          ..downloadResult = EducationVerificationDocument(
            bytes: Uint8List.fromList([1, 2, 3]),
            contentType: 'application/msword',
          );
        final fakeDownload = _FakeDocumentFileAction();

        await _pumpScreen(
          tester,
          repository: repository,
          downloadDocumentFile: fakeDownload.call,
        );

        await tester.tap(find.text('View Document'));
        await tester.pumpAndSettle();

        expect(
          find.text("This file type can't be previewed in the app."),
          findsOneWidget,
        );
        expect(find.text('Download Document'), findsOneWidget);

        await tester.tap(find.text('Download Document'));
        await tester.pumpAndSettle();

        expect(fakeDownload.callCount, 1);
        expect(find.text('Document downloaded'), findsOneWidget);
      },
    );

    testWidgets(
      'A missing document shows the backend message and keeps the Admin '
      'on this page',
      (tester) async {
        final repository = _FakeAdminEducationVerificationsRepository()
          ..loadResult = [_verification(id: 1)]
          ..downloadError = ApiException(
            'Education verification document not found',
            statusCode: 404,
          );

        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.text('View Document'));
        await tester.pumpAndSettle();

        expect(
          find.text('Education verification document not found'),
          findsOneWidget,
        );
        expect(find.text('Jane Student'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'The image preview fits and has no overflow at a narrow 320-wide '
      'viewport',
      (tester) async {
        final repository = _FakeAdminEducationVerificationsRepository()
          ..loadResult = [_verification(id: 1)]
          ..downloadResult = EducationVerificationDocument(
            bytes: _tinyPngBytes,
            contentType: 'image/png',
          );

        await _pumpScreen(
          tester,
          repository: repository,
          size: const Size(320, 700),
        );

        await tester.tap(find.text('View Document'));
        await tester.pumpAndSettle();

        expect(find.text('Document Preview'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Verify', () {
    testWidgets('Approves and removes the row, shows a SnackBar', (
      tester,
    ) async {
      final repository = _FakeAdminEducationVerificationsRepository()
        ..loadResult = [_verification(id: 1)];

      await _pumpScreen(tester, repository: repository);

      await tester.tap(
        find.byKey(const Key('verify-education-verification-1')),
      );
      await tester.pumpAndSettle();

      expect(repository.verifiedIds, [1]);
      expect(find.text('Jane Student'), findsNothing);
      expect(find.text('Education verification approved'), findsOneWidget);
    });

    testWidgets('A failure keeps the row and shows the error', (tester) async {
      final repository = _FakeAdminEducationVerificationsRepository()
        ..loadResult = [_verification(id: 1)]
        ..verifyError = ApiException(
          'This education verification has already been reviewed.',
          statusCode: 409,
        );

      await _pumpScreen(tester, repository: repository);

      await tester.tap(
        find.byKey(const Key('verify-education-verification-1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Jane Student'), findsOneWidget);
      expect(
        find.text('This education verification has already been reviewed.'),
        findsOneWidget,
      );
    });
  });

  group('Reject', () {
    testWidgets('Opens a dialog and requires a reason', (tester) async {
      final repository = _FakeAdminEducationVerificationsRepository()
        ..loadResult = [_verification(id: 1)];

      await _pumpScreen(tester, repository: repository);

      await tester.tap(
        find.byKey(const Key('reject-education-verification-1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reject Submission'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel').hitTestable());
      await tester.pumpAndSettle();

      expect(repository.rejectedIds, isEmpty);
    });

    testWidgets(
      'An empty reason shows a validation error and does not submit',
      (tester) async {
        final repository = _FakeAdminEducationVerificationsRepository()
          ..loadResult = [_verification(id: 1)];

        await _pumpScreen(tester, repository: repository);

        await tester.tap(
          find.byKey(const Key('reject-education-verification-1')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reject').last);
        await tester.pumpAndSettle();

        expect(find.text('A rejection reason is required'), findsOneWidget);
        expect(repository.rejectedIds, isEmpty);
      },
    );

    testWidgets('A valid reason rejects, removes the row, shows a SnackBar', (
      tester,
    ) async {
      final repository = _FakeAdminEducationVerificationsRepository()
        ..loadResult = [_verification(id: 1)];

      await _pumpScreen(tester, repository: repository);

      await tester.tap(
        find.byKey(const Key('reject-education-verification-1')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Document is unreadable.');
      await tester.tap(find.text('Reject').last);
      await tester.pumpAndSettle();

      expect(repository.rejectedIds, [1]);
      expect(repository.rejectReasons, ['Document is unreadable.']);
      expect(find.text('Jane Student'), findsNothing);
      expect(find.text('Education verification rejected'), findsOneWidget);
    });
  });

  testWidgets('No overflow at a narrow 320-wide viewport', (tester) async {
    final repository = _FakeAdminEducationVerificationsRepository()
      ..loadResult = [_verification()];

    await _pumpScreen(
      tester,
      repository: repository,
      size: const Size(320, 700),
    );

    expect(tester.takeException(), isNull);
  });
}
