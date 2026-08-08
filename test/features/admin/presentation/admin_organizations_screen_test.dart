// Widget tests for AdminOrganizationsScreen, in isolation with a small
// GoRouter. Mirrors admin_users_screen_test.dart's structure and
// conventions.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_organizations_repository.dart';
import 'package:opportunityhub_flutter/features/admin/presentation/admin_organization_details_screen.dart';
import 'package:opportunityhub_flutter/features/admin/presentation/admin_organizations_screen.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/models/organization_profile_model.dart';
import 'package:opportunityhub_flutter/models/user_model.dart';
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
  int id = 1,
  String organizationName = 'Acme Corp',
  String organizationType = 'company',
  String approvalStatus = 'pending',
  bool withUser = true,
  String? email,
}) {
  // Defaults to a unique per-id address (not a shared literal) so two
  // organizations built with default arguments in the same test never
  // accidentally collide on a search query.
  final resolvedEmail = email ?? 'org$id@example.com';
  return OrganizationProfileModel(
    id: id,
    organizationName: organizationName,
    organizationType: organizationType,
    approvalStatus: approvalStatus,
    user: withUser
        ? UserModel(
            id: id + 100,
            name: '$organizationName Contact',
            email: resolvedEmail,
            role: 'organization',
            status: 'active',
          )
        : null,
  );
}

class _FakeAdminOrganizationsRepository extends AdminOrganizationsRepository {
  _FakeAdminOrganizationsRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<OrganizationProfileModel>? loadResult;
  ApiException? loadError;
  Duration loadDelay = Duration.zero;
  int getOrganizationsCallCount = 0;
  int getOrganizationCallCount = 0;

  @override
  Future<List<OrganizationProfileModel>> getOrganizations() async {
    getOrganizationsCallCount++;
    if (loadDelay > Duration.zero) {
      await Future<void>.delayed(loadDelay);
    }
    if (loadError != null) throw loadError!;
    return loadResult ?? [];
  }

  // Only reached by the row-navigation test — the details screen it
  // navigates to calls this to load the same organization it was already
  // showing in the list.
  @override
  Future<OrganizationProfileModel> getOrganization(int organizationId) async {
    getOrganizationCallCount++;
    return loadResult!.firstWhere((o) => o.id == organizationId);
  }
}

class _Providers {
  _Providers({required this.organizations});

  final AdminOrganizationsProvider organizations;
}

Future<_Providers> _pumpScreen(
  WidgetTester tester, {
  required AdminOrganizationsRepository repository,
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

  final router = GoRouter(
    initialLocation: '/admin/organizations',
    routes: [
      GoRoute(
        path: '/admin/organizations',
        builder: (_, _) => const AdminOrganizationsScreen(),
      ),
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
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  return _Providers(organizations: organizationsProvider);
}

void main() {
  testWidgets('Loading state renders while organizations are in flight', (
    tester,
  ) async {
    final repository = _FakeAdminOrganizationsRepository()
      ..loadResult = [_organization()]
      ..loadDelay = const Duration(milliseconds: 200);

    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final organizationsProvider = AdminOrganizationsProvider(
      repository: repository,
      authProvider: authProvider,
    );
    final router = GoRouter(
      initialLocation: '/admin/organizations',
      routes: [
        GoRoute(
          path: '/admin/organizations',
          builder: (_, _) => const AdminOrganizationsScreen(),
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
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(organizationsProvider.isLoading, isTrue);
    expect(find.text('Acme Corp'), findsNothing);

    await tester.pumpAndSettle();
  });

  testWidgets(
    'Error state with no organizations shows AppErrorView and a working retry',
    (tester) async {
      final repository = _FakeAdminOrganizationsRepository()
        ..loadError = ApiException('Server error, please try again later.');

      final providers = await _pumpScreen(tester, repository: repository);

      expect(
        find.text('Server error, please try again later.'),
        findsOneWidget,
      );
      expect(find.text('Try Again'), findsOneWidget);

      repository.loadError = null;
      repository.loadResult = [_organization()];
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();

      expect(find.text('Acme Corp'), findsOneWidget);
      expect(providers.organizations.organizations, hasLength(1));
    },
  );

  testWidgets('Empty state shows AppEmptyView', (tester) async {
    final repository = _FakeAdminOrganizationsRepository()..loadResult = [];

    await _pumpScreen(tester, repository: repository);

    expect(find.text('No Organizations Yet'), findsOneWidget);
  });

  testWidgets('Renders organization cards with name, type, email, and status', (
    tester,
  ) async {
    final repository = _FakeAdminOrganizationsRepository()
      ..loadResult = [
        _organization(
          id: 1,
          organizationName: 'Acme Corp',
          organizationType: 'company',
          approvalStatus: 'pending',
          email: 'contact@acme.example',
        ),
      ];

    await _pumpScreen(tester, repository: repository);

    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.text('contact@acme.example'), findsOneWidget);
    expect(find.text('Company'), findsOneWidget);
    // Two: the "Pending" approval-filter chip plus this card's own
    // "Pending" status chip.
    expect(find.text('Pending'), findsNWidgets(2));
  });

  testWidgets('Search filters by organization name', (tester) async {
    final repository = _FakeAdminOrganizationsRepository()
      ..loadResult = [
        _organization(id: 1, organizationName: 'Acme Corp'),
        _organization(id: 2, organizationName: 'Beta LLC'),
      ];

    await _pumpScreen(tester, repository: repository);

    await tester.enterText(find.byType(TextFormField), 'Acme');
    await tester.pumpAndSettle();

    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.text('Beta LLC'), findsNothing);
  });

  testWidgets('Search filters by user email', (tester) async {
    final repository = _FakeAdminOrganizationsRepository()
      ..loadResult = [
        _organization(
          id: 1,
          organizationName: 'Acme Corp',
          email: 'acme@example.com',
        ),
        _organization(
          id: 2,
          organizationName: 'Beta LLC',
          email: 'beta@example.com',
        ),
      ];

    await _pumpScreen(tester, repository: repository);

    await tester.enterText(find.byType(TextFormField), 'beta@example.com');
    await tester.pumpAndSettle();

    expect(find.text('Beta LLC'), findsOneWidget);
    expect(find.text('Acme Corp'), findsNothing);
  });

  testWidgets('Search filters by type, case-insensitively', (tester) async {
    final repository = _FakeAdminOrganizationsRepository()
      ..loadResult = [
        _organization(
          id: 1,
          organizationName: 'Acme Corp',
          organizationType: 'company',
        ),
        _organization(
          id: 2,
          organizationName: 'State University',
          organizationType: 'university',
        ),
      ];

    await _pumpScreen(tester, repository: repository);

    await tester.enterText(find.byType(TextFormField), 'UNIVERSITY');
    await tester.pumpAndSettle();

    expect(find.text('State University'), findsOneWidget);
    expect(find.text('Acme Corp'), findsNothing);
  });

  testWidgets(
    'Search with no matches shows a dedicated no-match state, not the general empty state',
    (tester) async {
      final repository = _FakeAdminOrganizationsRepository()
        ..loadResult = [_organization(id: 1, organizationName: 'Acme Corp')];

      await _pumpScreen(tester, repository: repository);

      await tester.enterText(find.byType(TextFormField), 'nonexistent-org-xyz');
      await tester.pumpAndSettle();

      expect(find.text('No Matches'), findsOneWidget);
      expect(find.text('No Organizations Yet'), findsNothing);
    },
  );

  testWidgets('Approval filter narrows the list to the selected status', (
    tester,
  ) async {
    final repository = _FakeAdminOrganizationsRepository()
      ..loadResult = [
        _organization(
          id: 1,
          organizationName: 'Pending Org',
          approvalStatus: 'pending',
        ),
        _organization(
          id: 2,
          organizationName: 'Approved Org',
          approvalStatus: 'approved',
        ),
        _organization(
          id: 3,
          organizationName: 'Rejected Org',
          approvalStatus: 'rejected',
        ),
      ];

    await _pumpScreen(tester, repository: repository);

    expect(find.text('Pending Org'), findsOneWidget);
    expect(find.text('Approved Org'), findsOneWidget);
    expect(find.text('Rejected Org'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Approved'));
    await tester.pumpAndSettle();

    expect(find.text('Approved Org'), findsOneWidget);
    expect(find.text('Pending Org'), findsNothing);
    expect(find.text('Rejected Org'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.pumpAndSettle();

    expect(find.text('Pending Org'), findsOneWidget);
    expect(find.text('Approved Org'), findsOneWidget);
    expect(find.text('Rejected Org'), findsOneWidget);
  });

  testWidgets('Tapping a card navigates to organization details', (
    tester,
  ) async {
    final repository = _FakeAdminOrganizationsRepository()
      ..loadResult = [_organization(id: 7, organizationName: 'Acme Corp')];

    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.text('Acme Corp'));
    await tester.pumpAndSettle();

    expect(find.byType(AdminOrganizationDetailsScreen), findsOneWidget);
    expect(find.text('Organization Details'), findsOneWidget);
  });

  testWidgets('Pull-to-refresh calls the provider and reloads the list', (
    tester,
  ) async {
    final repository = _FakeAdminOrganizationsRepository()
      ..loadResult = [_organization()];
    await _pumpScreen(tester, repository: repository);
    expect(repository.getOrganizationsCallCount, 1);

    unawaited(
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show(),
    );
    await tester.pumpAndSettle();

    expect(repository.getOrganizationsCallCount, 2);
  });

  testWidgets(
    'A failed refresh keeps the old list visible, not a blank screen',
    (tester) async {
      final repository = _FakeAdminOrganizationsRepository()
        ..loadResult = [_organization(id: 1, organizationName: 'Acme Corp')];
      await _pumpScreen(tester, repository: repository);
      expect(find.text('Acme Corp'), findsOneWidget);

      repository.loadResult = null;
      repository.loadError = ApiException('Server error, please retry.');

      unawaited(
        tester
            .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
            .show(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Acme Corp'), findsOneWidget); // old list retained
      expect(find.text('Server error, please retry.'), findsOneWidget);
    },
  );

  testWidgets('No overflow at a narrow 320-wide viewport', (tester) async {
    final repository = _FakeAdminOrganizationsRepository()
      ..loadResult = [
        _organization(
          id: 1,
          organizationName:
              'A Very Long Organization Name That Might Wrap Or Overflow',
          email: 'a-very-long-email-address@example.com',
        ),
      ];

    await _pumpScreen(
      tester,
      repository: repository,
      size: const Size(320, 700),
    );

    expect(tester.takeException(), isNull);
  });
}
