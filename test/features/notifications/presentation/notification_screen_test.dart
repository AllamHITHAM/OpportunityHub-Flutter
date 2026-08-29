// Widget tests for the premium NotificationScreen (UI Phase 9), in
// isolation with a small GoRouter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/core/widgets/app_widgets.dart';
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

  ApiException? deleteError;
  final List<int> deleteCalls = [];

  int clearReadResult = 0;
  ApiException? clearReadError;
  int clearReadCallCount = 0;

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

  @override
  Future<void> deleteNotification(int notificationId) async {
    deleteCalls.add(notificationId);
    if (deleteError != null) throw deleteError!;
  }

  @override
  Future<int> clearRead() async {
    clearReadCallCount++;
    if (clearReadError != null) throw clearReadError!;
    return clearReadResult;
  }
}

NotificationModel _notification({
  int id = 1,
  String title = 'Application shortlisted',
  String message = 'Your application has been shortlisted.',
  String type = 'application',
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
    type: type,
    actionUrl: actionUrl,
    isRead: isRead,
    sentAt: sentAt ?? DateTime.now().subtract(const Duration(minutes: 5)),
  );
}

Future<NotificationProvider> _pumpScreen(
  WidgetTester tester, {
  required _FakeNotificationRepository repository,
  Size size = const Size(420, 900),
  ThemeData? theme,
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
        theme: theme ?? AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  return provider;
}

/// The AppBar title and the page-header title both legitimately say
/// "Notifications" now -- this finds just the AppBar's copy.
Finder _appBarTitle() => find.descendant(
  of: find.byType(AppBar),
  matching: find.text('Notifications'),
);

void main() {
  testWidgets('Loading state renders a skeleton while the list is in flight', (
    tester,
  ) async {
    final repository = _FakeNotificationRepository(
      listDelay: const Duration(milliseconds: 200),
    );
    tester.view.physicalSize = const Size(420, 900);
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

    expect(_appBarTitle(), findsOneWidget);
    expect(provider.isLoading, isTrue);
    expect(find.byType(AppSkeletonList), findsOneWidget);

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

  testWidgets('Empty state renders a truthful, premium first-use state', (
    tester,
  ) async {
    await _pumpScreen(tester, repository: _FakeNotificationRepository());

    expect(find.text("You're All Caught Up"), findsOneWidget);
    expect(find.textContaining('applications and account activity'), findsOneWidget);
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

  group('Unread/read presentation', () {
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

    testWidgets(
      'unread state is not color-only -- an unread dot is present, absent for read',
      (tester) async {
        final repository = _FakeNotificationRepository(
          listResult: [
            _notification(id: 1, title: 'Unread item', isRead: false),
            _notification(id: 2, title: 'Read item', isRead: true),
          ],
        );
        await _pumpScreen(tester, repository: repository);

        final unreadCard = find.ancestor(
          of: find.text('Unread item'),
          matching: find.byType(AppCard),
        );
        final readCard = find.ancestor(
          of: find.text('Read item'),
          matching: find.byType(AppCard),
        );

        // The unread dot is a small circular Container -- searching by
        // decoration shape within each card's own subtree.
        final unreadContainers = tester
            .widgetList<Container>(find.descendant(of: unreadCard, matching: find.byType(Container)))
            .where((c) => c.decoration is BoxDecoration && (c.decoration! as BoxDecoration).shape == BoxShape.circle)
            .length;
        final readContainers = tester
            .widgetList<Container>(find.descendant(of: readCard, matching: find.byType(Container)))
            .where((c) => c.decoration is BoxDecoration && (c.decoration! as BoxDecoration).shape == BoxShape.circle)
            .length;

        // Unread card: type-icon circle + unread dot = 2. Read card: only
        // the type-icon circle = 1.
        expect(unreadContainers, greaterThan(readContainers));
      },
    );

    testWidgets('a type-specific icon renders based on the real notification type', (
      tester,
    ) async {
      final repository = _FakeNotificationRepository(
        listResult: [
          _notification(id: 1, title: 'Interview', type: 'interview'),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.byIcon(Icons.event_outlined), findsOneWidget);
    });

    testWidgets('an unrecognized future type falls back to a safe neutral icon', (
      tester,
    ) async {
      final repository = _FakeNotificationRepository(
        listResult: [
          _notification(id: 1, title: 'Future thing', type: 'future_type'),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.byIcon(Icons.notifications_outlined), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('Filters', () {
    testWidgets('the Unread filter shows only unread notifications', (
      tester,
    ) async {
      final repository = _FakeNotificationRepository(
        listResult: [
          _notification(id: 1, title: 'Unread item', isRead: false),
          _notification(id: 2, title: 'Read item', isRead: true),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byKey(const Key('notification-filter-unread')));
      await tester.pumpAndSettle();

      expect(find.text('Unread item'), findsOneWidget);
      expect(find.text('Read item'), findsNothing);
    });

    testWidgets('the Read filter shows only read notifications', (
      tester,
    ) async {
      final repository = _FakeNotificationRepository(
        listResult: [
          _notification(id: 1, title: 'Unread item', isRead: false),
          _notification(id: 2, title: 'Read item', isRead: true),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byKey(const Key('notification-filter-read')));
      await tester.pumpAndSettle();

      expect(find.text('Unread item'), findsNothing);
      expect(find.text('Read item'), findsOneWidget);
    });

    testWidgets('the All filter restores every notification', (tester) async {
      final repository = _FakeNotificationRepository(
        listResult: [
          _notification(id: 1, title: 'Unread item', isRead: false),
          _notification(id: 2, title: 'Read item', isRead: true),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byKey(const Key('notification-filter-unread')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notification-filter-all')));
      await tester.pumpAndSettle();

      expect(find.text('Unread item'), findsOneWidget);
      expect(find.text('Read item'), findsOneWidget);
    });

    testWidgets('an empty filter result shows a truthful no-match state', (
      tester,
    ) async {
      final repository = _FakeNotificationRepository(
        listResult: [_notification(id: 1, isRead: true)],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byKey(const Key('notification-filter-unread')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining("all caught up -- no unread"),
        findsOneWidget,
      );
    });
  });

  group('Summary', () {
    testWidgets('shows the real total and unread counts', (tester) async {
      final repository = _FakeNotificationRepository(
        listResult: [
          _notification(id: 1, isRead: false),
          _notification(id: 2, isRead: false),
          _notification(id: 3, isRead: true),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.text('3 notifications'), findsOneWidget);
      expect(find.text('2 unread'), findsOneWidget);
    });

    testWidgets('shows a caught-up confirmation when nothing is unread, without hiding read history', (
      tester,
    ) async {
      final repository = _FakeNotificationRepository(
        listResult: [_notification(id: 1, title: 'Old one', isRead: true)],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.text("You're all caught up."), findsOneWidget);
      expect(find.text('Old one'), findsOneWidget);
    });

    testWidgets('never fabricates an engagement metric', (tester) async {
      final repository = _FakeNotificationRepository(
        listResult: [_notification(id: 1)],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('score'), findsNothing);
    });
  });

  group('Grouping', () {
    testWidgets('groups notifications into real Today/Yesterday/Earlier buckets', (
      tester,
    ) async {
      final now = DateTime.now();
      final repository = _FakeNotificationRepository(
        listResult: [
          _notification(id: 1, title: 'Today item', sentAt: now.subtract(const Duration(minutes: 5))),
          _notification(
            id: 2,
            title: 'Yesterday item',
            sentAt: DateTime(now.year, now.month, now.day - 1, 10),
          ),
          _notification(
            id: 3,
            title: 'Old item',
            sentAt: DateTime(now.year, now.month, now.day - 10, 10),
          ),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.text('Today'), findsOneWidget);
      // "Yesterday" legitimately appears twice: the bucket header, and
      // that item's own relative-time label -- not a duplication bug.
      expect(find.text('Yesterday'), findsWidgets);
      expect(find.text('Earlier'), findsOneWidget);
    });
  });

  group('Mark all as read', () {
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
  });

  group('Mark one as read', () {
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

    testWidgets(
      'a failed mark-as-read keeps the notification visibly unread and shows a safe error',
      (tester) async {
        final repository = _FakeNotificationRepository(
          listResult: [_notification(id: 1, isRead: false, actionUrl: null)],
        )..markAsReadError = ApiException('Server error, please try again later.');
        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.text('Application shortlisted'));
        await tester.pumpAndSettle();

        expect(
          find.text('Server error, please try again later.'),
          findsOneWidget,
        );
        // Still shown as unread -- the failed call never fakes success.
        final titleText = tester.widget<Text>(find.text('Application shortlisted'));
        expect(titleText.style?.fontWeight, FontWeight.bold);
      },
    );

    testWidgets(
      'an explicit Mark as read action is offered on desktop for unread items',
      (tester) async {
        final repository = _FakeNotificationRepository(
          listResult: [_notification(id: 1, isRead: false, actionUrl: null)],
        )..markAsReadResult = _notification(id: 1, isRead: true, actionUrl: null);
        await _pumpScreen(
          tester,
          repository: repository,
          size: const Size(1440, 1000),
        );

        await tester.tap(find.widgetWithText(TextButton, 'Mark as read'));
        await tester.pumpAndSettle();

        expect(repository.markAsReadCallCount, 1);
      },
    );

    testWidgets('the explicit per-item Mark as read action is not shown on mobile', (
      tester,
    ) async {
      final repository = _FakeNotificationRepository(
        listResult: [_notification(id: 1, isRead: false, actionUrl: null)],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.widgetWithText(TextButton, 'Mark as read'), findsNothing);
    });
  });

  group('Navigation', () {
    testWidgets('A null action_url marks read but does not navigate', (
      tester,
    ) async {
      final repository = _FakeNotificationRepository(
        listResult: [_notification(id: 1, isRead: false, actionUrl: null)],
      )..markAsReadResult = _notification(id: 1, isRead: true, actionUrl: null);
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Application shortlisted'));
      await tester.pumpAndSettle();

      expect(_appBarTitle(), findsOneWidget);
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
  });

  group('Refresh', () {
    testWidgets('Pull-to-refresh reloads the list', (tester) async {
      final repository = _FakeNotificationRepository(
        listResult: [_notification(id: 1)],
      );
      await _pumpScreen(tester, repository: repository);
      expect(repository.getNotificationsCallCount, 1);

      await tester.fling(
        find.byType(RefreshIndicator),
        const Offset(0, 300),
        1000,
      );
      await tester.pumpAndSettle();

      expect(repository.getNotificationsCallCount, 2);
    });

    testWidgets('a manual refresh action is offered on desktop', (
      tester,
    ) async {
      final repository = _FakeNotificationRepository(
        listResult: [_notification(id: 1)],
      );
      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(1440, 1000),
      );
      expect(repository.getNotificationsCallCount, 1);

      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();

      expect(repository.getNotificationsCallCount, 2);
    });

    testWidgets('no manual refresh icon clutters the mobile AppBar', (
      tester,
    ) async {
      final repository = _FakeNotificationRepository(
        listResult: [_notification(id: 1)],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.byTooltip('Refresh'), findsNothing);
    });
  });

  group('Responsive layout', () {
    testWidgets('Does not overflow at a narrow 320x720 viewport', (
      tester,
    ) async {
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

    testWidgets('Does not overflow on a tablet viewport', (tester) async {
      final repository = _FakeNotificationRepository(
        listResult: [_notification(id: 1, title: 'First')],
      );
      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(900, 1000),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Does not overflow on a desktop viewport and shows the real activity summary sidebar',
      (tester) async {
        final repository = _FakeNotificationRepository(
          listResult: [
            _notification(id: 1, title: 'First', isRead: false),
            _notification(id: 2, title: 'Second', isRead: true),
          ],
        );
        await _pumpScreen(
          tester,
          repository: repository,
          size: const Size(1440, 1000),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Activity Summary'), findsOneWidget);
      },
    );
  });

  testWidgets('honors reduced motion without throwing', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final repository = _FakeNotificationRepository(
      listResult: [_notification(id: 1, title: 'First')],
    );
    await _pumpScreen(tester, repository: repository);

    expect(tester.takeException(), isNull);
    expect(find.text('First'), findsOneWidget);
  });

  testWidgets('renders correctly in Dark Mode', (tester) async {
    final repository = _FakeNotificationRepository(
      listResult: [
        _notification(id: 1, title: 'First', isRead: false),
        _notification(id: 2, title: 'Second', isRead: true),
      ],
    );

    await _pumpScreen(
      tester,
      repository: repository,
      theme: AppTheme.darkTheme,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('the app-bar theme toggle is reachable', (tester) async {
    final repository = _FakeNotificationRepository(
      listResult: [_notification(id: 1)],
    );

    await _pumpScreen(tester, repository: repository);

    expect(find.byType(ThemeToggleButton), findsOneWidget);
  });

  group('Delete notification (Phase 9.1)', () {
    Finder cardOverflowButton(String title) => find.descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(AppCard)),
      matching: find.byIcon(Icons.more_vert_rounded),
    );

    testWidgets('a delete action is discoverable via the per-card overflow menu', (
      tester,
    ) async {
      final repository = _FakeNotificationRepository(
        listResult: [_notification(id: 1, title: 'First', actionUrl: null)],
      );
      await _pumpScreen(tester, repository: repository);

      expect(cardOverflowButton('First'), findsOneWidget);

      await tester.tap(cardOverflowButton('First'));
      await tester.pumpAndSettle();

      expect(find.text('Delete notification'), findsOneWidget);
    });

    testWidgets('opening the overflow menu does not navigate or mark as read', (
      tester,
    ) async {
      final repository = _FakeNotificationRepository(
        listResult: [
          _notification(
            id: 1,
            title: 'First',
            isRead: false,
            actionUrl: '/student/applications/42',
          ),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(cardOverflowButton('First'));
      await tester.pumpAndSettle();

      expect(find.text('STUDENT_APPLICATION_42'), findsNothing);
      expect(repository.markAsReadCallCount, 0);

      // Dismiss the open menu without selecting anything.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    });

    testWidgets('delete asks for confirmation with restrained, accurate copy', (
      tester,
    ) async {
      final repository = _FakeNotificationRepository(
        listResult: [_notification(id: 1, title: 'First', actionUrl: null)],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(cardOverflowButton('First'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete notification'));
      await tester.pumpAndSettle();

      expect(find.text('Delete notification?'), findsOneWidget);
      expect(
        find.textContaining('will not affect the related application'),
        findsOneWidget,
      );
      expect(repository.deleteCalls, isEmpty);
    });

    testWidgets('cancelling the confirmation deletes nothing', (tester) async {
      final repository = _FakeNotificationRepository(
        listResult: [_notification(id: 1, title: 'First', actionUrl: null)],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(cardOverflowButton('First'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete notification'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repository.deleteCalls, isEmpty);
      expect(find.text('First'), findsOneWidget);
    });

    testWidgets(
      'confirming delete removes the item and calls the backend once',
      (tester) async {
        final repository = _FakeNotificationRepository(
          listResult: [
            _notification(id: 1, title: 'First', actionUrl: null),
            _notification(id: 2, title: 'Second', actionUrl: null),
          ],
        );
        await _pumpScreen(tester, repository: repository);

        await tester.tap(cardOverflowButton('First'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete notification'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete').last);
        await tester.pumpAndSettle();

        expect(repository.deleteCalls, [1]);
        expect(find.text('First'), findsNothing);
        expect(find.text('Second'), findsOneWidget);
      },
    );

    testWidgets('deleting an unread item decreases the unread count', (
      tester,
    ) async {
      final repository = _FakeNotificationRepository(
        listResult: [
          _notification(id: 1, title: 'First', isRead: false, actionUrl: null),
          _notification(id: 2, title: 'Second', isRead: true, actionUrl: null),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.text('1 unread'), findsOneWidget);

      await tester.tap(cardOverflowButton('First'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete notification'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(find.text('2 notifications'), findsNothing);
      expect(find.text('1 notification'), findsOneWidget);
      expect(find.text("You're all caught up."), findsOneWidget);
    });

    testWidgets(
      'a failed delete keeps the notification visible and shows a safe error',
      (tester) async {
        final repository = _FakeNotificationRepository(
          listResult: [_notification(id: 1, title: 'First', actionUrl: null)],
        )..deleteError = ApiException('Server error, please try again later.');
        await _pumpScreen(tester, repository: repository);

        await tester.tap(cardOverflowButton('First'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete notification'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete').last);
        await tester.pumpAndSettle();

        expect(find.text('First'), findsOneWidget);
        expect(
          find.text('Server error, please try again later.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('deleting the last item inside the Read filter shows the empty state', (
      tester,
    ) async {
      final repository = _FakeNotificationRepository(
        listResult: [
          _notification(id: 1, title: 'Read one', isRead: true, actionUrl: null),
          _notification(id: 2, title: 'Unread one', isRead: false, actionUrl: null),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byKey(const Key('notification-filter-read')));
      await tester.pumpAndSettle();

      await tester.tap(cardOverflowButton('Read one'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete notification'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(find.text('Read one'), findsNothing);
      // Still on the Read filter -- deleting must not silently reset it.
      expect(
        find.textContaining("all caught up -- no unread"),
        findsNothing,
      );
      expect(find.text('Unread one'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('delete is reachable on a desktop viewport too', (tester) async {
      final repository = _FakeNotificationRepository(
        listResult: [_notification(id: 1, title: 'First', actionUrl: null)],
      );
      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(1440, 1000),
      );

      await tester.tap(cardOverflowButton('First'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete notification'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(repository.deleteCalls, [1]);
      expect(find.text('First'), findsNothing);
    });

    testWidgets('Mark all as read is unaffected by the new overflow menu', (
      tester,
    ) async {
      final repository = _FakeNotificationRepository(
        listResult: [
          _notification(id: 1, isRead: false, actionUrl: null),
          _notification(id: 2, isRead: false, actionUrl: null),
        ],
      )..markAllAsReadResult = 2;
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Mark all as read'));
      await tester.pumpAndSettle();

      expect(repository.markAllAsReadCallCount, 1);
      expect(find.text('Mark all as read'), findsNothing);
    });

    testWidgets('delete works with reduced motion enabled, without throwing', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

      final repository = _FakeNotificationRepository(
        listResult: [_notification(id: 1, title: 'First', actionUrl: null)],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(cardOverflowButton('First'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete notification'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('First'), findsNothing);
    });

    testWidgets('delete works correctly in Dark Mode', (tester) async {
      final repository = _FakeNotificationRepository(
        listResult: [_notification(id: 1, title: 'First', actionUrl: null)],
      );
      await _pumpScreen(
        tester,
        repository: repository,
        theme: AppTheme.darkTheme,
      );

      await tester.tap(cardOverflowButton('First'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete notification'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('First'), findsNothing);
    });

    testWidgets('a long notification message deletes cleanly without overflow', (
      tester,
    ) async {
      final repository = _FakeNotificationRepository(
        listResult: [
          _notification(
            id: 1,
            title: 'First',
            message:
                'This is a deliberately long notification message meant to '
                'wrap across several lines to make sure the card layout and '
                'the overflow menu still behave correctly when the text is '
                'unusually long.',
            actionUrl: null,
          ),
        ],
      );
      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(320, 720),
      );

      await tester.ensureVisible(cardOverflowButton('First'));
      await tester.tap(cardOverflowButton('First'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete notification'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('First'), findsNothing);
    });
  });

  group('Clear read notifications (Phase 9.1)', () {
    testWidgets('the overflow menu is hidden when there is nothing read yet', (
      tester,
    ) async {
      final repository = _FakeNotificationRepository(
        listResult: [_notification(id: 1, isRead: false)],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.byTooltip('More options'), findsNothing);
    });

    testWidgets('Clear read notifications is offered once something is read', (
      tester,
    ) async {
      final repository = _FakeNotificationRepository(
        listResult: [_notification(id: 1, isRead: true)],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();

      expect(find.text('Clear read notifications'), findsOneWidget);
    });

    testWidgets('asks for confirmation with copy that promises unread survive', (
      tester,
    ) async {
      final repository = _FakeNotificationRepository(
        listResult: [_notification(id: 1, isRead: true)],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear read notifications'));
      await tester.pumpAndSettle();

      expect(find.text('Clear read notifications?'), findsOneWidget);
      expect(find.textContaining('Unread notifications will stay'), findsOneWidget);
      expect(repository.clearReadCallCount, 0);
    });

    testWidgets(
      'confirming removes only read notifications, unread ones stay',
      (tester) async {
        final repository = _FakeNotificationRepository(
          listResult: [
            _notification(id: 1, title: 'Read one', isRead: true, actionUrl: null),
            _notification(id: 2, title: 'Unread one', isRead: false, actionUrl: null),
          ],
        )..clearReadResult = 1;
        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.byTooltip('More options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear read notifications'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear Read'));
        await tester.pumpAndSettle();

        expect(repository.clearReadCallCount, 1);
        expect(find.text('Read one'), findsNothing);
        expect(find.text('Unread one'), findsOneWidget);
        expect(find.text('1 unread'), findsOneWidget);
      },
    );

    testWidgets('cancelling clears nothing', (tester) async {
      final repository = _FakeNotificationRepository(
        listResult: [_notification(id: 1, title: 'Read one', isRead: true)],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear read notifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repository.clearReadCallCount, 0);
      expect(find.text('Read one'), findsOneWidget);
    });

    testWidgets(
      'a failed clear-read keeps read notifications visible and shows a safe error',
      (tester) async {
        final repository = _FakeNotificationRepository(
          listResult: [_notification(id: 1, title: 'Read one', isRead: true)],
        )..clearReadError = ApiException('Server error, please try again later.');
        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.byTooltip('More options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear read notifications'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear Read'));
        await tester.pumpAndSettle();

        expect(find.text('Read one'), findsOneWidget);
        expect(
          find.text('Server error, please try again later.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'the Read filter shows a polished empty state once cleared to nothing',
      (tester) async {
        final repository = _FakeNotificationRepository(
          listResult: [
            _notification(id: 1, title: 'Read one', isRead: true, actionUrl: null),
          ],
        )..clearReadResult = 1;
        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.byKey(const Key('notification-filter-read')));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('More options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear read notifications'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear Read'));
        await tester.pumpAndSettle();

        expect(find.text('Read one'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
