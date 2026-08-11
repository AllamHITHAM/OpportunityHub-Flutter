// Widget tests for StudentHomeScreen's notification bell + unread badge,
// in isolation with a small GoRouter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/notifications/data/notification_repository.dart';
import 'package:opportunityhub_flutter/features/student/presentation/student_home_screen.dart';
import 'package:opportunityhub_flutter/models/notification_model.dart';
import 'package:opportunityhub_flutter/models/user_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/notification_provider.dart';
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
  _FakeNotificationRepository({this.listResult = const []})
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<NotificationModel> listResult;

  @override
  Future<List<NotificationModel>> getNotifications() async => listResult;
}

NotificationModel _notification({int id = 1, bool isRead = false}) {
  return NotificationModel(
    id: id,
    userId: 1,
    title: 'Notice',
    message: 'A notification.',
    priority: 'normal',
    type: 'system',
    isRead: isRead,
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _FakeNotificationRepository notificationRepository,
}) async {
  final authProvider = AuthProvider(authRepository: _FakeAuthRepository())
    ..user = const UserModel(
      id: 1,
      name: 'Sam Student',
      email: 'sam@example.com',
      role: 'student',
      status: 'active',
    );
  final notificationProvider = NotificationProvider(
    repository: notificationRepository,
    authProvider: authProvider,
  );

  final router = GoRouter(
    initialLocation: AppRoutes.studentHome,
    routes: [
      GoRoute(
        path: AppRoutes.studentHome,
        builder: (_, _) => const StudentHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (_, _) => const Scaffold(body: Text('NOTIFICATIONS_SCREEN')),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<NotificationProvider>.value(
          value: notificationProvider,
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('The notification bell is present in the AppBar', (tester) async {
    await _pumpScreen(
      tester,
      notificationRepository: _FakeNotificationRepository(),
    );

    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
  });

  testWidgets('The badge is hidden when there is no unread notification', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      notificationRepository: _FakeNotificationRepository(
        listResult: [_notification(id: 1, isRead: true)],
      ),
    );

    final badge = tester.widget<Badge>(find.byType(Badge));
    expect(badge.isLabelVisible, isFalse);
  });

  testWidgets('The badge shows the unread count', (tester) async {
    await _pumpScreen(
      tester,
      notificationRepository: _FakeNotificationRepository(
        listResult: [
          _notification(id: 1, isRead: false),
          _notification(id: 2, isRead: false),
          _notification(id: 3, isRead: true),
        ],
      ),
    );

    final badge = tester.widget<Badge>(find.byType(Badge));
    expect(badge.isLabelVisible, isTrue);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('Tapping the bell opens the Notifications screen', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      notificationRepository: _FakeNotificationRepository(),
    );

    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pumpAndSettle();

    expect(find.text('NOTIFICATIONS_SCREEN'), findsOneWidget);
  });
}
