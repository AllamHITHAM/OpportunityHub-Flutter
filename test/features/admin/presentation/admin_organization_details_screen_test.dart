// Widget tests for AdminOrganizationDetailsScreen, in isolation with a
// small GoRouter. Mirrors admin_users_screen_test.dart's structure and
// conventions.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/core/widgets/danger_button.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_dashboard_repository.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_organizations_repository.dart';
import 'package:opportunityhub_flutter/features/admin/presentation/admin_organization_details_screen.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/models/admin_dashboard_stats_model.dart';
import 'package:opportunityhub_flutter/models/organization_profile_model.dart';
import 'package:opportunityhub_flutter/models/user_model.dart';
import 'package:opportunityhub_flutter/providers/admin_dashboard_provider.dart';
import 'package:opportunityhub_flutter/providers/admin_organizations_provider.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  @override
  Future<String?> getSavedToken() async => null;
}

OrganizationProfileModel _organization({
  int id = 7,
  String organizationName = 'Acme Corp',
  String organizationType = 'company',
  String approvalStatus = 'pending',
  String? phone,
  String? website,
  String? industry,
  String? description,
}) {
  return OrganizationProfileModel(
    id: id,
    organizationName: organizationName,
    organizationType: organizationType,
    approvalStatus: approvalStatus,
    phone: phone,
    website: website,
    industry: industry,
    description: description,
    user: UserModel(
      id: id + 100,
      name: '$organizationName Contact',
      email: 'contact@acme.example',
      role: 'organization',
      status: 'active',
    ),
  );
}

class _FakeAdminOrganizationsRepository extends AdminOrganizationsRepository {
  _FakeAdminOrganizationsRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  OrganizationProfileModel? detailsResult;
  ApiException? detailsError;
  Duration detailsDelay = Duration.zero;
  int getOrganizationCallCount = 0;

  OrganizationProfileModel? actionResult;
  ApiException? actionError;
  Duration actionDelay = Duration.zero;
  int approveCallCount = 0;
  int rejectCallCount = 0;

  @override
  Future<OrganizationProfileModel> getOrganization(int organizationId) async {
    getOrganizationCallCount++;
    if (detailsDelay > Duration.zero) {
      await Future<void>.delayed(detailsDelay);
    }
    if (detailsError != null) throw detailsError!;
    return detailsResult!;
  }

  @override
  Future<OrganizationProfileModel> approveOrganization(
    int organizationId,
  ) async {
    approveCallCount++;
    if (actionDelay > Duration.zero) {
      await Future<void>.delayed(actionDelay);
    }
    if (actionError != null) throw actionError!;
    return actionResult!;
  }

  @override
  Future<OrganizationProfileModel> rejectOrganization(
    int organizationId,
  ) async {
    rejectCallCount++;
    if (actionDelay > Duration.zero) {
      await Future<void>.delayed(actionDelay);
    }
    if (actionError != null) throw actionError!;
    return actionResult!;
  }
}

class _FakeAdminDashboardRepository extends AdminDashboardRepository {
  _FakeAdminDashboardRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  int getDashboardStatsCallCount = 0;

  @override
  Future<AdminDashboardStatsModel> getDashboardStats() async {
    getDashboardStatsCallCount++;
    return const AdminDashboardStatsModel(
      totalUsers: 1,
      totalStudents: 0,
      totalOrganizations: 1,
      pendingOrganizations: 1,
      approvedOrganizations: 0,
      rejectedOrganizations: 0,
      totalOpportunities: 0,
      openOpportunities: 0,
      closedOpportunities: 0,
      totalApplications: 0,
      totalInterviews: 0,
    );
  }
}

class _Providers {
  _Providers({required this.organizations, required this.dashboard});

  final AdminOrganizationsProvider organizations;
  final AdminDashboardProvider dashboard;
}

Future<_Providers> _pumpScreen(
  WidgetTester tester, {
  required AdminOrganizationsRepository repository,
  AdminDashboardRepository? dashboardRepository,
  int organizationId = 7,
  Size size = const Size(420, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final organizationsProvider = AdminOrganizationsProvider(
    repository: repository,
    authProvider: authProvider,
  );
  final dashboardProvider = AdminDashboardProvider(
    repository: dashboardRepository ?? _FakeAdminDashboardRepository(),
    authProvider: authProvider,
  );

  final router = GoRouter(
    initialLocation: '/admin/organizations/$organizationId',
    routes: [
      GoRoute(
        path: '/admin/organizations/:id',
        builder: (_, state) => AdminOrganizationDetailsScreen(
          organizationId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<AdminOrganizationsProvider>.value(
          value: organizationsProvider,
        ),
        ChangeNotifierProvider<AdminDashboardProvider>.value(
          value: dashboardProvider,
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  return _Providers(
    organizations: organizationsProvider,
    dashboard: dashboardProvider,
  );
}

void main() {
  testWidgets('Loading state renders while details are in flight', (
    tester,
  ) async {
    final repository = _FakeAdminOrganizationsRepository()
      ..detailsResult = _organization()
      ..detailsDelay = const Duration(milliseconds: 200);

    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final organizationsProvider = AdminOrganizationsProvider(
      repository: repository,
      authProvider: authProvider,
    );
    final dashboardProvider = AdminDashboardProvider(
      repository: _FakeAdminDashboardRepository(),
      authProvider: authProvider,
    );
    final router = GoRouter(
      initialLocation: '/admin/organizations/7',
      routes: [
        GoRoute(
          path: '/admin/organizations/:id',
          builder: (_, state) => AdminOrganizationDetailsScreen(
            organizationId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0,
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<AdminOrganizationsProvider>.value(
            value: organizationsProvider,
          ),
          ChangeNotifierProvider<AdminDashboardProvider>.value(
            value: dashboardProvider,
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

    expect(organizationsProvider.isLoadingDetails, isTrue);
    expect(find.text('Acme Corp'), findsNothing);

    await tester.pumpAndSettle();
  });

  testWidgets('Error state shows AppErrorView and a working retry', (
    tester,
  ) async {
    final repository = _FakeAdminOrganizationsRepository()
      ..detailsError = ApiException('Organization not found.', statusCode: 404);

    await _pumpScreen(tester, repository: repository);

    expect(find.text('Organization not found.'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);

    repository.detailsError = null;
    repository.detailsResult = _organization();
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();

    expect(find.text('Acme Corp'), findsOneWidget);
  });

  testWidgets('A malformed/nonexistent ID (0) is handled safely, not a crash', (
    tester,
  ) async {
    final repository = _FakeAdminOrganizationsRepository()
      ..detailsError = ApiException('No query results.', statusCode: 404);

    await _pumpScreen(tester, repository: repository, organizationId: 0);

    expect(find.text('No query results.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Fields render: name, type, email, phone, website, industry, description',
    (tester) async {
      final repository = _FakeAdminOrganizationsRepository()
        ..detailsResult = _organization(
          organizationName: 'Acme Corp',
          organizationType: 'company',
          phone: '555-1234',
          website: 'https://acme.example',
          industry: 'Tech',
          description: 'We build things.',
        );

      await _pumpScreen(tester, repository: repository);

      expect(find.text('Acme Corp'), findsOneWidget);
      expect(find.text('Company'), findsOneWidget);
      expect(find.text('contact@acme.example'), findsOneWidget);
      expect(find.text('555-1234'), findsOneWidget);
      expect(find.text('https://acme.example'), findsOneWidget);
      expect(find.text('Tech'), findsOneWidget);
      expect(find.text('We build things.'), findsOneWidget);
    },
  );

  testWidgets('A pending organization shows Approve and Reject actions', (
    tester,
  ) async {
    final repository = _FakeAdminOrganizationsRepository()
      ..detailsResult = _organization(approvalStatus: 'pending');

    await _pumpScreen(tester, repository: repository);

    expect(find.widgetWithText(ElevatedButton, 'Approve'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Reject'), findsOneWidget);
  });

  testWidgets('An approved organization shows no approval actions', (
    tester,
  ) async {
    final repository = _FakeAdminOrganizationsRepository()
      ..detailsResult = _organization(approvalStatus: 'approved');

    await _pumpScreen(tester, repository: repository);

    expect(find.text('Approved'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Approve'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Reject'), findsNothing);
  });

  testWidgets('A rejected organization shows no approval actions', (
    tester,
  ) async {
    final repository = _FakeAdminOrganizationsRepository()
      ..detailsResult = _organization(approvalStatus: 'rejected');

    await _pumpScreen(tester, repository: repository);

    expect(find.text('Rejected'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Approve'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Reject'), findsNothing);
  });

  testWidgets('Approve confirmation: cancel performs no mutation', (
    tester,
  ) async {
    final repository = _FakeAdminOrganizationsRepository()
      ..detailsResult = _organization(approvalStatus: 'pending');
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Approve'));
    await tester.pumpAndSettle();

    expect(find.text('Approve Organization'), findsOneWidget);
    expect(
      find.text('Are you sure you want to approve this organization?'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repository.approveCallCount, 0);
    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('Approve confirmation: confirm approves the organization', (
    tester,
  ) async {
    final repository = _FakeAdminOrganizationsRepository()
      ..detailsResult = _organization(approvalStatus: 'pending')
      ..actionResult = _organization(approvalStatus: 'approved');
    final providers = await _pumpScreen(tester, repository: repository);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Approve').last);
    await tester.pumpAndSettle();

    expect(repository.approveCallCount, 1);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Approve'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Reject'), findsNothing);
    expect(find.text('Organization approved successfully'), findsOneWidget);
    // Dashboard sync triggered from the presentation layer.
    expect(providers.dashboard.stats, isNotNull);
  });

  testWidgets('Reject confirmation: cancel performs no mutation', (
    tester,
  ) async {
    final repository = _FakeAdminOrganizationsRepository()
      ..detailsResult = _organization(approvalStatus: 'pending');
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reject'));
    await tester.pumpAndSettle();

    expect(find.text('Reject Organization'), findsOneWidget);
    expect(
      find.text('Are you sure you want to reject this organization?'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repository.rejectCallCount, 0);
    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('Reject confirmation: confirm rejects the organization', (
    tester,
  ) async {
    final repository = _FakeAdminOrganizationsRepository()
      ..detailsResult = _organization(approvalStatus: 'pending')
      ..actionResult = _organization(approvalStatus: 'rejected');
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reject'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Reject').last);
    await tester.pumpAndSettle();

    expect(repository.rejectCallCount, 1);
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Organization rejected successfully'), findsOneWidget);
  });

  testWidgets('Busy state disables actions while an approve is in flight', (
    tester,
  ) async {
    final repository = _FakeAdminOrganizationsRepository()
      ..detailsResult = _organization(approvalStatus: 'pending')
      ..actionResult = _organization(approvalStatus: 'approved')
      ..actionDelay = const Duration(milliseconds: 2000);
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Approve').last);
    await tester.pump(const Duration(milliseconds: 500));

    final rejectButton = tester.widget<DangerButton>(
      find.byKey(const Key('reject-action')),
    );
    expect(rejectButton.isLoading, isFalse);
    expect(rejectButton.onPressed, isNull);

    await tester.pumpAndSettle();
  });

  testWidgets(
    'An action failure retains the old status and shows the message',
    (tester) async {
      final repository = _FakeAdminOrganizationsRepository()
        ..detailsResult = _organization(approvalStatus: 'pending')
        ..actionError = ApiException(
          'This action is unauthorized for your account type',
          statusCode: 403,
        );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Approve').last);
      await tester.pumpAndSettle();

      expect(find.text('Pending'), findsOneWidget);
      expect(
        find.text('This action is unauthorized for your account type'),
        findsOneWidget,
      );
      expect(find.widgetWithText(ElevatedButton, 'Approve'), findsOneWidget);
    },
  );

  testWidgets(
    'A successful approve patches the UI immediately, without a full list reload',
    (tester) async {
      final repository = _FakeAdminOrganizationsRepository()
        ..detailsResult = _organization(approvalStatus: 'pending')
        ..actionResult = _organization(approvalStatus: 'approved');
      await _pumpScreen(tester, repository: repository);
      expect(repository.getOrganizationCallCount, 1);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Approve').last);
      await tester.pumpAndSettle();

      expect(find.text('Approved'), findsOneWidget);
      // No reload -- still exactly the one initial GET.
      expect(repository.getOrganizationCallCount, 1);
    },
  );

  testWidgets('Pull-to-refresh calls the provider and reloads details', (
    tester,
  ) async {
    final repository = _FakeAdminOrganizationsRepository()
      ..detailsResult = _organization();
    await _pumpScreen(tester, repository: repository);
    expect(repository.getOrganizationCallCount, 1);

    unawaited(
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show(),
    );
    await tester.pumpAndSettle();

    expect(repository.getOrganizationCallCount, 2);
  });
}
