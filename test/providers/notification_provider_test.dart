// Direct unit tests for NotificationProvider, using a fake repository (no
// real network) and a real AuthProvider (with a fake AuthRepository) so the
// reset-on-logout listener can be exercised genuinely.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/notifications/data/notification_repository.dart';
import 'package:opportunityhub_flutter/models/notification_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/notification_provider.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  @override
  Future<String?> getSavedToken() async => null;

  @override
  Future<void> logout() async {
    // A no-op: this test only cares that AuthProvider.logout() flips
    // `isAuthenticated` to false (which it does regardless of what the
    // repository does), not about the real network/secure-storage calls
    // that would otherwise require a platform-channel binding.
  }
}

NotificationModel _notification({
  int id = 1,
  String title = 'Application shortlisted',
  bool isRead = false,
  DateTime? readAt,
}) {
  return NotificationModel(
    id: id,
    userId: 1,
    title: title,
    message: 'A notification message.',
    priority: 'normal',
    type: 'application',
    actionUrl: '/student/applications/$id',
    isRead: isRead,
    readAt: readAt,
  );
}

class _FakeNotificationRepository extends NotificationRepository {
  _FakeNotificationRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<NotificationModel> listResult = [];
  ApiException? listError;
  Object? listRuntimeError;
  Duration listDelay = Duration.zero;
  int getNotificationsCallCount = 0;

  NotificationModel? markAsReadResult;
  ApiException? markAsReadError;
  Duration markAsReadDelay = Duration.zero;
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
    if (listRuntimeError != null) throw listRuntimeError!;
    if (listError != null) throw listError!;
    return listResult;
  }

  @override
  Future<NotificationModel> markAsRead(int notificationId) async {
    markAsReadCallCount++;
    if (markAsReadDelay > Duration.zero) {
      await Future<void>.delayed(markAsReadDelay);
    }
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

void main() {
  late AuthProvider authProvider;
  late _FakeNotificationRepository repository;
  late NotificationProvider provider;

  setUp(() {
    authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    repository = _FakeNotificationRepository();
    provider = NotificationProvider(
      repository: repository,
      authProvider: authProvider,
    );
  });

  test('initial state is empty, not loading, and error-free', () {
    expect(provider.notifications, isEmpty);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.isMarkingAll, isFalse);
    expect(provider.actionErrorMessage, isNull);
    expect(provider.unreadCount, 0);
    expect(provider.hasUnread, isFalse);
  });

  test('load success populates the list', () async {
    repository.listResult = [_notification(id: 1), _notification(id: 2)];

    await provider.load();

    expect(provider.notifications, hasLength(2));
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
  });

  test('load success with an empty list clears any prior error', () async {
    repository.listResult = [];

    await provider.load();

    expect(provider.notifications, isEmpty);
    expect(provider.errorMessage, isNull);
  });

  test('load failure surfaces the error and is retryable', () async {
    repository.listError = ApiException(
      'Server error, please try again later.',
    );

    await provider.load();

    expect(provider.errorMessage, 'Server error, please try again later.');
    expect(provider.notifications, isEmpty);

    repository.listError = null;
    repository.listResult = [_notification()];
    await provider.load(forceRefresh: true);

    expect(provider.errorMessage, isNull);
    expect(provider.notifications, hasLength(1));
  });

  test('malformed data (an unexpected runtime error) never leaves the '
      'provider stuck loading, and clears the pending fetch', () async {
    repository.listRuntimeError = TypeError();

    await provider.load();

    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNotNull);
    expect(provider.errorMessage, isNot(contains('TypeError')));

    repository.listRuntimeError = null;
    repository.listResult = [_notification()];
    await provider.load();

    expect(provider.errorMessage, isNull);
    expect(provider.notifications, hasLength(1));
  });

  test(
    'concurrent duplicate loads are deduplicated into one request',
    () async {
      repository.listResult = [_notification()];

      final first = provider.load();
      final second = provider.load();
      await Future.wait([first, second]);

      expect(repository.getNotificationsCallCount, 1);
    },
  );

  test(
    'forceRefresh starts a new fetch even immediately after a load',
    () async {
      repository.listResult = [_notification()];
      await provider.load();

      repository.listResult = [_notification(), _notification(id: 2)];
      await provider.load(forceRefresh: true);

      expect(repository.getNotificationsCallCount, 2);
      expect(provider.notifications, hasLength(2));
    },
  );

  test(
    'a slower stale refresh cannot overwrite a newer forceRefresh result',
    () async {
      repository.listResult = [_notification(id: 1)];
      await provider.load();

      repository.listDelay = const Duration(milliseconds: 100);
      repository.listResult = [_notification(id: 99)];
      final staleCall = provider.load(forceRefresh: true);

      repository.listDelay = Duration.zero;
      repository.listResult = [_notification(id: 2)];
      await provider.load(forceRefresh: true);

      expect(provider.notifications.single.id, 2);

      await staleCall;

      expect(provider.notifications.single.id, 2);
    },
  );

  test('a refresh failure retains the previously loaded list', () async {
    repository.listResult = [_notification(id: 1)];
    await provider.load();
    expect(provider.notifications, hasLength(1));

    repository.listResult = [];
    repository.listError = ApiException('Server error, please retry.');
    await provider.load(forceRefresh: true);

    expect(provider.notifications, hasLength(1));
    expect(provider.errorMessage, 'Server error, please retry.');
  });

  test('unreadCount counts only unread notifications', () async {
    repository.listResult = [
      _notification(id: 1, isRead: false),
      _notification(id: 2, isRead: true),
      _notification(id: 3, isRead: false),
    ];

    await provider.load();

    expect(provider.unreadCount, 2);
    expect(provider.hasUnread, isTrue);
  });

  test('hasUnread is false when every notification is read', () async {
    repository.listResult = [
      _notification(id: 1, isRead: true),
      _notification(id: 2, isRead: true),
    ];

    await provider.load();

    expect(provider.unreadCount, 0);
    expect(provider.hasUnread, isFalse);
  });

  test('markAsRead success patches only the matching item locally', () async {
    repository.listResult = [
      _notification(id: 1, isRead: false),
      _notification(id: 2, isRead: false),
    ];
    await provider.load();

    repository.markAsReadResult = _notification(
      id: 1,
      isRead: true,
      readAt: DateTime(2026, 8, 11),
    );
    final success = await provider.markAsRead(1);

    expect(success, isTrue);
    expect(provider.notifications.firstWhere((n) => n.id == 1).isRead, isTrue);
    expect(provider.notifications.firstWhere((n) => n.id == 2).isRead, isFalse);
    expect(provider.unreadCount, 1);
  });

  test(
    'markAsRead failure leaves the item unread and surfaces an error',
    () async {
      repository.listResult = [_notification(id: 1, isRead: false)];
      await provider.load();

      repository.markAsReadError = ApiException('Notification not found');
      final success = await provider.markAsRead(1);

      expect(success, isFalse);
      expect(
        provider.notifications.firstWhere((n) => n.id == 1).isRead,
        isFalse,
      );
      expect(provider.actionErrorMessage, 'Notification not found');
    },
  );

  test('a second markAsRead call for the same notification while one is in '
      'flight triggers only one repository call', () async {
    repository.listResult = [_notification(id: 1, isRead: false)];
    repository.markAsReadDelay = const Duration(milliseconds: 50);
    repository.markAsReadResult = _notification(id: 1, isRead: true);
    await provider.load();

    final first = provider.markAsRead(1);
    final second = provider.markAsRead(1);

    final results = await Future.wait([first, second]);

    expect(repository.markAsReadCallCount, 1);
    expect(results.where((success) => success).length, 1);
    expect(results.where((success) => !success).length, 1);
  });

  test(
    'busy-state protection: isBusy is true only during an in-flight markAsRead',
    () async {
      repository.listResult = [_notification(id: 1, isRead: false)];
      repository.markAsReadDelay = const Duration(milliseconds: 50);
      repository.markAsReadResult = _notification(id: 1, isRead: true);
      await provider.load();

      expect(provider.isBusy(1), isFalse);

      final future = provider.markAsRead(1);
      expect(provider.isBusy(1), isTrue);

      await future;
      expect(provider.isBusy(1), isFalse);
    },
  );

  test('markAllAsRead success patches every unread item locally', () async {
    repository.listResult = [
      _notification(id: 1, isRead: false),
      _notification(id: 2, isRead: true),
      _notification(id: 3, isRead: false),
    ];
    await provider.load();

    repository.markAllAsReadResult = 2;
    final success = await provider.markAllAsRead();

    expect(success, isTrue);
    expect(provider.unreadCount, 0);
    expect(provider.notifications.every((n) => n.isRead), isTrue);
    // No reload occurred — the patch is entirely local.
    expect(repository.getNotificationsCallCount, 1);
  });

  test(
    'markAllAsRead failure leaves every notification state unchanged',
    () async {
      repository.listResult = [
        _notification(id: 1, isRead: false),
        _notification(id: 2, isRead: true),
      ];
      await provider.load();

      repository.markAllAsReadError = ApiException(
        'Server error, please try again later.',
      );
      final success = await provider.markAllAsRead();

      expect(success, isFalse);
      expect(provider.unreadCount, 1);
      expect(
        provider.actionErrorMessage,
        'Server error, please try again later.',
      );
    },
  );

  test(
    'a second markAllAsRead call while one is in flight triggers only one repository call',
    () async {
      repository.listResult = [_notification(id: 1, isRead: false)];
      await provider.load();
      repository.markAllAsReadResult = 1;

      final first = provider.markAllAsRead();
      final second = provider.markAllAsRead();

      final results = await Future.wait([first, second]);

      expect(repository.markAllAsReadCallCount, 1);
      expect(results.where((success) => success).length, 1);
      expect(results.where((success) => !success).length, 1);
    },
  );

  test('clearActionError clears a previously set action error', () async {
    repository.listResult = [_notification(id: 1, isRead: false)];
    await provider.load();

    repository.markAsReadError = ApiException('Notification not found');
    await provider.markAsRead(1);
    expect(provider.actionErrorMessage, isNotNull);

    provider.clearActionError();

    expect(provider.actionErrorMessage, isNull);
  });

  test('reset clears all state', () async {
    repository.listResult = [_notification(id: 1, isRead: false)];
    await provider.load();
    expect(provider.notifications, isNotEmpty);

    provider.reset();

    expect(provider.notifications, isEmpty);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.isMarkingAll, isFalse);
    expect(provider.actionErrorMessage, isNull);
  });

  test('reset clears state on logout', () async {
    repository.listResult = [_notification(id: 1, isRead: false)];
    await provider.load();
    expect(provider.notifications, isNotEmpty);

    await authProvider.logout();

    expect(provider.notifications, isEmpty);
    expect(provider.errorMessage, isNull);
  });

  test('reset invalidates a load still in flight', () async {
    repository.listResult = [_notification(id: 1)];
    repository.listDelay = const Duration(milliseconds: 50);
    final staleLoad = provider.load();

    provider.reset();
    await staleLoad;

    expect(provider.notifications, isEmpty);
  });

  test(
    'dispose removes the AuthProvider listener (no error on logout after dispose)',
    () async {
      provider.dispose();

      await expectLater(authProvider.logout(), completes);
    },
  );
}
