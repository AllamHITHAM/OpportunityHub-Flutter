// Widget tests for ApplyBottomSheet, opened via showApplyBottomSheet from a
// small host screen with a GoRouter (matching how the real opportunity
// details screen opens it).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/applications/data/application_repository.dart';
import 'package:opportunityhub_flutter/features/applications/presentation/apply_bottom_sheet.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/cv/data/cv_repository.dart';
import 'package:opportunityhub_flutter/models/application_model.dart';
import 'package:opportunityhub_flutter/models/cv_model.dart';
import 'package:opportunityhub_flutter/models/opportunity_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/student_applications_provider.dart';
import 'package:opportunityhub_flutter/providers/student_cv_provider.dart';
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

CvModel _cv({int id = 1, String title = 'My CV', bool isDefault = false}) {
  return CvModel(
    id: id,
    studentId: 1,
    title: title,
    filePath: 'cvs/my-cv.pdf',
    version: 1,
    isDefault: isDefault,
    createdByAi: false,
  );
}

class _FakeCvRepository extends CvRepository {
  _FakeCvRepository({
    this.listResult = const [],
    this.listDelay = Duration.zero,
  }) : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<CvModel> listResult;
  Duration listDelay;

  @override
  Future<List<CvModel>> getStudentCvs() async {
    if (listDelay > Duration.zero) {
      await Future<void>.delayed(listDelay);
    }
    return listResult;
  }
}

ApplicationModel _application({required int opportunityId, required int cvId}) {
  return ApplicationModel(
    id: 1,
    studentId: 1,
    opportunityId: opportunityId,
    cvId: cvId,
    status: 'pending',
    opportunity: OpportunityModel(
      id: opportunityId,
      title: 'Software Engineer',
      description: 'A great opportunity.',
      opportunityType: 'job',
      employmentType: 'full_time',
      workMode: 'remote',
      experienceLevel: 'junior',
      positionsAvailable: 1,
      status: 'open',
    ),
    cv: _cv(id: cvId),
  );
}

class _FakeApplicationRepository extends ApplicationRepository {
  _FakeApplicationRepository({this.applyResult, this.applyError})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  ApplicationModel? applyResult;
  ApiException? applyError;
  int applyCallCount = 0;
  int? lastCvId;
  String? lastCoverLetter;

  @override
  Future<ApplicationModel> applyToOpportunity({
    required int opportunityId,
    required int cvId,
    String? coverLetter,
  }) async {
    applyCallCount++;
    lastCvId = cvId;
    lastCoverLetter = coverLetter;
    if (applyError != null) throw applyError!;
    return applyResult!;
  }
}

/// A minimal host screen with a button that opens the sheet exactly like
/// the real opportunity details screen does, plus a CVs-route placeholder
/// so "Manage CVs" navigation can be verified.
class _HostScreen extends StatelessWidget {
  const _HostScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            await showApplyBottomSheet(
              context,
              opportunityId: 5,
              opportunityTitle: 'Software Engineer',
            );
          },
          child: const Text('Open Sheet'),
        ),
      ),
    );
  }
}

Future<(StudentCvProvider, StudentApplicationsProvider)> _pumpHostAndOpenSheet(
  WidgetTester tester, {
  required _FakeCvRepository cvRepository,
  required _FakeApplicationRepository applicationRepository,
  Size size = const Size(420, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final cvProvider = StudentCvProvider(
    repository: cvRepository,
    authProvider: authProvider,
  );
  final applicationsProvider = StudentApplicationsProvider(
    repository: applicationRepository,
    authProvider: authProvider,
  );

  final router = GoRouter(
    initialLocation: '/host',
    routes: [
      GoRoute(path: '/host', builder: (_, _) => const _HostScreen()),
      GoRoute(
        path: AppRoutes.studentCvs,
        builder: (_, _) => const Scaffold(body: Text('CVS_PLACEHOLDER')),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<StudentCvProvider>.value(value: cvProvider),
        ChangeNotifierProvider<StudentApplicationsProvider>.value(
          value: applicationsProvider,
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Load CVs the same way the real details screen does before Apply is
  // ever tapped, unless a test wants to exercise the still-loading state.
  await cvProvider.loadCvs();
  await tester.pumpAndSettle();

  await tester.tap(find.text('Open Sheet'));
  await tester.pumpAndSettle();

  return (cvProvider, applicationsProvider);
}

void main() {
  testWidgets('Loading state renders while CVs are still being fetched', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final cvProvider = StudentCvProvider(
      repository: _FakeCvRepository(
        listResult: [_cv(id: 1, isDefault: true)],
        listDelay: const Duration(milliseconds: 200),
      ),
      authProvider: authProvider,
    );
    final applicationsProvider = StudentApplicationsProvider(
      repository: _FakeApplicationRepository(),
      authProvider: authProvider,
    );
    final router = GoRouter(
      initialLocation: '/host',
      routes: [GoRoute(path: '/host', builder: (_, _) => const _HostScreen())],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StudentCvProvider>.value(value: cvProvider),
          ChangeNotifierProvider<StudentApplicationsProvider>.value(
            value: applicationsProvider,
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Not awaited — the sheet opens while the fetch is still in flight.
    unawaited(cvProvider.loadCvs());
    await tester.tap(find.text('Open Sheet'));
    // Deliberately not pumpAndSettle — that would fast-forward straight
    // through the fake repository's 200ms delay. A couple of plain pumps
    // let the modal route build without letting the timer complete.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(cvProvider.isLoadingList, isTrue);
    expect(find.text('No CV Yet'), findsNothing);
    expect(find.text('Submit Application'), findsNothing);

    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(find.text('Submit Application'), findsOneWidget);
  });

  testWidgets('No-CV state shows a clear message and a way to manage CVs', (
    tester,
  ) async {
    await _pumpHostAndOpenSheet(
      tester,
      cvRepository: _FakeCvRepository(),
      applicationRepository: _FakeApplicationRepository(),
    );

    expect(find.text('No CV Yet'), findsOneWidget);
    expect(find.text('Submit Application'), findsNothing);

    await tester.tap(find.text('Manage CVs'));
    await tester.pumpAndSettle();

    expect(find.text('CVS_PLACEHOLDER'), findsOneWidget);
  });

  testWidgets('CV selection is offered and the default CV is pre-selected', (
    tester,
  ) async {
    await _pumpHostAndOpenSheet(
      tester,
      cvRepository: _FakeCvRepository(
        listResult: [
          _cv(id: 1, title: 'CV One'),
          _cv(id: 2, title: 'CV Two (Default)', isDefault: true),
        ],
      ),
      applicationRepository: _FakeApplicationRepository(),
    );

    expect(find.text('CV One'), findsOneWidget);
    expect(find.text('CV Two (Default)'), findsOneWidget);

    final radioGroup = tester.widget<RadioGroup<int>>(
      find.byType(RadioGroup<int>),
    );
    expect(radioGroup.groupValue, 2);
  });

  testWidgets('Cover letter is optional — submission succeeds without one', (
    tester,
  ) async {
    final applicationRepository = _FakeApplicationRepository(
      applyResult: _application(opportunityId: 5, cvId: 1),
    );
    await _pumpHostAndOpenSheet(
      tester,
      cvRepository: _FakeCvRepository(
        listResult: [_cv(id: 1, isDefault: true)],
      ),
      applicationRepository: applicationRepository,
    );

    await tester.tap(find.text('Submit Application'));
    await tester.pumpAndSettle();

    expect(applicationRepository.applyCallCount, 1);
    expect(applicationRepository.lastCoverLetter, isNull);
  });

  testWidgets('A provided cover letter is sent trimmed', (tester) async {
    final applicationRepository = _FakeApplicationRepository(
      applyResult: _application(opportunityId: 5, cvId: 1),
    );
    await _pumpHostAndOpenSheet(
      tester,
      cvRepository: _FakeCvRepository(
        listResult: [_cv(id: 1, isDefault: true)],
      ),
      applicationRepository: applicationRepository,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Cover Letter (optional)'),
      '  I would love to join.  ',
    );
    await tester.tap(find.text('Submit Application'));
    await tester.pumpAndSettle();

    expect(applicationRepository.lastCoverLetter, 'I would love to join.');
  });

  testWidgets('Submit is disabled while no CV is selected', (tester) async {
    // Two CVs, neither default — nothing gets pre-selected.
    await _pumpHostAndOpenSheet(
      tester,
      cvRepository: _FakeCvRepository(listResult: [_cv(id: 1), _cv(id: 2)]),
      applicationRepository: _FakeApplicationRepository(),
    );

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Submit Application'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('Successful submission closes the sheet', (tester) async {
    final applicationRepository = _FakeApplicationRepository(
      applyResult: _application(opportunityId: 5, cvId: 1),
    );
    await _pumpHostAndOpenSheet(
      tester,
      cvRepository: _FakeCvRepository(
        listResult: [_cv(id: 1, isDefault: true)],
      ),
      applicationRepository: applicationRepository,
    );

    await tester.tap(find.text('Submit Application'));
    await tester.pumpAndSettle();

    expect(find.text('Submit Application'), findsNothing);
    expect(find.text('Open Sheet'), findsOneWidget);
  });

  testWidgets('422 validation error is shown without closing the sheet', (
    tester,
  ) async {
    final applicationRepository = _FakeApplicationRepository(
      applyError: ApiException(
        'The given data was invalid.',
        statusCode: 422,
        errors: {
          'cv_id': ['The selected cv id is invalid.'],
        },
      ),
    );
    await _pumpHostAndOpenSheet(
      tester,
      cvRepository: _FakeCvRepository(
        listResult: [_cv(id: 1, isDefault: true)],
      ),
      applicationRepository: applicationRepository,
    );

    await tester.tap(find.text('Submit Application'));
    await tester.pumpAndSettle();

    expect(find.text('The selected cv id is invalid.'), findsOneWidget);
    expect(find.text('Submit Application'), findsOneWidget);
  });

  testWidgets('409 duplicate-application error is shown clearly', (
    tester,
  ) async {
    final applicationRepository = _FakeApplicationRepository(
      applyError: ApiException(
        'You have already applied to this opportunity',
        statusCode: 409,
      ),
    );
    await _pumpHostAndOpenSheet(
      tester,
      cvRepository: _FakeCvRepository(
        listResult: [_cv(id: 1, isDefault: true)],
      ),
      applicationRepository: applicationRepository,
    );

    await tester.tap(find.text('Submit Application'));
    await tester.pumpAndSettle();

    expect(
      find.text('You have already applied to this opportunity'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
