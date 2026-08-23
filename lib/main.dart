import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';

import 'core/api/api_client.dart';
import 'core/storage/token_storage_service.dart';
import 'core/theme/app_theme.dart';
import 'features/admin/data/admin_dashboard_repository.dart';
import 'features/admin/data/admin_education_verifications_repository.dart';
import 'features/admin/data/admin_organizations_repository.dart';
import 'features/admin/data/admin_skill_suggestions_repository.dart';
import 'features/admin/data/admin_skills_repository.dart';
import 'features/admin/data/admin_users_repository.dart';
import 'features/applications/data/application_repository.dart';
import 'features/assessments/data/assessment_repository.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/candidates/data/candidate_repository.dart';
import 'features/cv/data/cv_repository.dart';
import 'features/education_verification/data/education_verification_repository.dart';
import 'features/invitations/data/invitation_repository.dart';
import 'features/notifications/data/notification_repository.dart';
import 'features/offers/data/offer_repository.dart';
import 'features/opportunities/data/opportunity_repository.dart';
import 'features/organization/data/organization_profile_repository.dart';
import 'features/skills/data/student_skill_repository.dart';
import 'features/student/data/student_profile_repository.dart';
import 'providers/admin_dashboard_provider.dart';
import 'providers/admin_education_verifications_provider.dart';
import 'providers/admin_organizations_provider.dart';
import 'providers/admin_skill_suggestions_provider.dart';
import 'providers/admin_skills_provider.dart';
import 'providers/admin_users_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/candidate_search_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/organization_applications_provider.dart';
import 'providers/organization_assessment_provider.dart';
import 'providers/organization_match_analysis_provider.dart';
import 'providers/organization_offer_provider.dart';
import 'providers/organization_opportunities_provider.dart';
import 'providers/organization_profile_provider.dart';
import 'providers/organization_quiz_provider.dart';
import 'providers/student_applications_provider.dart';
import 'providers/student_assessment_provider.dart';
import 'providers/student_cv_provider.dart';
import 'providers/student_education_verification_provider.dart';
import 'providers/student_invitations_provider.dart';
import 'providers/student_offer_provider.dart';
import 'providers/student_opportunities_provider.dart';
import 'providers/student_profile_provider.dart';
import 'providers/student_skill_provider.dart';
import 'providers/student_quiz_provider.dart';
import 'providers/theme_provider.dart';
import 'routes/app_router.dart';

void main() async {
  // Without this, Flutter Web defaults to hash-based URLs (e.g.
  // `#/reset-password?...`). A plain path link -- like the one the
  // password-reset email sends (`/reset-password?token=...&email=...`) --
  // opened directly (not via in-app navigation) would never reach
  // GoRouter as the requested location at all: the app would boot at `/`
  // and lose the token/email query entirely before any router redirect
  // logic ever runs. `usePathUrlStrategy()` is a no-op on non-web
  // platforms.
  usePathUrlStrategy();

  // Awaited before the very first frame (UI Phase 1.3) so the correct
  // light/dark theme is already known when the app first paints -- never
  // a flash from one theme to another.
  WidgetsFlutterBinding.ensureInitialized();
  final themeProvider = ThemeProvider();
  await themeProvider.initialize();

  runApp(MyApp(themeProvider: themeProvider));
}

class MyApp extends StatelessWidget {
  const MyApp({required this.themeProvider, super.key});

  final ThemeProvider themeProvider;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        Provider<TokenStorageService>(create: (_) => TokenStorageService()),
        ProxyProvider<TokenStorageService, ApiClient>(
          update: (_, tokenStorageService, _) =>
              ApiClient(tokenStorageService: tokenStorageService),
        ),
        ProxyProvider2<ApiClient, TokenStorageService, AuthRepository>(
          update: (_, apiClient, tokenStorageService, _) => AuthRepository(
            apiClient: apiClient,
            tokenStorageService: tokenStorageService,
          ),
        ),
        ChangeNotifierProvider<AuthProvider>(
          create: (context) =>
              AuthProvider(authRepository: context.read<AuthRepository>())
                ..initialize(),
        ),
        ProxyProvider<ApiClient, StudentProfileRepository>(
          update: (_, apiClient, _) =>
              StudentProfileRepository(apiClient: apiClient),
        ),
        ChangeNotifierProxyProvider<AuthProvider, StudentProfileProvider>(
          create: (context) => StudentProfileProvider(
            repository: context.read<StudentProfileRepository>(),
            authProvider: context.read<AuthProvider>(),
          ),
          update: (_, _, previous) => previous!,
        ),
        ProxyProvider<ApiClient, OrganizationProfileRepository>(
          update: (_, apiClient, _) =>
              OrganizationProfileRepository(apiClient: apiClient),
        ),
        ChangeNotifierProxyProvider<AuthProvider, OrganizationProfileProvider>(
          create: (context) => OrganizationProfileProvider(
            repository: context.read<OrganizationProfileRepository>(),
            authProvider: context.read<AuthProvider>(),
          ),
          update: (_, _, previous) => previous!,
        ),
        ProxyProvider<ApiClient, OpportunityRepository>(
          update: (_, apiClient, _) =>
              OpportunityRepository(apiClient: apiClient),
        ),
        ChangeNotifierProxyProvider<
          AuthProvider,
          OrganizationOpportunitiesProvider
        >(
          create: (context) => OrganizationOpportunitiesProvider(
            repository: context.read<OpportunityRepository>(),
            authProvider: context.read<AuthProvider>(),
          ),
          update: (_, _, previous) => previous!,
        ),
        ChangeNotifierProxyProvider<AuthProvider, StudentOpportunitiesProvider>(
          create: (context) => StudentOpportunitiesProvider(
            repository: context.read<OpportunityRepository>(),
            authProvider: context.read<AuthProvider>(),
          ),
          update: (_, _, previous) => previous!,
        ),
        ProxyProvider<ApiClient, CvRepository>(
          update: (_, apiClient, _) => CvRepository(apiClient: apiClient),
        ),
        ProxyProvider<ApiClient, StudentSkillRepository>(
          update: (_, apiClient, _) =>
              StudentSkillRepository(apiClient: apiClient),
        ),
        ChangeNotifierProxyProvider<AuthProvider, StudentCvProvider>(
          create: (context) => StudentCvProvider(
            repository: context.read<CvRepository>(),
            studentSkillRepository: context.read<StudentSkillRepository>(),
            authProvider: context.read<AuthProvider>(),
          ),
          update: (_, _, previous) => previous!,
        ),
        ChangeNotifierProxyProvider<AuthProvider, StudentSkillProvider>(
          create: (context) => StudentSkillProvider(
            repository: context.read<StudentSkillRepository>(),
            authProvider: context.read<AuthProvider>(),
          ),
          update: (_, _, previous) => previous!,
        ),
        ProxyProvider<ApiClient, EducationVerificationRepository>(
          update: (_, apiClient, _) =>
              EducationVerificationRepository(apiClient: apiClient),
        ),
        ChangeNotifierProxyProvider<
          AuthProvider,
          StudentEducationVerificationProvider
        >(
          create: (context) => StudentEducationVerificationProvider(
            repository: context.read<EducationVerificationRepository>(),
            authProvider: context.read<AuthProvider>(),
          ),
          update: (_, _, previous) => previous!,
        ),
        ProxyProvider<ApiClient, ApplicationRepository>(
          update: (_, apiClient, _) =>
              ApplicationRepository(apiClient: apiClient),
        ),
        ChangeNotifierProxyProvider<AuthProvider, StudentApplicationsProvider>(
          create: (context) => StudentApplicationsProvider(
            repository: context.read<ApplicationRepository>(),
            authProvider: context.read<AuthProvider>(),
          ),
          update: (_, _, previous) => previous!,
        ),
        ChangeNotifierProxyProvider<
          AuthProvider,
          OrganizationApplicationsProvider
        >(
          create: (context) => OrganizationApplicationsProvider(
            repository: context.read<ApplicationRepository>(),
            authProvider: context.read<AuthProvider>(),
          ),
          update: (_, _, previous) => previous!,
        ),
        ProxyProvider<ApiClient, AssessmentRepository>(
          update: (_, apiClient, _) =>
              AssessmentRepository(apiClient: apiClient),
        ),
        ChangeNotifierProxyProvider<
          AuthProvider,
          OrganizationAssessmentProvider
        >(
          create: (context) => OrganizationAssessmentProvider(
            repository: context.read<AssessmentRepository>(),
            authProvider: context.read<AuthProvider>(),
          ),
          update: (_, _, previous) => previous!,
        ),
        ChangeNotifierProxyProvider<AuthProvider, OrganizationQuizProvider>(
          create: (context) => OrganizationQuizProvider(
            repository: context.read<AssessmentRepository>(),
            authProvider: context.read<AuthProvider>(),
          ),
          update: (_, _, previous) => previous!,
        ),
        ProxyProvider<ApiClient, OfferRepository>(
          update: (_, apiClient, _) => OfferRepository(apiClient: apiClient),
        ),
        ChangeNotifierProxyProvider<AuthProvider, OrganizationOfferProvider>(
          create: (context) => OrganizationOfferProvider(
            repository: context.read<OfferRepository>(),
            authProvider: context.read<AuthProvider>(),
          ),
          update: (_, _, previous) => previous!,
        ),
        ChangeNotifierProxyProvider<
          AuthProvider,
          OrganizationMatchAnalysisProvider
        >(
          create: (context) => OrganizationMatchAnalysisProvider(
            repository: context.read<ApplicationRepository>(),
            authProvider: context.read<AuthProvider>(),
          ),
          update: (_, _, previous) => previous!,
        ),
        ChangeNotifierProxyProvider<AuthProvider, StudentAssessmentProvider>(
          create: (context) => StudentAssessmentProvider(
            repository: context.read<AssessmentRepository>(),
            authProvider: context.read<AuthProvider>(),
          ),
          update: (_, _, previous) => previous!,
        ),
        ChangeNotifierProxyProvider<AuthProvider, StudentOfferProvider>(
          create: (context) => StudentOfferProvider(
            repository: context.read<OfferRepository>(),
            authProvider: context.read<AuthProvider>(),
          ),
          update: (_, _, previous) => previous!,
        ),
        ChangeNotifierProxyProvider<AuthProvider, StudentQuizProvider>(
          create: (context) => StudentQuizProvider(
            repository: context.read<AssessmentRepository>(),
            authProvider: context.read<AuthProvider>(),
          ),
          update: (_, _, previous) => previous!,
        ),
        ProxyProvider<ApiClient, AdminDashboardRepository>(
          update: (_, apiClient, _) =>
              AdminDashboardRepository(apiClient: apiClient),
        ),
        ChangeNotifierProxyProvider<AuthProvider, AdminDashboardProvider>(
          create: (context) => AdminDashboardProvider(
            repository: context.read<AdminDashboardRepository>(),
            authProvider: context.read<AuthProvider>(),
          ),
          update: (_, _, previous) => previous!,
        ),
        ProxyProvider<ApiClient, AdminUsersRepository>(
          update: (_, apiClient, _) =>
              AdminUsersRepository(apiClient: apiClient),
        ),
        ChangeNotifierProxyProvider<AuthProvider, AdminUsersProvider>(
          create: (context) => AdminUsersProvider(
            repository: context.read<AdminUsersRepository>(),
            authProvider: context.read<AuthProvider>(),
          ),
          update: (_, _, previous) => previous!,
        ),
        ProxyProvider<ApiClient, AdminOrganizationsRepository>(
          update: (_, apiClient, _) =>
              AdminOrganizationsRepository(apiClient: apiClient),
        ),
        ChangeNotifierProxyProvider<AuthProvider, AdminOrganizationsProvider>(
          create: (context) => AdminOrganizationsProvider(
            repository: context.read<AdminOrganizationsRepository>(),
            authProvider: context.read<AuthProvider>(),
          ),
          update: (_, _, previous) => previous!,
        ),
        ProxyProvider<ApiClient, AdminSkillsRepository>(
          update: (_, apiClient, _) =>
              AdminSkillsRepository(apiClient: apiClient),
        ),
        ChangeNotifierProxyProvider<AuthProvider, AdminSkillsProvider>(
          create: (context) => AdminSkillsProvider(
            repository: context.read<AdminSkillsRepository>(),
            authProvider: context.read<AuthProvider>(),
          ),
          update: (_, _, previous) => previous!,
        ),
        ProxyProvider<ApiClient, AdminSkillSuggestionsRepository>(
          update: (_, apiClient, _) =>
              AdminSkillSuggestionsRepository(apiClient: apiClient),
        ),
        ChangeNotifierProxyProvider<
          AuthProvider,
          AdminSkillSuggestionsProvider
        >(
          create: (context) => AdminSkillSuggestionsProvider(
            repository: context.read<AdminSkillSuggestionsRepository>(),
            authProvider: context.read<AuthProvider>(),
          ),
          update: (_, _, previous) => previous!,
        ),
        ProxyProvider<ApiClient, AdminEducationVerificationsRepository>(
          update: (_, apiClient, _) =>
              AdminEducationVerificationsRepository(apiClient: apiClient),
        ),
        ChangeNotifierProxyProvider<
          AuthProvider,
          AdminEducationVerificationsProvider
        >(
          create: (context) => AdminEducationVerificationsProvider(
            repository: context.read<AdminEducationVerificationsRepository>(),
            authProvider: context.read<AuthProvider>(),
          ),
          update: (_, _, previous) => previous!,
        ),
        ProxyProvider<ApiClient, CandidateRepository>(
          update: (_, apiClient, _) => CandidateRepository(apiClient: apiClient),
        ),
        ProxyProvider<ApiClient, InvitationRepository>(
          update: (_, apiClient, _) =>
              InvitationRepository(apiClient: apiClient),
        ),
        ChangeNotifierProxyProvider<AuthProvider, CandidateSearchProvider>(
          create: (context) => CandidateSearchProvider(
            repository: context.read<CandidateRepository>(),
            invitationRepository: context.read<InvitationRepository>(),
            authProvider: context.read<AuthProvider>(),
          ),
          update: (_, _, previous) => previous!,
        ),
        ChangeNotifierProxyProvider<AuthProvider, StudentInvitationsProvider>(
          create: (context) => StudentInvitationsProvider(
            repository: context.read<InvitationRepository>(),
            authProvider: context.read<AuthProvider>(),
          ),
          update: (_, _, previous) => previous!,
        ),
        ProxyProvider<ApiClient, NotificationRepository>(
          update: (_, apiClient, _) =>
              NotificationRepository(apiClient: apiClient),
        ),
        ChangeNotifierProxyProvider<AuthProvider, NotificationProvider>(
          create: (context) => NotificationProvider(
            repository: context.read<NotificationRepository>(),
            authProvider: context.read<AuthProvider>(),
          ),
          update: (_, _, previous) => previous!,
        ),
      ],
      child: const _AppRoot(),
    );
  }
}

/// Builds the app's [GoRouter] once, wired to the [AuthProvider] so it can
/// react to login/logout without being recreated on every rebuild.
class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  late final AppRouter _appRouter;

  @override
  void initState() {
    super.initState();
    _appRouter = AppRouter(
      context.read<AuthProvider>(),
      context.read<StudentProfileProvider>(),
      context.read<OrganizationProfileProvider>(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeProvider>().mode;

    return MaterialApp.router(
      title: 'OpportunityHub',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: _appRouter.router,
    );
  }
}
