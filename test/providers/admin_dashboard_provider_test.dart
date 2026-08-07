// Direct unit tests for AdminDashboardProvider, using a fake repository (no
// real network) and a real AuthProvider (with a fake AuthRepository) so the
// reset-on-logout listener can be exercised genuinely. Mirrors
// organization_assessment_provider_test.dart's structure and conventions.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_dashboard_repository.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/models/admin_dashboard_stats_model.dart';
import 'package:opportunityhub_flutter/providers/admin_dashboard_provider.dart';
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

AdminDashboardStatsModel _stats({int totalUsers = 42}) {
  return AdminDashboardStatsModel(
    totalUsers: totalUsers,
    totalStudents: 30,
    totalOrganizations: 10,
    pendingOrganizations: 3,
    approvedOrganizations: 6,
    rejectedOrganizations: 1,
    totalOpportunities: 20,
    openOpportunities: 15,
    closedOpportunities: 5,
    totalApplications: 100,
    totalInterviews: 8,
  );
}

class _FakeAdminDashboardRepository extends AdminDashboardRepository {
  _FakeAdminDashboardRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  AdminDashboardStatsModel? loadResult;
  ApiException? loadError;
  Object? loadRuntimeError;
  Duration loadDelay = Duration.zero;
  int getDashboardStatsCallCount = 0;

  @override
  Future<AdminDashboardStatsModel> getDashboardStats() async {
    getDashboardStatsCallCount++;
    if (loadDelay > Duration.zero) {
      await Future<void>.delayed(loadDelay);
    }
    if (loadRuntimeError != null) throw loadRuntimeError!;
    if (loadError != null) throw loadError!;
    return loadResult!;
  }
}

void main() {
  late AuthProvider authProvider;
  late _FakeAdminDashboardRepository repository;
  late AdminDashboardProvider provider;

  setUp(() {
    authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    repository = _FakeAdminDashboardRepository();
    provider = AdminDashboardProvider(
      repository: repository,
      authProvider: authProvider,
    );
  });

  test('initial state is empty and idle', () {
    expect(provider.stats, isNull);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
  });

  test('load success populates stats and clears any error', () async {
    repository.loadResult = _stats();

    await provider.load();

    expect(provider.stats, isNotNull);
    expect(provider.stats!.totalUsers, 42);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
  });

  test('load failure surfaces the backend message and is retryable', () async {
    repository.loadError = ApiException('Account is not active');

    await provider.load();

    expect(provider.errorMessage, 'Account is not active');
    expect(provider.stats, isNull);

    repository.loadError = null;
    repository.loadResult = _stats();
    await provider.load(forceRefresh: true);

    expect(provider.errorMessage, isNull);
    expect(provider.stats, isNotNull);
  });

  test(
    'an unexpected parsing/runtime error exposes a safe, non-technical message',
    () async {
      repository.loadRuntimeError = FormatException('bad field');

      await provider.load();

      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNotNull);
      expect(provider.errorMessage, isNot(contains('FormatException')));
      expect(provider.errorMessage, isNot(contains('bad field')));
      expect(provider.errorMessage, 'Something went wrong. Please try again.');
    },
  );

  test('concurrent duplicate loads are prevented', () async {
    repository.loadResult = _stats();
    repository.loadDelay = const Duration(milliseconds: 50);

    final first = provider.load();
    final second = provider.load();
    await Future.wait([first, second]);

    expect(repository.getDashboardStatsCallCount, 1);
  });

  test('forceRefresh starts a new fetch even while unchanged', () async {
    repository.loadResult = _stats();

    await provider.load();
    await provider.load(forceRefresh: true);

    expect(repository.getDashboardStatsCallCount, 2);
  });

  test(
    'old stats are retained when a forceRefresh fails, with the error exposed',
    () async {
      repository.loadResult = _stats(totalUsers: 42);
      await provider.load();
      expect(provider.stats!.totalUsers, 42);

      repository.loadResult = null;
      repository.loadError = ApiException('Server error, please retry.');
      await provider.load(forceRefresh: true);

      expect(provider.stats, isNotNull);
      expect(provider.stats!.totalUsers, 42);
      expect(provider.errorMessage, 'Server error, please retry.');
    },
  );

  test('loading state is cleared in finally after a successful load', () async {
    repository.loadResult = _stats();

    expect(provider.isLoading, isFalse);
    final future = provider.load();
    expect(provider.isLoading, isTrue);
    await future;
    expect(provider.isLoading, isFalse);
  });

  test('loading state is cleared in finally after a failed load', () async {
    repository.loadError = ApiException('Server error.');

    expect(provider.isLoading, isFalse);
    final future = provider.load();
    expect(provider.isLoading, isTrue);
    await future;
    expect(provider.isLoading, isFalse);
  });

  test('reset clears all state', () async {
    repository.loadResult = _stats();
    await provider.load();
    expect(provider.stats, isNotNull);

    provider.reset();

    expect(provider.stats, isNull);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
  });

  test('reset clears state on logout', () async {
    repository.loadResult = _stats();
    await provider.load();
    expect(provider.stats, isNotNull);

    await authProvider.logout();

    expect(provider.stats, isNull);
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
