// Router-level tests for organization application-management routes:
// role/profile gating, direct-URL safety, and no redirect loops.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_dashboard_repository.dart';
import 'package:opportunityhub_flutter/features/applications/data/application_repository.dart';
import 'package:opportunityhub_flutter/features/assessments/data/assessment_repository.dart';
import 'package:opportunityhub_flutter/features/assessments/data/interview_create_input.dart';
import 'package:opportunityhub_flutter/features/assessments/data/quiz_create_input.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/offers/data/offer_repository.dart';
import 'package:opportunityhub_flutter/features/organization/data/organization_profile_repository.dart';
import 'package:opportunityhub_flutter/features/student/data/student_profile_repository.dart';
import 'package:opportunityhub_flutter/models/admin_dashboard_stats_model.dart';
import 'package:opportunityhub_flutter/models/application_model.dart';
import 'package:opportunityhub_flutter/models/assessment_model.dart';
import 'package:opportunityhub_flutter/models/offer_model.dart';
import 'package:opportunityhub_flutter/models/organization_profile_model.dart';
import 'package:opportunityhub_flutter/models/quiz_model.dart';
import 'package:opportunityhub_flutter/models/student_profile_model.dart';
import 'package:opportunityhub_flutter/models/user_model.dart';
import 'package:opportunityhub_flutter/providers/admin_dashboard_provider.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_applications_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_assessment_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_offer_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_profile_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_quiz_provider.dart';
import 'package:opportunityhub_flutter/providers/student_profile_provider.dart';
import 'package:opportunityhub_flutter/routes/app_router.dart';
import 'package:opportunityhub_flutter/routes/app_routes.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({this.savedToken, this.currentUser})
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  String? savedToken;
  UserModel? currentUser;

  @override
  Future<String?> getSavedToken() async => savedToken;

  @override
  Future<UserModel> getCurrentUser() async => currentUser!;
}

class _FakeStudentProfileRepository extends StudentProfileRepository {
  _FakeStudentProfileRepository({this.getProfileResult})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  StudentProfileModel? getProfileResult;

  @override
  Future<StudentProfileModel?> getProfile() async => getProfileResult;
}

class _FakeOrganizationProfileRepository extends OrganizationProfileRepository {
  _FakeOrganizationProfileRepository({this.getProfileResult})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  OrganizationProfileModel? getProfileResult;

  @override
  Future<OrganizationProfileModel?> getProfile() async => getProfileResult;
}

class _FakeApplicationRepository extends ApplicationRepository {
  _FakeApplicationRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<List<ApplicationModel>> getApplicationsForOpportunity(
    int opportunityId,
  ) async => [];

  @override
  Future<ApplicationModel> getOrganizationApplication(int applicationId) async {
    throw ApiException('Application not found', statusCode: 404);
  }
}

class _FakeAssessmentRepository extends AssessmentRepository {
  _FakeAssessmentRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<AssessmentModel?> getAssessmentForApplication(
    int applicationId,
  ) async {
    return null;
  }

  @override
  Future<AssessmentModel> createAssessment({
    required int applicationId,
    required String type,
    InterviewCreateInput? interviewInput,
    QuizCreateInput? quizInput,
  }) async {
    throw ApiException('Not used in router tests');
  }

  @override
  Future<QuizModel?> getOrganizationQuiz(int assessmentId) async {
    return null;
  }
}

class _FakeOfferRepository extends OfferRepository {
  _FakeOfferRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<OfferModel> getOrganizationOffer(int applicationId) async {
    throw ApiException('This application has no offer yet', statusCode: 404);
  }
}

class _FakeAdminDashboardRepository extends AdminDashboardRepository {
  _FakeAdminDashboardRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  @override
  Future<AdminDashboardStatsModel> getDashboardStats() async {
    throw ApiException('Not used in these router tests');
  }
}

void _setViewSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pumps the full app, authenticated as [role] with a saved token
/// (simulating a returning user), and navigates straight to [initialPath].
Future<void> _pumpAsRole(
  WidgetTester tester, {
  required String role,
  required String initialPath,
  OrganizationProfileModel? organizationProfile,
}) async {
  _setViewSize(tester, const Size(420, 1400));

  final authProvider = AuthProvider(
    authRepository: _FakeAuthRepository(
      savedToken: 'saved-token',
      currentUser: UserModel(
        id: 1,
        name: 'Test User',
        email: 'test@example.com',
        role: role,
        status: 'active',
      ),
    ),
  );
  final studentProfileProvider = StudentProfileProvider(
    repository: _FakeStudentProfileRepository(
      getProfileResult: role == 'student'
          ? const StudentProfileModel(
              id: 1,
              university: 'State University',
              major: 'Computer Science',
              graduationYear: 2027,
            )
          : null,
    ),
    authProvider: authProvider,
  );
  final organizationProfileProvider = OrganizationProfileProvider(
    repository: _FakeOrganizationProfileRepository(
      getProfileResult: organizationProfile,
    ),
    authProvider: authProvider,
  );
  final applicationsProvider = OrganizationApplicationsProvider(
    repository: _FakeApplicationRepository(),
    authProvider: authProvider,
  );
  final assessmentProvider = OrganizationAssessmentProvider(
    repository: _FakeAssessmentRepository(),
    authProvider: authProvider,
  );
  final quizProvider = OrganizationQuizProvider(
    repository: _FakeAssessmentRepository(),
    authProvider: authProvider,
  );
  final offerProvider = OrganizationOfferProvider(
    repository: _FakeOfferRepository(),
    authProvider: authProvider,
  );
  // Not exercised by any test in this file, but registered because a
  // role='admin' request for a non-admin route (see the "Admins cannot
  // access..." tests below) redirects to AdminHomeScreen, which now
  // requires this provider to exist in the tree.
  final adminDashboardProvider = AdminDashboardProvider(
    repository: _FakeAdminDashboardRepository(),
    authProvider: authProvider,
  );
  final appRouter = AppRouter(
    authProvider,
    studentProfileProvider,
    organizationProfileProvider,
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<StudentProfileProvider>.value(
          value: studentProfileProvider,
        ),
        ChangeNotifierProvider<OrganizationProfileProvider>.value(
          value: organizationProfileProvider,
        ),
        ChangeNotifierProvider<OrganizationApplicationsProvider>.value(
          value: applicationsProvider,
        ),
        ChangeNotifierProvider<OrganizationAssessmentProvider>.value(
          value: assessmentProvider,
        ),
        ChangeNotifierProvider<OrganizationQuizProvider>.value(
          value: quizProvider,
        ),
        ChangeNotifierProvider<OrganizationOfferProvider>.value(
          value: offerProvider,
        ),
        ChangeNotifierProvider<AdminDashboardProvider>.value(
          value: adminDashboardProvider,
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: appRouter.router,
      ),
    ),
  );

  appRouter.router.go(initialPath);
  await authProvider.initialize();
  await tester.pumpAndSettle();
}

const _approvedProfile = OrganizationProfileModel(
  id: 1,
  organizationName: 'Acme Corp',
  organizationType: 'company',
  approvalStatus: 'approved',
);

void main() {
  testWidgets('Unauthenticated users are redirected to login', (tester) async {
    _setViewSize(tester, const Size(420, 1400));

    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final studentProfileProvider = StudentProfileProvider(
      repository: _FakeStudentProfileRepository(),
      authProvider: authProvider,
    );
    final organizationProfileProvider = OrganizationProfileProvider(
      repository: _FakeOrganizationProfileRepository(),
      authProvider: authProvider,
    );
    final applicationsProvider = OrganizationApplicationsProvider(
      repository: _FakeApplicationRepository(),
      authProvider: authProvider,
    );
    final appRouter = AppRouter(
      authProvider,
      studentProfileProvider,
      organizationProfileProvider,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<StudentProfileProvider>.value(
            value: studentProfileProvider,
          ),
          ChangeNotifierProvider<OrganizationProfileProvider>.value(
            value: organizationProfileProvider,
          ),
          ChangeNotifierProvider<OrganizationApplicationsProvider>.value(
            value: applicationsProvider,
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: appRouter.router,
        ),
      ),
    );

    appRouter.router.go(AppRoutes.organizationApplicants(5));
    await authProvider.initialize();
    await tester.pumpAndSettle();

    expect(find.text('Applicants'), findsNothing);
    expect(find.text('Login'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Unauthenticated users are redirected to login from the Schedule Interview route',
    (tester) async {
      _setViewSize(tester, const Size(420, 1400));

      final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
      final studentProfileProvider = StudentProfileProvider(
        repository: _FakeStudentProfileRepository(),
        authProvider: authProvider,
      );
      final organizationProfileProvider = OrganizationProfileProvider(
        repository: _FakeOrganizationProfileRepository(),
        authProvider: authProvider,
      );
      final applicationsProvider = OrganizationApplicationsProvider(
        repository: _FakeApplicationRepository(),
        authProvider: authProvider,
      );
      final assessmentProvider = OrganizationAssessmentProvider(
        repository: _FakeAssessmentRepository(),
        authProvider: authProvider,
      );
      final appRouter = AppRouter(
        authProvider,
        studentProfileProvider,
        organizationProfileProvider,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<StudentProfileProvider>.value(
              value: studentProfileProvider,
            ),
            ChangeNotifierProvider<OrganizationProfileProvider>.value(
              value: organizationProfileProvider,
            ),
            ChangeNotifierProvider<OrganizationApplicationsProvider>.value(
              value: applicationsProvider,
            ),
            ChangeNotifierProvider<OrganizationAssessmentProvider>.value(
              value: assessmentProvider,
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: appRouter.router,
          ),
        ),
      );

      appRouter.router.go(AppRoutes.organizationScheduleInterview(1));
      await authProvider.initialize();
      await tester.pumpAndSettle();

      expect(find.text('Schedule Interview'), findsNothing);
      expect(find.text('Login'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('An approved organization can open the applicants route', (
    tester,
  ) async {
    await _pumpAsRole(
      tester,
      role: 'organization',
      initialPath: AppRoutes.organizationApplicants(5),
      organizationProfile: _approvedProfile,
    );

    expect(find.text('No Applicants Yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'An approved organization can open the application details route',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'organization',
        initialPath: AppRoutes.organizationApplicationDetails(123),
        organizationProfile: _approvedProfile,
      );

      // A nonexistent ID surfaces the documented not-found error safely,
      // rather than crashing — proving the route never depended on extra.
      expect(find.text('Application not found'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Students cannot access organization applicant routes', (
    tester,
  ) async {
    await _pumpAsRole(
      tester,
      role: 'student',
      initialPath: AppRoutes.organizationApplicants(5),
    );

    expect(find.text('No Applicants Yet'), findsNothing);
    expect(find.text('Role: Student'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Students cannot access organization application details routes',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'student',
        initialPath: AppRoutes.organizationApplicationDetails(1),
      );

      expect(find.text('Application not found'), findsNothing);
      expect(find.text('Role: Student'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Admins cannot access organization applicant routes', (
    tester,
  ) async {
    await _pumpAsRole(
      tester,
      role: 'admin',
      initialPath: AppRoutes.organizationApplicants(5),
    );

    expect(find.text('No Applicants Yet'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Admins cannot access organization application details routes', (
    tester,
  ) async {
    await _pumpAsRole(
      tester,
      role: 'admin',
      initialPath: AppRoutes.organizationApplicationDetails(1),
    );

    expect(find.text('Application not found'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'An organization with an incomplete profile remains routed to onboarding',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'organization',
        initialPath: AppRoutes.organizationApplicants(5),
        organizationProfile: null,
      );

      expect(find.text('No Applicants Yet'), findsNothing);
      expect(find.text('Company Profile Setup Incomplete'), findsOneWidget);
    },
  );

  testWidgets(
    'A malformed application ID does not crash — falls back to a safe not-found state',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'organization',
        initialPath: '${AppRoutes.organizationApplications}/not-a-number',
        organizationProfile: _approvedProfile,
      );

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('No redirect loop occurs for the applicants route', (
    tester,
  ) async {
    await _pumpAsRole(
      tester,
      role: 'organization',
      initialPath: AppRoutes.organizationApplicants(5),
      organizationProfile: _approvedProfile,
    );

    // Settling completed without a pumpAndSettle timeout (which throws if
    // frames never stop scheduling, e.g. from a redirect loop).
    expect(find.text('No Applicants Yet'), findsOneWidget);
  });

  testWidgets(
    'An approved organization can open the Schedule Interview route directly by URL',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'organization',
        initialPath: AppRoutes.organizationScheduleInterview(123),
        organizationProfile: _approvedProfile,
      );

      expect(find.text('Schedule Interview'), findsWidgets);
      expect(find.text('Interview Type'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Students cannot access the Schedule Interview route', (
    tester,
  ) async {
    await _pumpAsRole(
      tester,
      role: 'student',
      initialPath: AppRoutes.organizationScheduleInterview(1),
    );

    expect(find.text('Schedule Interview'), findsNothing);
    expect(find.text('Role: Student'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Admins cannot access the Schedule Interview route', (
    tester,
  ) async {
    await _pumpAsRole(
      tester,
      role: 'admin',
      initialPath: AppRoutes.organizationScheduleInterview(1),
    );

    expect(find.text('Schedule Interview'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'An organization with an incomplete profile is not routed to Schedule Interview',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'organization',
        initialPath: AppRoutes.organizationScheduleInterview(1),
        organizationProfile: null,
      );

      expect(find.text('Schedule Interview'), findsNothing);
      expect(find.text('Company Profile Setup Incomplete'), findsOneWidget);
    },
  );

  testWidgets(
    'A malformed application ID on the Schedule Interview route does not crash',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'organization',
        initialPath:
            '${AppRoutes.organizationApplications}/not-a-number/assessment/interview',
        organizationProfile: _approvedProfile,
      );

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'An approved organization can open the Create Quiz route directly by URL',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'organization',
        initialPath: AppRoutes.organizationCreateQuiz(123),
        organizationProfile: _approvedProfile,
      );

      expect(find.text('Create Quiz'), findsWidgets);
      expect(find.text('Passing Score (%)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Students cannot access the Create Quiz route', (tester) async {
    await _pumpAsRole(
      tester,
      role: 'student',
      initialPath: AppRoutes.organizationCreateQuiz(1),
    );

    expect(find.text('Create Quiz'), findsNothing);
    expect(find.text('Role: Student'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Admins cannot access the Create Quiz route', (tester) async {
    await _pumpAsRole(
      tester,
      role: 'admin',
      initialPath: AppRoutes.organizationCreateQuiz(1),
    );

    expect(find.text('Create Quiz'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'An organization with an incomplete profile is not routed to Create Quiz',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'organization',
        initialPath: AppRoutes.organizationCreateQuiz(1),
        organizationProfile: null,
      );

      expect(find.text('Create Quiz'), findsNothing);
      expect(find.text('Company Profile Setup Incomplete'), findsOneWidget);
    },
  );

  testWidgets(
    'A malformed application ID on the Create Quiz route does not crash',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'organization',
        initialPath:
            '${AppRoutes.organizationApplications}/not-a-number/assessment/quiz',
        organizationProfile: _approvedProfile,
      );

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'An approved organization can open the Quiz editor route directly by URL',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'organization',
        initialPath: AppRoutes.organizationQuizEditor(1),
        organizationProfile: _approvedProfile,
      );

      // No quiz found for assessment 1 in this test's fake repository --
      // the screen's own safe "not found" state proves the route resolved
      // without depending on `extra`, the same pattern the Application
      // Details route tests already use for a nonexistent ID.
      expect(find.text('No Quiz Found'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Students cannot access the Quiz editor route', (tester) async {
    await _pumpAsRole(
      tester,
      role: 'student',
      initialPath: AppRoutes.organizationQuizEditor(1),
    );

    expect(find.text('No Quiz Found'), findsNothing);
    expect(find.text('Role: Student'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Admins cannot access the Quiz editor route', (tester) async {
    await _pumpAsRole(
      tester,
      role: 'admin',
      initialPath: AppRoutes.organizationQuizEditor(1),
    );

    expect(find.text('No Quiz Found'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'An organization with an incomplete profile is not routed to the Quiz editor',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'organization',
        initialPath: AppRoutes.organizationQuizEditor(1),
        organizationProfile: null,
      );

      expect(find.text('No Quiz Found'), findsNothing);
      expect(find.text('Company Profile Setup Incomplete'), findsOneWidget);
    },
  );

  testWidgets(
    'A malformed assessment ID on the Quiz editor route does not crash',
    (tester) async {
      await _pumpAsRole(
        tester,
        role: 'organization',
        initialPath: '${AppRoutes.organizationAssessments}/not-a-number/quiz',
        organizationProfile: _approvedProfile,
      );

      expect(tester.takeException(), isNull);
    },
  );
}
