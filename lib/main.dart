import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/api/api_client.dart';
import 'core/storage/token_storage_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/opportunities/data/opportunity_repository.dart';
import 'features/organization/data/organization_profile_repository.dart';
import 'features/student/data/student_profile_repository.dart';
import 'providers/auth_provider.dart';
import 'providers/organization_opportunities_provider.dart';
import 'providers/organization_profile_provider.dart';
import 'providers/student_opportunities_provider.dart';
import 'providers/student_profile_provider.dart';
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
