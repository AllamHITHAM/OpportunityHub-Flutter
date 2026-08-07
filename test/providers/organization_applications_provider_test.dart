// Direct unit tests for OrganizationApplicationsProvider, using a fake
// repository (no real network) and a real AuthProvider (with a fake
// AuthRepository) so the reset-on-logout listener can be exercised
// genuinely.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/applications/data/application_repository.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/models/application_model.dart';
import 'package:opportunityhub_flutter/models/cv_model.dart';
import 'package:opportunityhub_flutter/models/opportunity_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_applications_provider.dart';

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

const _cv = CvModel(
  id: 2,
  studentId: 1,
  title: 'Main CV',
  filePath: 'uploads/cv.pdf',
  version: 1,
  isDefault: false,
  createdByAi: false,
);

OpportunityModel _opportunity({int id = 5}) {
  return OpportunityModel(
    id: id,
    title: 'Backend Developer',
    description: 'Great role.',
    opportunityType: 'job',
    employmentType: 'full_time',
    workMode: 'remote',
    experienceLevel: 'junior',
    positionsAvailable: 1,
    status: 'open',
  );
}

ApplicationModel _application({
  int id = 1,
  String status = 'pending',
  bool withOpportunity = false,
}) {
  return ApplicationModel(
    id: id,
    studentId: 1,
    opportunityId: 5,
    cvId: 2,
    status: status,
    cv: _cv,
    opportunity: withOpportunity ? _opportunity() : null,
  );
}

class _FakeApplicationRepository extends ApplicationRepository {
  _FakeApplicationRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<ApplicationModel> listResult = [];
  ApiException? listError;
  Object? listRuntimeError;
  int getApplicationsForOpportunityCallCount = 0;
  int? lastOpportunityId;
  final List<int> requestedOpportunityIds = [];

  /// Per-opportunity overrides — when set for a given ID, take priority
  /// over the single [listResult]/no-delay defaults. Lets a test give two
  /// different opportunities two different results and/or delays, to
  /// exercise the stale-response-must-not-win scenario.
  Map<int, List<ApplicationModel>>? resultsByOpportunity;
  Map<int, Duration>? delaysByOpportunity;

  ApplicationModel? detailsResult;
  ApiException? detailsError;
  int getOrganizationApplicationCallCount = 0;

  ApplicationModel? statusUpdateResult;
  ApiException? statusUpdateError;

  /// A non-[ApiException] error — simulates what the real repository
  /// would throw if the backend ever returned a malformed status-update
  /// response (a failed type cast inside `ApplicationModel.fromJson`).
  Object? statusUpdateRuntimeError;
  Duration statusUpdateDelay = Duration.zero;
  int updateStatusCallCount = 0;
  String? lastStatus;

  @override
  Future<List<ApplicationModel>> getApplicationsForOpportunity(
    int opportunityId,
  ) async {
    getApplicationsForOpportunityCallCount++;
    lastOpportunityId = opportunityId;
    requestedOpportunityIds.add(opportunityId);

    final delay = delaysByOpportunity?[opportunityId] ?? Duration.zero;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (listRuntimeError != null) throw listRuntimeError!;
    if (listError != null) throw listError!;
    return resultsByOpportunity?[opportunityId] ?? listResult;
  }

  @override
  Future<ApplicationModel> getOrganizationApplication(int applicationId) async {
    getOrganizationApplicationCallCount++;
    if (detailsError != null) throw detailsError!;
    return detailsResult!;
  }

  @override
  Future<ApplicationModel> updateOrganizationApplicationStatus({
    required int applicationId,
    required String status,
  }) async {
    updateStatusCallCount++;
    lastStatus = status;
    if (statusUpdateDelay > Duration.zero) {
      await Future<void>.delayed(statusUpdateDelay);
    }
    if (statusUpdateRuntimeError != null) throw statusUpdateRuntimeError!;
    if (statusUpdateError != null) throw statusUpdateError!;
    return statusUpdateResult!;
  }
}

void main() {
  late AuthProvider authProvider;
  late _FakeApplicationRepository repository;
  late OrganizationApplicationsProvider provider;

  setUp(() {
    authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    repository = _FakeApplicationRepository();
    provider = OrganizationApplicationsProvider(
      repository: repository,
      authProvider: authProvider,
    );
  });

  test('initial state is empty and idle', () {
    expect(provider.applications, isEmpty);
    expect(provider.isLoadingList, isFalse);
    expect(provider.listErrorMessage, isNull);
    expect(provider.selectedApplication, isNull);
    expect(provider.isLoadingDetails, isFalse);
    expect(provider.detailsErrorMessage, isNull);
    expect(provider.busyApplicationIds, isEmpty);
    expect(provider.actionErrorMessage, isNull);
  });

  test('list loading success populates the list', () async {
    repository.listResult = [_application(id: 1), _application(id: 2)];

    await provider.loadApplicationsForOpportunity(5);

    expect(provider.applications, hasLength(2));
    expect(provider.isLoadingList, isFalse);
    expect(provider.listErrorMessage, isNull);
    expect(repository.lastOpportunityId, 5);
  });

  test('an empty list is represented correctly, not as an error', () async {
    await provider.loadApplicationsForOpportunity(5);

    expect(provider.applications, isEmpty);
    expect(provider.listErrorMessage, isNull);
  });

  test('list loading failure surfaces the error and is retryable', () async {
    repository.listError = ApiException(
      'Server error, please try again later.',
    );

    await provider.loadApplicationsForOpportunity(5);

    expect(provider.listErrorMessage, 'Server error, please try again later.');
    expect(provider.applications, isEmpty);

    repository.listError = null;
    repository.listResult = [_application()];
    await provider.loadApplicationsForOpportunity(5, forceRefresh: true);

    expect(provider.listErrorMessage, isNull);
    expect(provider.applications, hasLength(1));
  });

  test('malformed list data never leaves the provider stuck loading', () async {
    repository.listRuntimeError = TypeError();

    await provider.loadApplicationsForOpportunity(5);

    expect(provider.isLoadingList, isFalse);
    expect(provider.listErrorMessage, isNotNull);
    expect(provider.listErrorMessage, isNot(contains('TypeError')));

    repository.listRuntimeError = null;
    repository.listResult = [_application()];
    await provider.loadApplicationsForOpportunity(5);

    expect(provider.listErrorMessage, isNull);
    expect(provider.applications, hasLength(1));
  });

  test('forceRefresh starts a new fetch even while unchanged', () async {
    await provider.loadApplicationsForOpportunity(5);
    await provider.loadApplicationsForOpportunity(5, forceRefresh: true);

    expect(repository.getApplicationsForOpportunityCallCount, 2);
  });

  test('concurrent duplicate list fetches are prevented', () async {
    repository.listResult = [_application()];

    final first = provider.loadApplicationsForOpportunity(5);
    final second = provider.loadApplicationsForOpportunity(5);
    await Future.wait([first, second]);

    expect(repository.getApplicationsForOpportunityCallCount, 1);
  });

  test(
    'loading opportunity 5 then opportunity 9 loads opportunity 9 correctly, not opportunity 5\'s in-flight future',
    () async {
      // Opportunity 5's fetch is slow; opportunity 9's is requested before
      // it resolves. Without per-opportunity keying, the second call would
      // just await opportunity 5's future and end up with its data.
      repository.delaysByOpportunity = {5: const Duration(milliseconds: 100)};
      repository.resultsByOpportunity = {
        5: [_application(id: 1)],
        9: [_application(id: 2), _application(id: 3)],
      };

      final firstCall = provider.loadApplicationsForOpportunity(5);
      final secondCall = provider.loadApplicationsForOpportunity(9);
      await Future.wait([firstCall, secondCall]);

      expect(provider.applications.map((a) => a.id), [2, 3]);
      expect(repository.requestedOpportunityIds, containsAll([5, 9]));
    },
  );

  test(
    'a slower stale response for opportunity 5 cannot overwrite the newer opportunity 9 list',
    () async {
      // Opportunity 9 is requested first and resolves fast; opportunity 5
      // is requested second (a genuinely new, separate request — not a
      // dedup case) but resolves slower and arrives *after* opportunity 9
      // already settled. Its data must never win.
      repository.resultsByOpportunity = {
        9: [_application(id: 9)],
        5: [_application(id: 5)],
      };

      await provider.loadApplicationsForOpportunity(9);
      expect(provider.applications.single.id, 9);

      repository.delaysByOpportunity = {5: const Duration(milliseconds: 100)};
      final staleCall = provider.loadApplicationsForOpportunity(5);

      // Switch back to opportunity 9 before the stale opportunity-5
      // response arrives — this is the "currently requested" opportunity
      // by the time opportunity 5 resolves.
      await provider.loadApplicationsForOpportunity(9, forceRefresh: true);
      expect(provider.applications.single.id, 9);

      // Let the slow, now-stale opportunity-5 response resolve.
      await staleCall;

      expect(provider.applications.single.id, 9);
    },
  );

  test(
    'loadApplicationDetails reuses a cached list item only when it has full details (opportunity present)',
    () async {
      repository.listResult = [_application(id: 1, withOpportunity: true)];
      await provider.loadApplicationsForOpportunity(5);

      await provider.loadApplicationDetails(1);

      expect(provider.selectedApplication?.id, 1);
      expect(repository.getOrganizationApplicationCallCount, 0);
    },
  );

  test(
    'loadApplicationDetails fetches fresh when the cached list item is missing full details (applicants-list shape)',
    () async {
      repository.listResult = [_application(id: 1, withOpportunity: false)];
      await provider.loadApplicationsForOpportunity(5);

      repository.detailsResult = _application(id: 1, withOpportunity: true);
      await provider.loadApplicationDetails(1);

      expect(provider.selectedApplication?.opportunity, isNotNull);
      expect(repository.getOrganizationApplicationCallCount, 1);
    },
  );

  test('details loading failure surfaces the error', () async {
    repository.detailsError = ApiException('Application not found');

    await provider.loadApplicationDetails(999);

    expect(provider.detailsErrorMessage, 'Application not found');
    expect(provider.selectedApplication, isNull);
  });

  test('markReviewed success updates status locally', () async {
    repository.listResult = [_application(id: 1, status: 'pending')];
    await provider.loadApplicationsForOpportunity(5);

    repository.statusUpdateResult = _application(id: 1, status: 'reviewed');
    final success = await provider.markReviewed(1);

    expect(success, isTrue);
    expect(repository.lastStatus, 'reviewed');
    expect(provider.applications.single.status, 'reviewed');
  });

  test('markReviewed failure keeps the old status', () async {
    repository.listResult = [_application(id: 1, status: 'pending')];
    await provider.loadApplicationsForOpportunity(5);

    repository.statusUpdateError = ApiException('Something went wrong.');
    final success = await provider.markReviewed(1);

    expect(success, isFalse);
    expect(provider.applications.single.status, 'pending');
    expect(provider.actionErrorMessage, 'Something went wrong.');
  });

  test('shortlist success updates status locally', () async {
    repository.listResult = [_application(id: 1, status: 'reviewed')];
    await provider.loadApplicationsForOpportunity(5);

    repository.statusUpdateResult = _application(id: 1, status: 'shortlisted');
    final success = await provider.shortlist(1);

    expect(success, isTrue);
    expect(repository.lastStatus, 'shortlisted');
    expect(provider.applications.single.status, 'shortlisted');
  });

  test('shortlist failure keeps the old status', () async {
    repository.listResult = [_application(id: 1, status: 'reviewed')];
    await provider.loadApplicationsForOpportunity(5);

    repository.statusUpdateError = ApiException('Server error.');
    final success = await provider.shortlist(1);

    expect(success, isFalse);
    expect(provider.applications.single.status, 'reviewed');
  });

  test('reject success updates status locally', () async {
    repository.listResult = [_application(id: 1, status: 'shortlisted')];
    await provider.loadApplicationsForOpportunity(5);

    repository.statusUpdateResult = _application(id: 1, status: 'rejected');
    final success = await provider.reject(1);

    expect(success, isTrue);
    expect(repository.lastStatus, 'rejected');
    expect(provider.applications.single.status, 'rejected');
  });

  test(
    'reject failure (409 withdrawn conflict) keeps the old status and exposes the message',
    () async {
      repository.listResult = [_application(id: 1, status: 'withdrawn')];
      await provider.loadApplicationsForOpportunity(5);

      repository.statusUpdateError = ApiException(
        'Cannot change the status of a withdrawn application',
        statusCode: 409,
      );
      final success = await provider.reject(1);

      expect(success, isFalse);
      expect(provider.applications.single.status, 'withdrawn');
      expect(
        provider.actionErrorMessage,
        'Cannot change the status of a withdrawn application',
      );
    },
  );

  test('a successful update patches selectedApplication immediately', () async {
    repository.listResult = [
      _application(id: 1, status: 'pending', withOpportunity: true),
    ];
    await provider.loadApplicationsForOpportunity(5);
    await provider.loadApplicationDetails(1);
    expect(provider.selectedApplication?.status, 'pending');

    repository.statusUpdateResult = _application(id: 1, status: 'reviewed');
    await provider.markReviewed(1);

    expect(provider.selectedApplication?.status, 'reviewed');
  });

  test('a failed update leaves selectedApplication untouched', () async {
    repository.listResult = [
      _application(id: 1, status: 'pending', withOpportunity: true),
    ];
    await provider.loadApplicationsForOpportunity(5);
    await provider.loadApplicationDetails(1);

    repository.statusUpdateError = ApiException('Server error.');
    await provider.markReviewed(1);

    expect(provider.selectedApplication?.status, 'pending');
  });

  test(
    'a second status action for the same application while one is in flight is blocked (only one repository call)',
    () async {
      repository.listResult = [_application(id: 1, status: 'pending')];
      repository.statusUpdateDelay = const Duration(milliseconds: 50);
      repository.statusUpdateResult = _application(id: 1, status: 'reviewed');
      await provider.loadApplicationsForOpportunity(5);

      final first = provider.markReviewed(1);
      final second = provider.markReviewed(1);

      final results = await Future.wait([first, second]);

      expect(repository.updateStatusCallCount, 1);
      expect(results.where((success) => success).length, 1);
      expect(results.where((success) => !success).length, 1);
    },
  );

  test('busy ID is removed in finally after a successful update', () async {
    repository.listResult = [_application(id: 1, status: 'pending')];
    repository.statusUpdateResult = _application(id: 1, status: 'reviewed');
    await provider.loadApplicationsForOpportunity(5);

    expect(provider.isUpdating(1), isFalse);
    final future = provider.markReviewed(1);
    expect(provider.isUpdating(1), isTrue);
    await future;
    expect(provider.isUpdating(1), isFalse);
  });

  test('busy ID is removed in finally after a failed update', () async {
    repository.listResult = [_application(id: 1, status: 'pending')];
    repository.statusUpdateError = ApiException('Server error.');
    await provider.loadApplicationsForOpportunity(5);

    await provider.markReviewed(1);

    expect(provider.isUpdating(1), isFalse);
  });

  test(
    'an unexpected status-update parsing/runtime failure never escapes the provider',
    () async {
      repository.listResult = [_application(id: 1, status: 'pending')];
      await provider.loadApplicationsForOpportunity(5);

      repository.statusUpdateRuntimeError = TypeError();

      // Must complete (not throw) and return false.
      final success = await provider.markReviewed(1);

      expect(success, isFalse);
    },
  );

  test(
    'an unexpected status-update failure preserves the old list status',
    () async {
      repository.listResult = [_application(id: 1, status: 'pending')];
      await provider.loadApplicationsForOpportunity(5);

      repository.statusUpdateRuntimeError = TypeError();
      await provider.markReviewed(1);

      expect(provider.applications.single.status, 'pending');
    },
  );

  test(
    'an unexpected status-update failure preserves selectedApplication',
    () async {
      repository.listResult = [
        _application(id: 1, status: 'pending', withOpportunity: true),
      ];
      await provider.loadApplicationsForOpportunity(5);
      await provider.loadApplicationDetails(1);
      expect(provider.selectedApplication?.status, 'pending');

      repository.statusUpdateRuntimeError = TypeError();
      await provider.markReviewed(1);

      expect(provider.selectedApplication?.status, 'pending');
    },
  );

  test(
    'an unexpected status-update failure still clears the busy ID',
    () async {
      repository.listResult = [_application(id: 1, status: 'pending')];
      await provider.loadApplicationsForOpportunity(5);

      repository.statusUpdateRuntimeError = TypeError();
      await provider.markReviewed(1);

      expect(provider.isUpdating(1), isFalse);
    },
  );

  test(
    'an unexpected status-update failure exposes a safe, non-technical message',
    () async {
      repository.listResult = [_application(id: 1, status: 'pending')];
      await provider.loadApplicationsForOpportunity(5);

      repository.statusUpdateRuntimeError = TypeError();
      await provider.markReviewed(1);

      expect(provider.actionErrorMessage, isNotNull);
      expect(provider.actionErrorMessage, isNot(contains('TypeError')));
      expect(
        provider.actionErrorMessage,
        'Something went wrong. Please try again.',
      );
    },
  );

  test('clearActionError clears the action error message', () async {
    repository.listResult = [_application(id: 1, status: 'pending')];
    repository.statusUpdateError = ApiException('Server error.');
    await provider.loadApplicationsForOpportunity(5);
    await provider.markReviewed(1);
    expect(provider.actionErrorMessage, isNotNull);

    provider.clearActionError();

    expect(provider.actionErrorMessage, isNull);
  });

  test('reset clears all state (called on logout)', () async {
    repository.listResult = [_application(id: 1)];
    await provider.loadApplicationsForOpportunity(5);
    await provider.loadApplicationDetails(1);
    expect(provider.applications, isNotEmpty);

    await authProvider.logout();

    expect(provider.applications, isEmpty);
    expect(provider.selectedApplication, isNull);
    expect(provider.listErrorMessage, isNull);
    expect(provider.detailsErrorMessage, isNull);
    expect(provider.busyApplicationIds, isEmpty);
    expect(provider.actionErrorMessage, isNull);
  });

  test(
    'switching organizations cannot leak the previous organization\'s applicants',
    () async {
      repository.listResult = [_application(id: 1)];
      await provider.loadApplicationsForOpportunity(5);
      expect(provider.applications, hasLength(1));

      await authProvider.logout();
      repository.listResult = [_application(id: 2), _application(id: 3)];
      await provider.loadApplicationsForOpportunity(9);

      expect(provider.applications, hasLength(2));
    },
  );

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

  group('patchApplication', () {
    test('a changed application patches the matching list item', () async {
      repository.listResult = [_application(id: 1, status: 'shortlisted')];
      await provider.loadApplicationsForOpportunity(5);

      provider.patchApplication(
        _application(id: 1, status: 'interview_scheduled'),
      );

      expect(provider.applications.single.status, 'interview_scheduled');
    });

    test(
      'a changed application patches selectedApplication when IDs match',
      () async {
        repository.listResult = [
          _application(id: 1, status: 'shortlisted', withOpportunity: true),
        ];
        await provider.loadApplicationsForOpportunity(5);
        await provider.loadApplicationDetails(1);
        expect(provider.selectedApplication?.status, 'shortlisted');

        provider.patchApplication(
          _application(id: 1, status: 'interview_scheduled'),
        );

        expect(provider.selectedApplication?.status, 'interview_scheduled');
      },
    );

    test(
      'list and selectedApplication stay consistent, patched together in one notification',
      () async {
        repository.listResult = [
          _application(id: 1, status: 'shortlisted', withOpportunity: true),
        ];
        await provider.loadApplicationsForOpportunity(5);
        await provider.loadApplicationDetails(1);

        var notifyCount = 0;
        provider.addListener(() => notifyCount++);

        provider.patchApplication(
          _application(id: 1, status: 'interview_scheduled'),
        );

        expect(provider.applications.single.status, 'interview_scheduled');
        expect(provider.selectedApplication?.status, 'interview_scheduled');
        expect(notifyCount, 1);
      },
    );

    test(
      'an effectively identical model produces zero notifications',
      () async {
        repository.listResult = [_application(id: 1, status: 'shortlisted')];
        await provider.loadApplicationsForOpportunity(5);

        var notifyCount = 0;
        provider.addListener(() => notifyCount++);

        // A separately-constructed model carrying the exact same data —
        // never `identical()` to the one already in `applications`, but
        // content-equal.
        provider.patchApplication(_application(id: 1, status: 'shortlisted'));

        expect(notifyCount, 0);
      },
    );

    test(
      'an unrelated application ID produces zero notifications and no change',
      () async {
        repository.listResult = [_application(id: 1, status: 'shortlisted')];
        await provider.loadApplicationsForOpportunity(5);

        var notifyCount = 0;
        provider.addListener(() => notifyCount++);

        provider.patchApplication(
          _application(id: 999, status: 'interview_scheduled'),
        );

        expect(notifyCount, 0);
        expect(provider.applications.single.id, 1);
        expect(provider.applications.single.status, 'shortlisted');
      },
    );

    test(
      'patches selectedApplication even when the matching list item is absent',
      () async {
        repository.detailsResult = _application(
          id: 7,
          status: 'shortlisted',
          withOpportunity: true,
        );
        await provider.loadApplicationDetails(7);
        expect(provider.selectedApplication?.status, 'shortlisted');

        provider.patchApplication(
          _application(id: 7, status: 'interview_scheduled'),
        );

        expect(provider.selectedApplication?.status, 'interview_scheduled');
        expect(provider.applications, isEmpty);
      },
    );

    test(
      'patches the list item even when it is not the selected application',
      () async {
        repository.listResult = [_application(id: 1, status: 'shortlisted')];
        await provider.loadApplicationsForOpportunity(5);
        expect(provider.selectedApplication, isNull);

        provider.patchApplication(
          _application(id: 1, status: 'interview_scheduled'),
        );

        expect(provider.applications.single.status, 'interview_scheduled');
        expect(provider.selectedApplication, isNull);
      },
    );

    test('does not reload data — no repository call is made', () async {
      repository.listResult = [_application(id: 1, status: 'shortlisted')];
      await provider.loadApplicationsForOpportunity(5);
      final callCountBefore = repository.getApplicationsForOpportunityCallCount;

      provider.patchApplication(
        _application(id: 1, status: 'interview_scheduled'),
      );

      expect(
        repository.getApplicationsForOpportunityCallCount,
        callCountBefore,
      );
    });
  });
}
