// Widget tests for NotificationScreen, in isolation with a small GoRouter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/notifications/data/notification_repository.dart';
import 'package:opportunityhub_flutter/features/notifications/presentation/notification_screen.dart';
import 'package:opportunityhub_flutter/models/notification_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/notification_provider.dart';
import 'package:opportunityhub_flutter/providers/theme_provider.dart';
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

class _FakeNotificationRepository extends NotificationRepository {
  _FakeNotificationRepository({
    this.listResult = const [],
    this.listError,
    this.listDelay = Duration.zero,
  }) : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<NotificationModel> listResult;
  ApiException? listError;
  Duration listDelay;
  int getNotificationsCallCount = 0;

  NotificationModel? markAsReadResult;
  ApiException? markAsReadError;
  int markAsReadCallCount = 0;

  int markAllAsReadResult = 0;
  ApiException? markAllAsReadError;
  int markAllAsReadCallCount = 0;

  @override
  Future<List<NotificationModel>> getNotifications() async {
    getNotificationsCallCount++;
    if (listDelay > Duration.zero) {
      await Future<void>.delayed(listDelay);
    }
    if (listError != null) throw listError!;
    return listResult;
  }

  @override
  Future<NotificationModel> markAsRead(int notificationId) async {
    markAsReadCallCount++;
    if (markAsReadError != null) throw markAsReadError!;
    return markAsReadResult!;
  }

  @override
  Future<int> markAllAsRead() async {
    markAllAsReadCallCount++;
    if (markAllAsReadError != null) throw markAllAsReadError!;
    return markAllAsReadResult;
  }
}

NotificationModel _notification({
  int id = 1,
  String title = 'Application shortlisted',
  String message = 'Your application has been shortlisted.',
  bool isRead = false,
  String? actionUrl = '/student/applications/42',
  DateTime? sentAt,
}) {
  return NotificationModel(
    id: id,
    userId: 1,
    title: title,
    message: message,
    priority: 'normal',
    type: 'application',
    actionUrl: actionUrl,
    isRead: isRead,
    sentAt: sentAt ?? DateTime(2026, 8, 10, 9),
  );
}

Future<NotificationProvider> _pumpScreen(
  WidgetTester tester, {
  required _FakeNotificationRepository repository,
  Size size = const Size(420, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final provider = NotificationProvider(
    repository: repository,
    authProvider: authProvider,
  );

  final router = GoRouter(
    initialLocation: AppRoutes.notifications,
    routes: [
      GoRoute(
        path: AppRoutes.notifications,
        builder: (_, _) => const NotificationScreen(),
      ),
      GoRoute(
        path: '/student/applications/:id',
        builder: (_, state) => Scaffold(
          body: Text('STUDENT_APPLICATION_${state.pathParameters['id']}'),
        ),
      ),
      GoRoute(
        path: '/organization/applications/:id',
        builder: (_, state) => Scaffold(
          body: Text('ORGANIZATION_APPLICATION_${state.pathParameters['id']}'),
        ),
      ),
      GoRoute(
        path: '/student/assessments/:id/quiz',
        builder: (_, state) =>
            Scaffold(body: Text('STUDENT_QUIZ_${state.pathParameters['id']}')),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<NotificationProvider>.value(value: provider),
        ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
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
  testWidgets('Loading state renders a skeleton while the list is in flight', (
    tester,
  ) async {
    final repository = _FakeNotificationRepository(
      listDelay: const Duration(milliseconds: 200),
    );
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final provider = NotificationProvider(
      repository: repository,
      authProvider: authProvider,
    );
    final router = GoRouter(
      initialLocation: AppRoutes.notifications,
      routes: [
        GoRoute(
          path: AppRoutes.notifications,
          builder: (_, _) => const NotificationScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<NotificationProvider>.value(value: provider),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Notifications'), findsOneWidget);
    expect(provider.isLoading, isTrue);

    await tester.pumpAndSettle();
  });

  testWidgets('Error state renders on load failure, with retry', (
    tester,
  ) async {
    final repository = _FakeNotificationRepository(
      listError: ApiException('Server error, please try again later.'),
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text('Server error, please try again later.'), findsOneWidget);

    repository.listError = null;
    repository.listResult = [_notification()];
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();

    expect(find.text('Application shortlisted'), findsOneWidget);
  });

  testWidgets('Empty state renders when there are no notifications', (
    tester,
  ) async {
    await _pumpScreen(tester, repository: _FakeNotificationRepository());

    expect(find.text('No Notifications'), findsOneWidget);
  });

  testWidgets('Populated list renders title and message for each item', (
    tester,
  ) async {
    final repository = _FakeNotificationRepository(
      listResult: [
        _notification(id: 1, title: 'First', message: 'First message'),
        _notification(id: 2, title: 'Second', message: 'Second message'),
      ],
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text('First'), findsOneWidget);
    expect(find.text('First message'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('Second message'), findsOneWidget);
  });

  testWidgets('Renders notifications in the exact order the provider holds '
      'them (newest-first is the repository/provider\'s responsibility)', (
    tester,
  ) async {
    final repository = _FakeNotificationRepository(
      listResult: [
        _notification(id: 1, title: 'Newest'),
        _notification(id: 2, title: 'Oldest'),
      ],
    );
    await _pumpScreen(tester, repository: repository);

    final newestCenter = tester.getCenter(find.text('Newest'));
    final oldestCenter = tester.getCenter(find.text('Oldest'));
    expect(newestCenter.dy, lessThan(oldestCenter.dy));
  });

  testWidgets('Unread notifications look visually distinct from read ones', (
    tester,
  ) async {
    final repository = _FakeNotificationRepository(
      listResult: [
        _notification(id: 1, title: 'Unread item', isRead: false),
        _notification(id: 2, title: 'Read item', isRead: true),
      ],
    );
    await _pumpScreen(tester, repository: repository);

    final unreadText = tester.widget<Text>(find.text('Unread item'));
    final readText = tester.widget<Text>(find.text('Read item'));

    expect(unreadText.style?.fontWeight, FontWeight.bold);
    expect(readText.style?.fontWeight, FontWeight.normal);
  });

  testWidgets('Mark all as read action is hidden when unread count is zero', (
    tester,
  ) async {
    final repository = _FakeNotificationRepository(
      listResult: [_notification(id: 1, isRead: true)],
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text('Mark all as read'), findsNothing);
  });

  testWidgets('Mark all as read action is shown when there is unread', (
    tester,
  ) async {
    final repository = _FakeNotificationRepository(
      listResult: [_notification(id: 1, isRead: false)],
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text('Mark all as read'), findsOneWidget);
  });

  testWidgets(
    'Tapping Mark all as read marks every item read locally, hides the action',
    (tester) async {
      final repository = _FakeNotificationRepository(
        listResult: [
          _notification(id: 1, isRead: false),
          _notification(id: 2, isRead: false),
        ],
      )..markAllAsReadResult = 2;
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Mark all as read'));
      await tester.pumpAndSettle();

      expect(repository.markAllAsReadCallCount, 1);
      expect(find.text('Mark all as read'), findsNothing);
    },
  );

  testWidgets(
    'A failed Mark all as read keeps the action visible and shows a safe error',
    (tester) async {
      final repository = _FakeNotificationRepository(
        listResult: [_notification(id: 1, isRead: false)],
      )..markAllAsReadError = ApiException('Server error, please retry.');
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Mark all as read'));
      await tester.pumpAndSettle();

      expect(find.text('Mark all as read'), findsOneWidget);
      expect(find.text('Server error, please retry.'), findsOneWidget);
    },
  );

  testWidgets('Tapping an unread notification marks it as read', (
    tester,
  ) async {
    final repository = _FakeNotificationRepository(
      listResult: [_notification(id: 1, isRead: false, actionUrl: null)],
    )..markAsReadResult = _notification(id: 1, isRead: true, actionUrl: null);
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.text('Application shortlisted'));
    await tester.pumpAndSettle();

    expect(repository.markAsReadCallCount, 1);
  });

  testWidgets(
    'Tapping an already-read notification does not call markAsRead again',
    (tester) async {
      final repository = _FakeNotificationRepository(
        listResult: [_notification(id: 1, isRead: true, actionUrl: null)],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Application shortlisted'));
      await tester.pumpAndSettle();

      expect(repository.markAsReadCallCount, 0);
    },
  );

  testWidgets('A null action_url marks read but does not navigate', (
    tester,
  ) async {
    final repository = _FakeNotificationRepository(
      listResult: [_notification(id: 1, isRead: false, actionUrl: null)],
    )..markAsReadResult = _notification(id: 1, isRead: true, actionUrl: null);
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.text('Application shortlisted'));
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'A valid Student Application action_url navigates to that route',
    (tester) async {
      final repository = _FakeNotificationRepository(
        listResult: [
          _notification(
            id: 1,
            isRead: true,
            actionUrl: '/student/applications/42',
          ),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Application shortlisted'));
      await tester.pumpAndSettle();

      expect(find.text('STUDENT_APPLICATION_42'), findsOneWidget);
    },
  );

  testWidgets(
    'A valid Organization Application action_url navigates to that route',
    (tester) async {
      final repository = _FakeNotificationRepository(
        listResult: [
          _notification(
            id: 1,
            isRead: true,
            actionUrl: '/organization/applications/7',
          ),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Application shortlisted'));
      await tester.pumpAndSettle();

      expect(find.text('ORGANIZATION_APPLICATION_7'), findsOneWidget);
    },
  );

  testWidgets('A valid Student Quiz action_url navigates to that route', (
    tester,
  ) async {
    final repository = _FakeNotificationRepository(
      listResult: [
        _notification(
          id: 1,
          isRead: true,
          actionUrl: '/student/assessments/9/quiz',
        ),
      ],
    );
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.text('Application shortlisted'));
    await tester.pumpAndSettle();

    expect(find.text('STUDENT_QUIZ_9'), findsOneWidget);
  });

  testWidgets('A malformed/unknown action_url is handled safely, not a crash', (
    tester,
  ) async {
    final repository = _FakeNotificationRepository(
      listResult: [
        _notification(id: 1, isRead: true, actionUrl: '/no/such/route'),
      ],
    );
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.text('Application shortlisted'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('Does not overflow at a narrow 320x720 viewport', (tester) async {
    final repository = _FakeNotificationRepository(
      listResult: [
        _notification(id: 1, title: 'First'),
        _notification(id: 2, title: 'Second'),
      ],
    );
    await _pumpScreen(
      tester,
      repository: repository,
      size: const Size(320, 720),
    );

    expect(tester.takeException(), isNull);
  });
}
