import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/api/api_client.dart';
import 'core/storage/token_storage_service.dart';
import 'core/theme/app_theme.dart';
import 'features/admin/data/admin_dashboard_repository.dart';
import 'features/admin/data/admin_organizations_repository.dart';
import 'features/admin/data/admin_skills_repository.dart';
import 'features/admin/data/admin_users_repository.dart';
import 'features/applications/data/application_repository.dart';
import 'features/assessments/data/assessment_repository.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/cv/data/cv_repository.dart';
import 'features/offers/data/offer_repository.dart';
import 'features/opportunities/data/opportunity_repository.dart';
import 'features/organization/data/organization_profile_repository.dart';
import 'features/student/data/student_profile_repository.dart';
import 'providers/admin_dashboard_provider.dart';
import 'providers/admin_organizations_provider.dart';
import 'providers/admin_skills_provider.dart';
import 'providers/admin_users_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/organization_applications_provider.dart';
import 'providers/organization_assessment_provider.dart';
import 'providers/organization_offer_provider.dart';
import 'providers/organization_opportunities_provider.dart';
import 'providers/organization_profile_provider.dart';
import 'providers/organization_quiz_provider.dart';
import 'providers/student_applications_provider.dart';
import 'providers/student_assessment_provider.dart';
import 'providers/student_cv_provider.dart';
import 'providers/student_opportunities_provider.dart';
import 'providers/student_profile_provider.dart';
import 'providers/student_quiz_provider.dart';
import 'routes/app_router.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
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
        ChangeNotifierProxyProvider<AuthProvider, StudentCvProvider>(
          create: (context) => StudentCvProvider(
            repository: context.read<CvRepository>(),
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
        ChangeNotifierProxyProvider<AuthProvider, StudentAssessmentProvider>(
          create: (context) => StudentAssessmentProvider(
            repository: context.read<AssessmentRepository>(),
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
    return MaterialApp.router(
      title: 'OpportunityHub',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: _appRouter.router,
    );
  }
}
