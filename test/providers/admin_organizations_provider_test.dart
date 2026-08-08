// Direct unit tests for AdminOrganizationsProvider, using a fake repository
// (no real network) and a real AuthProvider (with a fake AuthRepository) so
// the reset-on-logout listener can be exercised genuinely. Mirrors
// admin_users_provider_test.dart's and
// organization_applications_provider_test.dart's structure and conventions.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_organizations_repository.dart';
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

  @override
  Future<void> logout() async {
    // A no-op: this test only cares that AuthProvider.logout() flips
    // `isAuthenticated` to false (which it does regardless of what the
    // repository does), not about the real network/secure-storage calls
    // that would otherwise require a platform-channel binding.
  }
}

OrganizationProfileModel _organization({
  int id = 1,
  String organizationName = 'Acme Corp',
  String approvalStatus = 'pending',
}) {
  return OrganizationProfileModel(
    id: id,
    organizationName: organizationName,
    organizationType: 'company',
    approvalStatus: approvalStatus,
    user: UserModel(
      id: id + 100,
      name: '$organizationName Contact',
      email: 'org$id@example.com',
      role: 'organization',
      status: 'active',
    ),
  );
}

class _FakeAdminOrganizationsRepository extends AdminOrganizationsRepository {
  _FakeAdminOrganizationsRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<OrganizationProfileModel>? loadResult;
  ApiException? loadError;
  Object? loadRuntimeError;
  Duration loadDelay = Duration.zero;
  int getOrganizationsCallCount = 0;

  /// Per-organization overrides — when set for a given ID, take priority
  /// over the shared defaults below. Lets a test give two different
  /// organizations two different results and/or delays, to exercise the
  /// stale-response-must-not-win scenario, exactly like
  /// organization_applications_provider_test.dart's
  /// resultsByOpportunity/delaysByOpportunity.
  Map<int, OrganizationProfileModel>? resultsByOrganization;
  Map<int, Duration>? delaysByOrganization;
  ApiException? detailsError;
  Object? detailsRuntimeError;
  int getOrganizationCallCount = 0;
  final List<int> requestedOrganizationIds = [];

  OrganizationProfileModel? actionResult;
  ApiException? actionError;
  Object? actionRuntimeError;
  Duration actionDelay = Duration.zero;
  int approveCallCount = 0;
  int rejectCallCount = 0;

  @override
  Future<List<OrganizationProfileModel>> getOrganizations() async {
    getOrganizationsCallCount++;
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
  Future<OrganizationProfileModel> getOrganization(int organizationId) async {
    getOrganizationCallCount++;
    requestedOrganizationIds.add(organizationId);
    final result = resultsByOrganization?[organizationId];
    final delay = delaysByOrganization?[organizationId] ?? Duration.zero;
    final runtimeError = detailsRuntimeError;
    final error = detailsError;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (runtimeError != null) throw runtimeError;
    if (error != null) throw error;
    return result!;
  }

  @override
  Future<OrganizationProfileModel> approveOrganization(
    int organizationId,
  ) async {
    approveCallCount++;
    return _performAction();
  }

  @override
  Future<OrganizationProfileModel> rejectOrganization(
    int organizationId,
  ) async {
    rejectCallCount++;
    return _performAction();
  }

  Future<OrganizationProfileModel> _performAction() async {
    if (actionDelay > Duration.zero) {
      await Future<void>.delayed(actionDelay);
    }
    if (actionRuntimeError != null) throw actionRuntimeError!;
    if (actionError != null) throw actionError!;
    return actionResult!;
  }
}

void main() {
  late AuthProvider authProvider;
  late _FakeAdminOrganizationsRepository repository;
  late AdminOrganizationsProvider provider;

  setUp(() {
    authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    repository = _FakeAdminOrganizationsRepository();
    provider = AdminOrganizationsProvider(
      repository: repository,
      authProvider: authProvider,
    );
  });

  test('initial state is empty and idle', () {
    expect(provider.organizations, isEmpty);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.selectedOrganization, isNull);
    expect(provider.isLoadingDetails, isFalse);
    expect(provider.detailsErrorMessage, isNull);
    expect(provider.actionErrorMessage, isNull);
    expect(provider.busyOrganizationIds, isEmpty);
  });

  group('load', () {
    test('success populates the list', () async {
      repository.loadResult = [_organization(id: 1), _organization(id: 2)];

      await provider.load();

      expect(provider.organizations, hasLength(2));
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test('an empty list is represented correctly, not as an error', () async {
      await provider.load();

      expect(provider.organizations, isEmpty);
      expect(provider.errorMessage, isNull);
    });

    test('failure surfaces the error and is retryable', () async {
      repository.loadError = ApiException(
        'Server error, please try again later.',
      );

      await provider.load();

      expect(provider.errorMessage, 'Server error, please try again later.');
      expect(provider.organizations, isEmpty);

      repository.loadError = null;
      repository.loadResult = [_organization()];
      await provider.load(forceRefresh: true);

      expect(provider.errorMessage, isNull);
      expect(provider.organizations, hasLength(1));
    });

    test('malformed repository data (the real FormatException '
        'AdminOrganizationsRepository throws for an invalid organization) '
        'never enters provider.organizations', () async {
      repository.loadRuntimeError = FormatException(
        'Organization "id" is not an int',
      );

      await provider.load();

      expect(provider.organizations, isEmpty);
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, 'Something went wrong. Please try again.');
      expect(provider.errorMessage, isNot(contains('FormatException')));
    });

    test('duplicate concurrent loads are deduplicated', () async {
      repository.loadResult = [_organization()];
      repository.loadDelay = const Duration(milliseconds: 50);

      final first = provider.load();
      final second = provider.load();
      await Future.wait([first, second]);

      expect(repository.getOrganizationsCallCount, 1);
    });

    test('forceRefresh starts a new fetch even while unchanged', () async {
      await provider.load();
      await provider.load(forceRefresh: true);

      expect(repository.getOrganizationsCallCount, 2);
    });

    test('a stale response from a slower first load never overwrites a faster '
        'forceRefresh — the newer request always wins, regardless of arrival '
        'order', () async {
      repository.loadResult = [_organization(id: 1, organizationName: 'Stale')];
      repository.loadDelay = const Duration(milliseconds: 50);
      final firstLoad = provider.load();

      repository.loadResult = [_organization(id: 2, organizationName: 'Fresh')];
      repository.loadDelay = const Duration(milliseconds: 5);
      await provider.load(forceRefresh: true);

      expect(provider.organizations, hasLength(1));
      expect(provider.organizations.single.organizationName, 'Fresh');
      expect(provider.isLoading, isFalse);

      await firstLoad;

      expect(repository.getOrganizationsCallCount, 2);
      expect(provider.organizations, hasLength(1));
      expect(provider.organizations.single.organizationName, 'Fresh');
      expect(provider.isLoading, isFalse);
    });

    test(
      'a malformed forceRefresh never overwrites a previously-good list',
      () async {
        repository.loadResult = [_organization(id: 1)];
        await provider.load();
        expect(provider.organizations, hasLength(1));

        repository.loadResult = null;
        repository.loadRuntimeError = FormatException('bad field');
        await provider.load(forceRefresh: true);

        expect(provider.organizations, hasLength(1));
        expect(
          provider.errorMessage,
          'Something went wrong. Please try again.',
        );
      },
    );
  });

  group('loadDetails', () {
    test('success populates selectedOrganization', () async {
      final organization = _organization(id: 5);
      repository.resultsByOrganization = {5: organization};

      await provider.loadDetails(5);

      expect(provider.selectedOrganization?.id, 5);
      expect(provider.isLoadingDetails, isFalse);
      expect(provider.detailsErrorMessage, isNull);
    });

    test(
      'failure surfaces the error and clears selectedOrganization',
      () async {
        repository.detailsError = ApiException(
          'Organization not found.',
          statusCode: 404,
        );

        await provider.loadDetails(999);

        expect(provider.detailsErrorMessage, 'Organization not found.');
        expect(provider.selectedOrganization, isNull);
      },
    );

    test(
      'malformed repository data never enters provider.selectedOrganization',
      () async {
        repository.detailsRuntimeError = FormatException(
          'Organization "id" is not an int',
        );

        await provider.loadDetails(5);

        expect(provider.selectedOrganization, isNull);
        expect(
          provider.detailsErrorMessage,
          'Something went wrong. Please try again.',
        );
        expect(
          provider.detailsErrorMessage,
          isNot(contains('FormatException')),
        );
      },
    );

    test(
      'duplicate concurrent detail loads for the same ID are deduplicated',
      () async {
        repository.resultsByOrganization = {5: _organization(id: 5)};
        repository.delaysByOrganization = {5: const Duration(milliseconds: 50)};

        final first = provider.loadDetails(5);
        final second = provider.loadDetails(5);
        await Future.wait([first, second]);

        expect(repository.getOrganizationCallCount, 1);
      },
    );

    test('a slower stale response for organization 5 cannot overwrite the '
        'newer organization 9 details', () async {
      repository.resultsByOrganization = {
        5: _organization(id: 5, organizationName: 'Slow Org'),
        9: _organization(id: 9, organizationName: 'Fast Org'),
      };
      repository.delaysByOrganization = {
        5: const Duration(milliseconds: 50),
        9: Duration.zero,
      };

      final staleCall = provider.loadDetails(5);
      await provider.loadDetails(9, forceRefresh: true);

      expect(provider.selectedOrganization?.id, 9);

      // Let the slow, now-stale organization-5 response resolve.
      await staleCall;

      expect(provider.selectedOrganization?.id, 9);
      expect(provider.selectedOrganization?.organizationName, 'Fast Org');
      expect(repository.getOrganizationCallCount, 2);
    });
  });

  group('approve', () {
    test(
      'success patches the matching list entry and selectedOrganization',
      () async {
        repository.loadResult = [
          _organization(id: 1, approvalStatus: 'pending'),
          _organization(id: 2, approvalStatus: 'pending'),
        ];
        await provider.load();
        repository.resultsByOrganization = {
          1: _organization(id: 1, approvalStatus: 'approved'),
        };
        await provider.loadDetails(1);

        repository.actionResult = _organization(
          id: 1,
          approvalStatus: 'approved',
        );
        final success = await provider.approve(1);

        expect(success, isTrue);
        expect(
          provider.organizations.firstWhere((o) => o.id == 1).approvalStatus,
          'approved',
        );
        // The other organization is untouched.
        expect(
          provider.organizations.firstWhere((o) => o.id == 2).approvalStatus,
          'pending',
        );
        expect(provider.selectedOrganization?.approvalStatus, 'approved');
        expect(repository.approveCallCount, 1);
      },
    );

    test(
      'does not patch selectedOrganization when it is a different organization',
      () async {
        repository.loadResult = [_organization(id: 1), _organization(id: 2)];
        await provider.load();
        repository.resultsByOrganization = {2: _organization(id: 2)};
        await provider.loadDetails(2);

        repository.actionResult = _organization(
          id: 1,
          approvalStatus: 'approved',
        );
        await provider.approve(1);

        expect(provider.selectedOrganization?.id, 2);
        expect(provider.selectedOrganization?.approvalStatus, 'pending');
      },
    );

    test('failure retains the old approval status', () async {
      repository.loadResult = [_organization(id: 1, approvalStatus: 'pending')];
      await provider.load();

      repository.actionError = ApiException('Server error.');
      final success = await provider.approve(1);

      expect(success, isFalse);
      expect(provider.organizations.single.approvalStatus, 'pending');
      expect(provider.actionErrorMessage, 'Server error.');
    });

    test(
      'an unexpected failure exposes a safe, non-technical message',
      () async {
        repository.loadResult = [
          _organization(id: 1, approvalStatus: 'pending'),
        ];
        await provider.load();

        repository.actionRuntimeError = TypeError();
        await provider.approve(1);

        expect(provider.actionErrorMessage, isNotNull);
        expect(provider.actionErrorMessage, isNot(contains('TypeError')));
        expect(
          provider.actionErrorMessage,
          'Something went wrong. Please try again.',
        );
        expect(provider.organizations.single.approvalStatus, 'pending');
      },
    );

    test('a second approve for the same organization while one is in flight is '
        'blocked (only one repository call)', () async {
      repository.loadResult = [_organization(id: 1, approvalStatus: 'pending')];
      repository.actionDelay = const Duration(milliseconds: 50);
      repository.actionResult = _organization(
        id: 1,
        approvalStatus: 'approved',
      );
      await provider.load();

      final first = provider.approve(1);
      final second = provider.approve(1);

      final results = await Future.wait([first, second]);

      expect(repository.approveCallCount, 1);
      expect(results.where((success) => success).length, 1);
      expect(results.where((success) => !success).length, 1);
    });

    test('busy ID is removed in finally after a successful approve', () async {
      repository.loadResult = [_organization(id: 1, approvalStatus: 'pending')];
      repository.actionResult = _organization(
        id: 1,
        approvalStatus: 'approved',
      );
      await provider.load();

      expect(provider.isBusy(1), isFalse);
      final future = provider.approve(1);
      expect(provider.isBusy(1), isTrue);
      await future;
      expect(provider.isBusy(1), isFalse);
    });

    test('busy ID is removed in finally after a failed approve', () async {
      repository.loadResult = [_organization(id: 1, approvalStatus: 'pending')];
      repository.actionError = ApiException('Server error.');
      await provider.load();

      await provider.approve(1);

      expect(provider.isBusy(1), isFalse);
    });

    test(
      'different organizations can act independently at the same time',
      () async {
        repository.loadResult = [
          _organization(id: 1, approvalStatus: 'pending'),
          _organization(id: 2, approvalStatus: 'pending'),
        ];
        repository.actionDelay = const Duration(milliseconds: 50);
        repository.actionResult = _organization(
          id: 1,
          approvalStatus: 'approved',
        );
        await provider.load();

        final firstAction = provider.approve(1);
        expect(provider.isBusy(1), isTrue);
        expect(provider.isBusy(2), isFalse);

        final secondAction = provider.reject(2);
        expect(provider.isBusy(2), isTrue);

        final results = await Future.wait([firstAction, secondAction]);

        expect(repository.approveCallCount, 1);
        expect(repository.rejectCallCount, 1);
        expect(results, [true, true]);
      },
    );
  });

  group('reject', () {
    test(
      'success patches the matching list entry and selectedOrganization',
      () async {
        repository.loadResult = [
          _organization(id: 1, approvalStatus: 'pending'),
        ];
        await provider.load();
        repository.resultsByOrganization = {
          1: _organization(id: 1, approvalStatus: 'rejected'),
        };
        await provider.loadDetails(1);

        repository.actionResult = _organization(
          id: 1,
          approvalStatus: 'rejected',
        );
        final success = await provider.reject(1);

        expect(success, isTrue);
        expect(provider.organizations.single.approvalStatus, 'rejected');
        expect(provider.selectedOrganization?.approvalStatus, 'rejected');
        expect(repository.rejectCallCount, 1);
      },
    );

    test('failure retains the old approval status', () async {
      repository.loadResult = [_organization(id: 1, approvalStatus: 'pending')];
      await provider.load();

      repository.actionError = ApiException(
        'This action is unauthorized for your account type',
        statusCode: 403,
      );
      final success = await provider.reject(1);

      expect(success, isFalse);
      expect(provider.organizations.single.approvalStatus, 'pending');
      expect(
        provider.actionErrorMessage,
        'This action is unauthorized for your account type',
      );
    });
  });

  test('clearActionError clears the action error message', () async {
    repository.loadResult = [_organization(id: 1, approvalStatus: 'pending')];
    repository.actionError = ApiException('Server error.');
    await provider.load();
    await provider.approve(1);
    expect(provider.actionErrorMessage, isNotNull);

    provider.clearActionError();

    expect(provider.actionErrorMessage, isNull);
  });

  test('reset clears all state', () async {
    repository.loadResult = [_organization(id: 1)];
    await provider.load();
    repository.resultsByOrganization = {1: _organization(id: 1)};
    await provider.loadDetails(1);
    expect(provider.organizations, isNotEmpty);
    expect(provider.selectedOrganization, isNotNull);

    provider.reset();

    expect(provider.organizations, isEmpty);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.selectedOrganization, isNull);
    expect(provider.isLoadingDetails, isFalse);
    expect(provider.detailsErrorMessage, isNull);
    expect(provider.actionErrorMessage, isNull);
    expect(provider.busyOrganizationIds, isEmpty);
  });

  test('reset clears state on logout', () async {
    repository.loadResult = [_organization(id: 1)];
    await provider.load();
    expect(provider.organizations, isNotEmpty);

    await authProvider.logout();

    expect(provider.organizations, isEmpty);
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
