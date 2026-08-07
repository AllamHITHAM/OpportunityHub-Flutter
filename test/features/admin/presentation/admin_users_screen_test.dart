// Widget tests for AdminUsersScreen, in isolation with a small GoRouter.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/core/widgets/danger_button.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_users_repository.dart';
import 'package:opportunityhub_flutter/features/admin/presentation/admin_users_screen.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/models/user_model.dart';
import 'package:opportunityhub_flutter/providers/admin_users_provider.dart';
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

const _selfAdmin = UserModel(
  id: 1,
  name: 'Root Admin',
  email: 'root@example.com',
  role: 'admin',
  status: 'active',
);

UserModel _user({
  int id = 2,
  String name = 'Jane Student',
  String email = 'jane@example.com',
  String role = 'student',
  String status = 'active',
  DateTime? createdAt,
}) {
  return UserModel(
    id: id,
    name: name,
    email: email,
    role: role,
    status: status,
    createdAt: createdAt,
  );
}

class _FakeAdminUsersRepository extends AdminUsersRepository {
  _FakeAdminUsersRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<UserModel>? loadResult;
  ApiException? loadError;
  Duration loadDelay = Duration.zero;
  int getUsersCallCount = 0;

  UserModel? updateResult;
  ApiException? updateError;
  Duration updateDelay = Duration.zero;
  int updateStatusCallCount = 0;

  @override
  Future<List<UserModel>> getUsers() async {
    getUsersCallCount++;
    if (loadDelay > Duration.zero) {
      await Future<void>.delayed(loadDelay);
    }
    if (loadError != null) throw loadError!;
    return loadResult ?? [];
  }

  @override
  Future<UserModel> updateUserStatus({
    required int userId,
    required String status,
  }) async {
    updateStatusCallCount++;
    if (updateDelay > Duration.zero) {
      await Future<void>.delayed(updateDelay);
    }
    if (updateError != null) throw updateError!;
    return updateResult!;
  }
}

class _Providers {
  _Providers({required this.auth, required this.users});

  final AuthProvider auth;
  final AdminUsersProvider users;
}

Future<_Providers> _pumpScreen(
  WidgetTester tester, {
  required AdminUsersRepository repository,
  UserModel selfUser = _selfAdmin,
  Size size = const Size(420, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository())
    ..user = selfUser;
  final usersProvider = AdminUsersProvider(
    repository: repository,
    authProvider: authProvider,
  );

  final router = GoRouter(
    initialLocation: '/admin/users',
    routes: [
      GoRoute(
        path: '/admin/users',
        builder: (_, _) => const AdminUsersScreen(),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<AdminUsersProvider>.value(value: usersProvider),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  return _Providers(auth: authProvider, users: usersProvider);
}

void main() {
  testWidgets('Loading state renders while users are in flight', (
    tester,
  ) async {
    final repository = _FakeAdminUsersRepository()
      ..loadResult = [_user()]
      ..loadDelay = const Duration(milliseconds: 200);

    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = AuthProvider(authRepository: _FakeAuthRepository())
      ..user = _selfAdmin;
    final usersProvider = AdminUsersProvider(
      repository: repository,
      authProvider: authProvider,
    );
    final router = GoRouter(
      initialLocation: '/admin/users',
      routes: [
        GoRoute(
          path: '/admin/users',
          builder: (_, _) => const AdminUsersScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<AdminUsersProvider>.value(
            value: usersProvider,
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

    expect(usersProvider.isLoading, isTrue);
    expect(find.text('Jane Student'), findsNothing);

    await tester.pumpAndSettle();
  });

  testWidgets(
    'Error state with no users shows AppErrorView and a working retry',
    (tester) async {
      final repository = _FakeAdminUsersRepository()
        ..loadError = ApiException('Server error, please try again later.');

      final providers = await _pumpScreen(tester, repository: repository);

      expect(
        find.text('Server error, please try again later.'),
        findsOneWidget,
      );
      expect(find.text('Try Again'), findsOneWidget);

      repository.loadError = null;
      repository.loadResult = [_user()];
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();

      expect(find.text('Jane Student'), findsOneWidget);
      expect(providers.users.users, hasLength(1));
    },
  );

  testWidgets('Empty state shows AppEmptyView', (tester) async {
    final repository = _FakeAdminUsersRepository()..loadResult = [];

    await _pumpScreen(tester, repository: repository);

    expect(find.text('No Users Yet'), findsOneWidget);
  });

  testWidgets('Renders user rows with name, email, role, and status', (
    tester,
  ) async {
    final repository = _FakeAdminUsersRepository()
      ..loadResult = [
        _user(
          id: 2,
          name: 'Jane Student',
          email: 'jane@example.com',
          role: 'student',
          status: 'active',
        ),
      ];

    await _pumpScreen(tester, repository: repository);

    expect(find.text('Jane Student'), findsOneWidget);
    expect(find.text('jane@example.com'), findsOneWidget);
    expect(find.text('Student'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
  });

  testWidgets('Renders the joined date when createdAt is present', (
    tester,
  ) async {
    final repository = _FakeAdminUsersRepository()
      ..loadResult = [_user(createdAt: DateTime(2026, 7, 1))];

    await _pumpScreen(tester, repository: repository);

    expect(find.textContaining('Joined'), findsOneWidget);
  });

  testWidgets('Search filters by name', (tester) async {
    final repository = _FakeAdminUsersRepository()
      ..loadResult = [
        _user(id: 2, name: 'Jane Student', email: 'jane@example.com'),
        _user(id: 3, name: 'John Organization', email: 'john@example.com'),
      ];

    await _pumpScreen(tester, repository: repository);

    await tester.enterText(find.byType(TextFormField), 'Jane');
    await tester.pumpAndSettle();

    expect(find.text('Jane Student'), findsOneWidget);
    expect(find.text('John Organization'), findsNothing);
  });

  testWidgets('Search filters by email', (tester) async {
    final repository = _FakeAdminUsersRepository()
      ..loadResult = [
        _user(id: 2, name: 'Jane Student', email: 'jane@example.com'),
        _user(id: 3, name: 'John Organization', email: 'john@example.com'),
      ];

    await _pumpScreen(tester, repository: repository);

    await tester.enterText(find.byType(TextFormField), 'john@example.com');
    await tester.pumpAndSettle();

    expect(find.text('John Organization'), findsOneWidget);
    expect(find.text('Jane Student'), findsNothing);
  });

  testWidgets('Search filters by role, case-insensitively', (tester) async {
    final repository = _FakeAdminUsersRepository()
      ..loadResult = [
        _user(id: 2, name: 'Jane Student', role: 'student'),
        _user(id: 3, name: 'Acme Corp', role: 'organization'),
      ];

    await _pumpScreen(tester, repository: repository);

    await tester.enterText(find.byType(TextFormField), 'ORGANIZATION');
    await tester.pumpAndSettle();

    expect(find.text('Acme Corp'), findsOneWidget);
    expect(find.text('Jane Student'), findsNothing);
  });

  testWidgets(
    'Search with no matches shows a dedicated no-match state, not the general empty state',
    (tester) async {
      final repository = _FakeAdminUsersRepository()
        ..loadResult = [_user(id: 2, name: 'Jane Student')];

      await _pumpScreen(tester, repository: repository);

      await tester.enterText(
        find.byType(TextFormField),
        'nonexistent-user-xyz',
      );
      await tester.pumpAndSettle();

      expect(find.text('No Matches'), findsOneWidget);
      expect(find.text('No Users Yet'), findsNothing);
    },
  );

  testWidgets('An active user shows a Suspend action', (tester) async {
    final repository = _FakeAdminUsersRepository()
      ..loadResult = [_user(id: 2, status: 'active')];

    await _pumpScreen(tester, repository: repository);

    expect(find.widgetWithText(OutlinedButton, 'Suspend'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Reactivate'), findsNothing);
  });

  testWidgets('A suspended user shows a Reactivate action', (tester) async {
    final repository = _FakeAdminUsersRepository()
      ..loadResult = [_user(id: 2, status: 'suspended')];

    await _pumpScreen(tester, repository: repository);

    expect(find.widgetWithText(ElevatedButton, 'Reactivate'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Suspend'), findsNothing);
  });

  testWidgets('A pending user shows no status action', (tester) async {
    final repository = _FakeAdminUsersRepository()
      ..loadResult = [_user(id: 2, status: 'pending')];

    await _pumpScreen(tester, repository: repository);

    expect(find.text('Pending'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Suspend'), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Reactivate'), findsNothing);
  });

  testWidgets(
    'The current admin\'s own row shows a "You" marker and no status action',
    (tester) async {
      final repository = _FakeAdminUsersRepository()
        ..loadResult = [_selfAdmin, _user(id: 2, status: 'active')];

      await _pumpScreen(tester, repository: repository);

      expect(find.text('You'), findsOneWidget);
      // Only the other (non-self) active user gets a Suspend button.
      expect(find.widgetWithText(OutlinedButton, 'Suspend'), findsOneWidget);
    },
  );

  testWidgets('Suspend confirmation: cancel performs no status change', (
    tester,
  ) async {
    final repository = _FakeAdminUsersRepository()
      ..loadResult = [_user(id: 2, status: 'active')];
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Suspend'));
    await tester.pumpAndSettle();

    expect(find.text('Suspend User'), findsOneWidget);
    expect(
      find.text('Are you sure you want to suspend this user?'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repository.updateStatusCallCount, 0);
    expect(find.text('Active'), findsOneWidget);
  });

  testWidgets('Suspend confirmation: confirm suspends the user', (
    tester,
  ) async {
    final repository = _FakeAdminUsersRepository()
      ..loadResult = [_user(id: 2, status: 'active')]
      ..updateResult = _user(id: 2, status: 'suspended');
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Suspend'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Suspend').last);
    await tester.pumpAndSettle();

    expect(repository.updateStatusCallCount, 1);
    expect(find.text('Suspended'), findsOneWidget);
  });

  testWidgets('Reactivate confirmation: confirm reactivates the user', (
    tester,
  ) async {
    final repository = _FakeAdminUsersRepository()
      ..loadResult = [_user(id: 2, status: 'suspended')]
      ..updateResult = _user(id: 2, status: 'active');
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Reactivate'));
    await tester.pumpAndSettle();

    expect(find.text('Reactivate User'), findsOneWidget);
    expect(
      find.text('Are you sure you want to reactivate this user?'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Reactivate').last);
    await tester.pumpAndSettle();

    expect(repository.updateStatusCallCount, 1);
    expect(find.text('Active'), findsOneWidget);
  });

  testWidgets('Row-level busy state disables the action while in flight', (
    tester,
  ) async {
    final repository = _FakeAdminUsersRepository()
      ..loadResult = [_user(id: 2, status: 'active')]
      ..updateResult = _user(id: 2, status: 'suspended')
      ..updateDelay = const Duration(milliseconds: 2000);
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Suspend'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Suspend').last);
    // A single bounded-duration pump: long enough (500ms) for the
    // confirmation dialog's own closing transition to run to completion
    // (AnimationController values are computed from elapsed clock time,
    // so one pump with a large-enough duration is sufficient — no need
    // for repeated frames) and for the `_handleStatusChange` continuation
    // to call `provider.updateStatus` (which synchronously marks the user
    // busy and notifies before awaiting the delayed repository call), but
    // well short of the 2000ms fake repository delay.
    await tester.pump(const Duration(milliseconds: 500));

    // Targeted by key, not text -- belt-and-braces in case the dialog's
    // own button (same text/type) is still mid-transition in the tree.
    // Checked via `DangerButton.isLoading`, not `OutlinedButton.onPressed`
    // — DangerButton/PrimaryButton/SecondaryButton all swap in a no-op
    // `() {}` callback while loading (so the button still *looks*
    // pressable but silently swallows taps and shows a spinner), they
    // never actually set `onPressed` to null.
    final button = tester.widget<DangerButton>(
      find.byKey(const Key('suspend-action-2')),
    );
    expect(button.isLoading, isTrue);

    await tester.pumpAndSettle();
  });

  testWidgets(
    'A successful status update patches the UI immediately, without a full list reload',
    (tester) async {
      final repository = _FakeAdminUsersRepository()
        ..loadResult = [_user(id: 2, status: 'active')]
        ..updateResult = _user(id: 2, status: 'suspended');
      await _pumpScreen(tester, repository: repository);
      expect(repository.getUsersCallCount, 1);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Suspend'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Suspend').last);
      await tester.pumpAndSettle();

      expect(find.text('Suspended'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Reactivate'), findsOneWidget);
      // No reload -- still exactly the one initial GET.
      expect(repository.getUsersCallCount, 1);
    },
  );

  testWidgets('A successful status update shows a success SnackBar', (
    tester,
  ) async {
    final repository = _FakeAdminUsersRepository()
      ..loadResult = [_user(id: 2, status: 'active')]
      ..updateResult = _user(id: 2, status: 'suspended');
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Suspend'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Suspend').last);
    await tester.pumpAndSettle();

    expect(find.text('User suspended successfully'), findsOneWidget);
  });

  testWidgets(
    'A failed status update keeps the old status and shows the backend message',
    (tester) async {
      final repository = _FakeAdminUsersRepository()
        ..loadResult = [_user(id: 2, status: 'active')]
        ..updateError = ApiException('Server error, please retry.');
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Suspend'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Suspend').last);
      await tester.pumpAndSettle();

      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Server error, please retry.'), findsOneWidget);
    },
  );

  testWidgets('Pull-to-refresh calls the provider and reloads the list', (
    tester,
  ) async {
    final repository = _FakeAdminUsersRepository()..loadResult = [_user()];
    await _pumpScreen(tester, repository: repository);
    expect(repository.getUsersCallCount, 1);

    unawaited(
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show(),
    );
    await tester.pumpAndSettle();

    expect(repository.getUsersCallCount, 2);
  });

  testWidgets(
    'A failed refresh keeps the old list visible, not a blank screen',
    (tester) async {
      final repository = _FakeAdminUsersRepository()
        ..loadResult = [_user(id: 2, name: 'Jane Student')];
      await _pumpScreen(tester, repository: repository);
      expect(find.text('Jane Student'), findsOneWidget);

      repository.loadResult = null;
      repository.loadError = ApiException('Server error, please retry.');

      unawaited(
        tester
            .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
            .show(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Jane Student'), findsOneWidget); // old list retained
      expect(find.text('Server error, please retry.'), findsOneWidget);
    },
  );

  testWidgets('No overflow at a narrow 320-wide viewport', (tester) async {
    final repository = _FakeAdminUsersRepository()
      ..loadResult = [
        _user(
          id: 2,
          name: 'A Very Long Full Name That Might Wrap Or Overflow',
          email: 'a-very-long-email-address@example.com',
          createdAt: DateTime(2026, 7, 1),
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
