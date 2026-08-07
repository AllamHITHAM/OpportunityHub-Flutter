// Direct unit tests for AdminUsersProvider, using a fake repository (no
// real network) and a real AuthProvider (with a fake AuthRepository) so
// the reset-on-logout listener can be exercised genuinely. Mirrors
// admin_dashboard_provider_test.dart's structure and conventions.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_users_repository.dart';
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

  @override
  Future<void> logout() async {
    // A no-op: this test only cares that AuthProvider.logout() flips
    // `isAuthenticated` to false (which it does regardless of what the
    // repository does), not about the real network/secure-storage calls
    // that would otherwise require a platform-channel binding.
  }
}

UserModel _user({
  int id = 1,
  String name = 'Jane Student',
  String status = 'active',
}) {
  return UserModel(
    id: id,
    name: name,
    email: 'user$id@example.com',
    role: 'student',
    status: status,
  );
}

class _FakeAdminUsersRepository extends AdminUsersRepository {
  _FakeAdminUsersRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<UserModel>? loadResult;
  ApiException? loadError;
  Object? loadRuntimeError;
  Duration loadDelay = Duration.zero;
  int getUsersCallCount = 0;

  UserModel? updateResult;
  ApiException? updateError;
  Object? updateRuntimeError;
  Duration updateDelay = Duration.zero;
  int updateStatusCallCount = 0;
  int? lastUpdatedUserId;
  String? lastUpdatedStatus;

  @override
  Future<List<UserModel>> getUsers() async {
    getUsersCallCount++;
    // Captured immediately, like a real request's response would be
    // determined by what the server had at request time — not whichever
    // fields happen to be set by the time a later `await` resumes. This
    // lets a test simulate two genuinely different in-flight responses.
    final result = loadResult ?? [];
    final runtimeError = loadRuntimeError;
    final error = loadError;
    if (loadDelay > Duration.zero) {
      await Future<void>.delayed(loadDelay);
    }
    if (runtimeError != null) throw runtimeError;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<UserModel> updateUserStatus({
    required int userId,
    required String status,
  }) async {
    updateStatusCallCount++;
    lastUpdatedUserId = userId;
    lastUpdatedStatus = status;
    if (updateDelay > Duration.zero) {
      await Future<void>.delayed(updateDelay);
    }
    if (updateRuntimeError != null) throw updateRuntimeError!;
    if (updateError != null) throw updateError!;
    return updateResult!;
  }
}

void main() {
  late AuthProvider authProvider;
  late _FakeAdminUsersRepository repository;
  late AdminUsersProvider provider;

  setUp(() {
    authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    repository = _FakeAdminUsersRepository();
    provider = AdminUsersProvider(
      repository: repository,
      authProvider: authProvider,
    );
  });

  test('initial state is empty and idle', () {
    expect(provider.users, isEmpty);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.actionErrorMessage, isNull);
    expect(provider.busyUserIds, isEmpty);
  });

  test('load success populates the list', () async {
    repository.loadResult = [_user(id: 1), _user(id: 2)];

    await provider.load();

    expect(provider.users, hasLength(2));
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
  });

  test('an empty list is represented correctly, not as an error', () async {
    await provider.load();

    expect(provider.users, isEmpty);
    expect(provider.errorMessage, isNull);
  });

  test('load failure surfaces the error and is retryable', () async {
    repository.loadError = ApiException(
      'Server error, please try again later.',
    );

    await provider.load();

    expect(provider.errorMessage, 'Server error, please try again later.');
    expect(provider.users, isEmpty);

    repository.loadError = null;
    repository.loadResult = [_user()];
    await provider.load(forceRefresh: true);

    expect(provider.errorMessage, isNull);
    expect(provider.users, hasLength(1));
  });

  test('malformed list data never leaves the provider stuck loading', () async {
    repository.loadRuntimeError = TypeError();

    await provider.load();

    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNotNull);
    expect(provider.errorMessage, isNot(contains('TypeError')));
  });

  test(
    'malformed repository data (the real FormatException AdminUsersRepository '
    'throws for an invalid user) never enters provider.users',
    () async {
      // FormatException is what AdminUsersRepository._parseAdminUser
      // actually throws for a malformed successful response (e.g. a
      // non-int id) — this proves the provider's generic catch handles
      // that specific exception safely and never lets bad data through,
      // not just a generic runtime error.
      repository.loadRuntimeError = FormatException('User "id" is not an int');

      await provider.load();

      expect(provider.users, isEmpty);
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, 'Something went wrong. Please try again.');
      expect(provider.errorMessage, isNot(contains('FormatException')));
    },
  );

  test(
    'a malformed forceRefresh never overwrites a previously-good list',
    () async {
      repository.loadResult = [_user(id: 1)];
      await provider.load();
      expect(provider.users, hasLength(1));

      repository.loadResult = null;
      repository.loadRuntimeError = FormatException('bad field');
      await provider.load(forceRefresh: true);

      expect(provider.users, hasLength(1));
      expect(provider.errorMessage, 'Something went wrong. Please try again.');
    },
  );

  test('forceRefresh starts a new fetch even while unchanged', () async {
    await provider.load();
    await provider.load(forceRefresh: true);

    expect(repository.getUsersCallCount, 2);
  });

  test(
    'a stale response from a slower first load never overwrites a faster '
    'forceRefresh — the newer request always wins, regardless of arrival order',
    () async {
      repository.loadResult = [_user(id: 1, name: 'Stale')];
      repository.loadDelay = const Duration(milliseconds: 50);
      final firstLoad = provider.load();

      repository.loadResult = [_user(id: 2, name: 'Fresh')];
      repository.loadDelay = const Duration(milliseconds: 5);
      await provider.load(forceRefresh: true);

      // The fast forceRefresh has already resolved and populated the list.
      expect(provider.users, hasLength(1));
      expect(provider.users.single.name, 'Fresh');
      expect(provider.isLoading, isFalse);

      // The slow first request is still in flight and, once it resolves,
      // must not clobber the newer result with its now-stale response.
      await firstLoad;

      expect(repository.getUsersCallCount, 2);
      expect(provider.users, hasLength(1));
      expect(provider.users.single.name, 'Fresh');
      expect(provider.isLoading, isFalse);
    },
  );

  test('concurrent duplicate list loads are prevented', () async {
    repository.loadResult = [_user()];
    repository.loadDelay = const Duration(milliseconds: 50);

    final first = provider.load();
    final second = provider.load();
    await Future.wait([first, second]);

    expect(repository.getUsersCallCount, 1);
  });

  test(
    'old list is retained when a forceRefresh fails, with the error exposed',
    () async {
      repository.loadResult = [_user(id: 1)];
      await provider.load();
      expect(provider.users, hasLength(1));

      repository.loadResult = null;
      repository.loadError = ApiException('Server error, please retry.');
      await provider.load(forceRefresh: true);

      expect(provider.users, hasLength(1));
      expect(provider.errorMessage, 'Server error, please retry.');
    },
  );

  test('updateStatus success patches the matching user in place', () async {
    repository.loadResult = [
      _user(id: 1, name: 'Jane Student', status: 'active'),
      _user(id: 2, name: 'John Org', status: 'active'),
    ];
    await provider.load();

    repository.updateResult = _user(
      id: 1,
      name: 'Jane Student',
      status: 'suspended',
    );
    final success = await provider.updateStatus(userId: 1, status: 'suspended');

    expect(success, isTrue);
    expect(provider.users.firstWhere((u) => u.id == 1).status, 'suspended');
    // The other user is untouched.
    expect(provider.users.firstWhere((u) => u.id == 2).status, 'active');
  });

  test('suspend calls the repository with status=suspended', () async {
    repository.loadResult = [_user(id: 1, status: 'active')];
    await provider.load();
    repository.updateResult = _user(id: 1, status: 'suspended');

    await provider.updateStatus(userId: 1, status: 'suspended');

    expect(repository.lastUpdatedUserId, 1);
    expect(repository.lastUpdatedStatus, 'suspended');
  });

  test('reactivate calls the repository with status=active', () async {
    repository.loadResult = [_user(id: 1, status: 'suspended')];
    await provider.load();
    repository.updateResult = _user(id: 1, status: 'active');

    await provider.updateStatus(userId: 1, status: 'active');

    expect(repository.lastUpdatedUserId, 1);
    expect(repository.lastUpdatedStatus, 'active');
  });

  test('a failed update retains the old user state', () async {
    repository.loadResult = [_user(id: 1, status: 'active')];
    await provider.load();

    repository.updateError = ApiException(
      'You cannot change your own account status',
      statusCode: 403,
    );
    final success = await provider.updateStatus(userId: 1, status: 'suspended');

    expect(success, isFalse);
    expect(provider.users.single.status, 'active');
    expect(
      provider.actionErrorMessage,
      'You cannot change your own account status',
    );
  });

  test(
    'an unexpected update failure exposes a safe, non-technical message',
    () async {
      repository.loadResult = [_user(id: 1, status: 'active')];
      await provider.load();

      repository.updateRuntimeError = TypeError();
      await provider.updateStatus(userId: 1, status: 'suspended');

      expect(provider.actionErrorMessage, isNotNull);
      expect(provider.actionErrorMessage, isNot(contains('TypeError')));
      expect(
        provider.actionErrorMessage,
        'Something went wrong. Please try again.',
      );
      expect(provider.users.single.status, 'active');
    },
  );

  test(
    'a second status update for the same user while one is in flight is blocked (only one repository call)',
    () async {
      repository.loadResult = [_user(id: 1, status: 'active')];
      repository.updateDelay = const Duration(milliseconds: 50);
      repository.updateResult = _user(id: 1, status: 'suspended');
      await provider.load();

      final first = provider.updateStatus(userId: 1, status: 'suspended');
      final second = provider.updateStatus(userId: 1, status: 'suspended');

      final results = await Future.wait([first, second]);

      expect(repository.updateStatusCallCount, 1);
      expect(results.where((success) => success).length, 1);
      expect(results.where((success) => !success).length, 1);
    },
  );

  test('busy ID is removed in finally after a successful update', () async {
    repository.loadResult = [_user(id: 1, status: 'active')];
    repository.updateResult = _user(id: 1, status: 'suspended');
    await provider.load();

    expect(provider.isBusy(1), isFalse);
    final future = provider.updateStatus(userId: 1, status: 'suspended');
    expect(provider.isBusy(1), isTrue);
    await future;
    expect(provider.isBusy(1), isFalse);
  });

  test('busy ID is removed in finally after a failed update', () async {
    repository.loadResult = [_user(id: 1, status: 'active')];
    repository.updateError = ApiException('Server error.');
    await provider.load();

    await provider.updateStatus(userId: 1, status: 'suspended');

    expect(provider.isBusy(1), isFalse);
  });

  test('different users can update independently at the same time', () async {
    repository.loadResult = [
      _user(id: 1, status: 'active'),
      _user(id: 2, status: 'active'),
    ];
    repository.updateDelay = const Duration(milliseconds: 50);
    repository.updateResult = _user(id: 1, status: 'suspended');
    await provider.load();

    final firstUpdate = provider.updateStatus(userId: 1, status: 'suspended');
    expect(provider.isBusy(1), isTrue);
    expect(provider.isBusy(2), isFalse);

    final secondUpdate = provider.updateStatus(userId: 2, status: 'suspended');
    expect(provider.isBusy(2), isTrue);

    final results = await Future.wait([firstUpdate, secondUpdate]);

    expect(repository.updateStatusCallCount, 2);
    expect(results, [true, true]);
  });

  test('clearActionError clears the action error message', () async {
    repository.loadResult = [_user(id: 1, status: 'active')];
    repository.updateError = ApiException('Server error.');
    await provider.load();
    await provider.updateStatus(userId: 1, status: 'suspended');
    expect(provider.actionErrorMessage, isNotNull);

    provider.clearActionError();

    expect(provider.actionErrorMessage, isNull);
  });

  test('reset clears all state', () async {
    repository.loadResult = [_user(id: 1)];
    await provider.load();
    expect(provider.users, isNotEmpty);

    provider.reset();

    expect(provider.users, isEmpty);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.actionErrorMessage, isNull);
    expect(provider.busyUserIds, isEmpty);
  });

  test('reset clears state on logout', () async {
    repository.loadResult = [_user(id: 1)];
    await provider.load();
    expect(provider.users, isNotEmpty);

    await authProvider.logout();

    expect(provider.users, isEmpty);
    expect(provider.errorMessage, isNull);
    expect(provider.isLoading, isFalse);
  });

  test(
    'dispose removes the AuthProvider listener (no error on logout after dispose)',
    () async {
      provider.dispose();

      // Should complete cleanly even though the provider is disposed — the
      // listener was correctly removed, so AuthProvider's own
      // notifyListeners() never tries to call back into a disposed
      // ChangeNotifier (which would throw "used after being disposed").
      await expectLater(authProvider.logout(), completes);
    },
  );
}
