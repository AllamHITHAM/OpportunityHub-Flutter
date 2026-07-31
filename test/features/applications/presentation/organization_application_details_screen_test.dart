// Widget tests for OrganizationApplicationDetailsScreen, in isolation with
// a small GoRouter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/applications/data/application_repository.dart';
import 'package:opportunityhub_flutter/features/applications/presentation/organization_application_details_screen.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/models/applicant_summary_model.dart';
import 'package:opportunityhub_flutter/models/application_model.dart';
import 'package:opportunityhub_flutter/models/cv_model.dart';
import 'package:opportunityhub_flutter/models/opportunity_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_applications_provider.dart';
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

const _cv = CvModel(
  id: 2,
  studentId: 1,
  title: 'Main CV',
  filePath: 'uploads/cv.pdf',
  version: 1,
  isDefault: true,
  createdByAi: true,
);

const _applicant = ApplicantSummaryModel(
  id: 1,
  userId: 10,
  name: 'Jane Student',
  email: 'jane@example.com',
  phone: '0599111111',
  university: 'State University',
  major: 'Computer Science',
  graduationYear: 2027,
  bio: 'Backend developer.',
);

OpportunityModel _opportunity() {
  return const OpportunityModel(
    id: 5,
    title: 'Backend Developer',
    description: 'Great role.',
    opportunityType: 'job',
    employmentType: 'full_time',
    workMode: 'remote',
    experienceLevel: 'junior',
    positionsAvailable: 1,
    status: 'open',
  );
}

ApplicationModel _application({
  int id = 1,
  String status = 'pending',
  String? coverLetter,
  ApplicantSummaryModel? applicant = _applicant,
}) {
  return ApplicationModel(
    id: id,
    studentId: 1,
    opportunityId: 5,
    cvId: 2,
    status: status,
    cv: _cv,
    opportunity: _opportunity(),
    applicant: applicant,
    coverLetter: coverLetter,
    appliedAt: DateTime(2026, 7, 20),
  );
}

class _FakeApplicationRepository extends ApplicationRepository {
  _FakeApplicationRepository({
    this.detailsResult,
    this.detailsError,
    this.detailsDelay = Duration.zero,
  }) : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  ApplicationModel? detailsResult;
  ApiException? detailsError;
  Duration detailsDelay;

  ApplicationModel? statusUpdateResult;
  ApiException? statusUpdateError;
  Duration statusUpdateDelay = Duration.zero;
  int updateStatusCallCount = 0;
  String? lastStatus;

  @override
  Future<ApplicationModel> getOrganizationApplication(int applicationId) async {
    if (detailsDelay > Duration.zero) {
      await Future<void>.delayed(detailsDelay);
    }
    if (detailsError != null) throw detailsError!;
    return detailsResult!;
  }

  @override
  Future<ApplicationModel> updateOrganizationApplicationStatus({
    required int applicationId,
    required String status,
  }) async {
    updateStatusCallCount++;
    lastStatus = status;
    if (statusUpdateDelay > Duration.zero) {
      await Future<void>.delayed(statusUpdateDelay);
    }
    if (statusUpdateError != null) throw statusUpdateError!;
    return statusUpdateResult!;
  }
}

Future<OrganizationApplicationsProvider> _pumpDetails(
  WidgetTester tester, {
  required _FakeApplicationRepository repository,
  int applicationId = 1,
  Size size = const Size(420, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final provider = OrganizationApplicationsProvider(
    repository: repository,
    authProvider: authProvider,
  );

  final router = GoRouter(
    initialLocation: AppRoutes.organizationApplicationDetails(applicationId),
    routes: [
      GoRoute(
        path: '${AppRoutes.organizationApplications}/:id',
        builder: (_, state) => OrganizationApplicationDetailsScreen(
          applicationId: int.parse(state.pathParameters['id']!),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ChangeNotifierProvider<OrganizationApplicationsProvider>.value(
      value: provider,
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
  testWidgets('Loading state renders while details are in flight', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(),
      detailsDelay: const Duration(milliseconds: 200),
    );
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final provider = OrganizationApplicationsProvider(
      repository: repository,
      authProvider: authProvider,
    );
    final router = GoRouter(
      initialLocation: AppRoutes.organizationApplicationDetails(1),
      routes: [
        GoRoute(
          path: '${AppRoutes.organizationApplications}/:id',
          builder: (_, state) => OrganizationApplicationDetailsScreen(
            applicationId: int.parse(state.pathParameters['id']!),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<OrganizationApplicationsProvider>.value(
        value: provider,
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(provider.isLoadingDetails, isTrue);

    await tester.pumpAndSettle();
  });

  testWidgets('Error state renders safely, no crash', (tester) async {
    final repository = _FakeApplicationRepository(
      detailsError: ApiException('Application not found'),
    );
    await _pumpDetails(tester, repository: repository, applicationId: 999);

    expect(find.text('Application not found'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Applicant details render', (tester) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Jane Student'), findsOneWidget);
    expect(find.text('jane@example.com'), findsOneWidget);
    expect(find.text('0599111111'), findsOneWidget);
    expect(find.text('State University'), findsOneWidget);
    expect(find.text('Computer Science'), findsOneWidget);
    expect(find.text('2027'), findsOneWidget);
    expect(find.text('Backend developer.'), findsOneWidget);
  });

  testWidgets('Empty-string applicant name falls back to "Unnamed applicant"', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(
        applicant: const ApplicantSummaryModel(id: 1, name: ''),
      ),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Unnamed applicant'), findsOneWidget);
    expect(find.text(''), findsNothing);
  });

  testWidgets(
    'Whitespace-only applicant name falls back to "Unnamed applicant"',
    (tester) async {
      final repository = _FakeApplicationRepository(
        detailsResult: _application(
          applicant: const ApplicantSummaryModel(id: 1, name: '   '),
        ),
      );
      await _pumpDetails(tester, repository: repository);

      expect(find.text('Unnamed applicant'), findsOneWidget);
      expect(find.text('   '), findsNothing);
    },
  );

  testWidgets(
    'Empty/whitespace email, university, and major show "Not specified"',
    (tester) async {
      final repository = _FakeApplicationRepository(
        detailsResult: _application(
          applicant: const ApplicantSummaryModel(
            id: 1,
            name: 'Jane Student',
            email: '',
            phone: '0599111111',
            university: '   ',
            major: '',
            graduationYear: 2027,
          ),
        ),
      );
      await _pumpDetails(tester, repository: repository);

      expect(find.text('Not specified'), findsNWidgets(3));
      expect(find.text(''), findsNothing);
      expect(find.text('   '), findsNothing);
    },
  );

  testWidgets('Whitespace-only bio does not render a bio row', (tester) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(
        applicant: const ApplicantSummaryModel(
          id: 1,
          name: 'Jane Student',
          bio: '   ',
        ),
      ),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('   '), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cover letter renders when present', (tester) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(coverLetter: 'I would love to join.'),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Cover Letter'), findsOneWidget);
    expect(find.text('I would love to join.'), findsOneWidget);
  });

  testWidgets('No Cover Letter section renders when absent', (tester) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(coverLetter: null),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Cover Letter'), findsNothing);
  });

  testWidgets('CV details render', (tester) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Main CV'), findsOneWidget);
    expect(find.text('uploads/cv.pdf'), findsOneWidget);
    expect(find.text('Version 1'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('AI Generated'), findsOneWidget);
  });

  testWidgets('Opportunity details render', (tester) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Backend Developer'), findsOneWidget);
    expect(find.text('Job'), findsOneWidget);
  });

  testWidgets('Pending status shows Mark Reviewed, Shortlist, and Reject', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'pending'),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Mark Reviewed'), findsOneWidget);
    expect(find.text('Shortlist'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
  });

  testWidgets('Reviewed status shows only Shortlist and Reject', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'reviewed'),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Mark Reviewed'), findsNothing);
    expect(find.text('Shortlist'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
  });

  testWidgets('Shortlisted status shows only Reject', (tester) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'shortlisted'),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Mark Reviewed'), findsNothing);
    expect(find.text('Shortlist'), findsNothing);
    expect(find.text('Reject'), findsOneWidget);
  });

  testWidgets('Rejected status shows no action buttons', (tester) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'rejected'),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Mark Reviewed'), findsNothing);
    expect(find.text('Shortlist'), findsNothing);
    expect(find.text('Reject'), findsNothing);
    expect(find.text('Rejected'), findsOneWidget);
  });

  testWidgets('Withdrawn status shows no action buttons', (tester) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'withdrawn'),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Mark Reviewed'), findsNothing);
    expect(find.text('Shortlist'), findsNothing);
    expect(find.text('Reject'), findsNothing);
  });

  testWidgets('interview_scheduled status is read-only — no Phase 3D actions', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'interview_scheduled'),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Mark Reviewed'), findsNothing);
    expect(find.text('Shortlist'), findsNothing);
    expect(find.text('Reject'), findsNothing);
  });

  testWidgets('accepted status is read-only — no Phase 3D actions', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'accepted'),
    );
    await _pumpDetails(tester, repository: repository);

    expect(find.text('Mark Reviewed'), findsNothing);
    expect(find.text('Shortlist'), findsNothing);
    expect(find.text('Reject'), findsNothing);
  });

  testWidgets(
    'Mark Reviewed succeeds and the status updates immediately without restart',
    (tester) async {
      final repository = _FakeApplicationRepository(
        detailsResult: _application(status: 'pending'),
      );
      repository.statusUpdateResult = _application(status: 'reviewed');
      await _pumpDetails(tester, repository: repository);

      await tester.tap(find.text('Mark Reviewed'));
      await tester.pumpAndSettle();

      expect(repository.lastStatus, 'reviewed');
      expect(find.text('Reviewed'), findsOneWidget);
      // The action set has updated to match the new status in the same
      // screen instance — no restart or remount required.
      expect(find.text('Mark Reviewed'), findsNothing);
      expect(find.text('Shortlist'), findsOneWidget);
    },
  );

  testWidgets(
    'Shortlist succeeds and the status updates immediately without restart',
    (tester) async {
      final repository = _FakeApplicationRepository(
        detailsResult: _application(status: 'reviewed'),
      );
      repository.statusUpdateResult = _application(status: 'shortlisted');
      await _pumpDetails(tester, repository: repository);

      await tester.tap(find.text('Shortlist'));
      await tester.pumpAndSettle();

      expect(repository.lastStatus, 'shortlisted');
      expect(find.text('Shortlisted'), findsOneWidget);
      expect(find.text('Shortlist'), findsNothing);
    },
  );

  testWidgets('Reject shows a confirmation dialog before anything happens', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'pending'),
    );
    await _pumpDetails(tester, repository: repository);

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();

    expect(find.text('Reject Application'), findsOneWidget);
    expect(find.text('Reject this application?'), findsOneWidget);
    expect(repository.updateStatusCallCount, 0);
  });

  testWidgets('Reject cancellation performs no status change', (tester) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'pending'),
    );
    await _pumpDetails(tester, repository: repository);

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repository.updateStatusCallCount, 0);
    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('Reject success updates the status immediately without restart', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'pending'),
    );
    repository.statusUpdateResult = _application(status: 'rejected');
    await _pumpDetails(tester, repository: repository);

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reject').last);
    await tester.pumpAndSettle();

    expect(repository.updateStatusCallCount, 1);
    expect(repository.lastStatus, 'rejected');
    expect(find.text('Rejected'), findsOneWidget);
  });

  testWidgets('Action failure shows the backend error and keeps the status', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'pending'),
    );
    repository.statusUpdateError = ApiException(
      'Cannot change the status of a withdrawn application',
      statusCode: 409,
    );
    await _pumpDetails(tester, repository: repository);

    await tester.tap(find.text('Mark Reviewed'));
    await tester.pumpAndSettle();

    expect(
      find.text('Cannot change the status of a withdrawn application'),
      findsOneWidget,
    );
    expect(find.text('Pending'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Buttons are disabled while an update is in flight', (
    tester,
  ) async {
    final repository = _FakeApplicationRepository(
      detailsResult: _application(status: 'pending'),
    );
    repository.statusUpdateResult = _application(status: 'reviewed');
    repository.statusUpdateDelay = const Duration(milliseconds: 200);
    await _pumpDetails(tester, repository: repository);

    await tester.tap(find.text('Mark Reviewed'));
    await tester.pump();

    final shortlistButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Shortlist'),
    );
    expect(shortlistButton.onPressed, isNull);

    await tester.pumpAndSettle();
  });
}
