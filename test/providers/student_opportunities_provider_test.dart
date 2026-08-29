// Direct unit tests for StudentOpportunitiesProvider, using a fake
// repository (no real network) and a real AuthProvider (with a fake
// AuthRepository) so the reset-on-logout listener can be exercised
// genuinely.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/api/paginated_result.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/opportunities/data/opportunity_repository.dart';
import 'package:opportunityhub_flutter/models/opportunity_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/student_opportunities_provider.dart';

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

OpportunityModel _opportunity({
  int id = 1,
  String title = 'Software Engineer',
}) {
  return OpportunityModel(
    id: id,
    title: title,
    description: 'A great opportunity.',
    opportunityType: 'job',
    employmentType: 'full_time',
    workMode: 'remote',
    experienceLevel: 'junior',
    positionsAvailable: 1,
    status: 'open',
  );
}

class _FakeOpportunityRepository extends OpportunityRepository {
  _FakeOpportunityRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  PaginatedResult<OpportunityModel> listResult = const PaginatedResult(
    items: [],
    currentPage: 1,
    lastPage: 1,
    total: 0,
  );
  ApiException? listError;
  int getPublicOpportunitiesCallCount = 0;
  String? lastKeyword;
  String? lastOpportunityType;
  int? lastPage;

  OpportunityModel? getResult;
  ApiException? getError;
  int getPublicOpportunityCallCount = 0;

  @override
  Future<PaginatedResult<OpportunityModel>> getPublicOpportunities({
    String? opportunityType,
    String? employmentType,
    String? workMode,
    String? experienceLevel,
    String? location,
    String? fieldOfStudy,
    String? keyword,
    int? organizationId,
    int page = 1,
    int perPage = 15,
  }) async {
    getPublicOpportunitiesCallCount++;
    lastKeyword = keyword;
    lastOpportunityType = opportunityType;
    lastPage = page;
    if (listError != null) throw listError!;
    return listResult;
  }

  @override
  Future<OpportunityModel> getPublicOpportunity(int id) async {
    getPublicOpportunityCallCount++;
    if (getError != null) throw getError!;
    return getResult!;
  }
}

void main() {
  late AuthProvider authProvider;
  late _FakeOpportunityRepository repository;
  late StudentOpportunitiesProvider provider;

  setUp(() {
    authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    repository = _FakeOpportunityRepository();
    provider = StudentOpportunitiesProvider(
      repository: repository,
      authProvider: authProvider,
    );
  });

  test('initial load succeeds and populates the list', () async {
    repository.listResult = PaginatedResult(
      items: [_opportunity(id: 1), _opportunity(id: 2)],
      currentPage: 1,
      lastPage: 1,
      total: 2,
    );

    await provider.loadOpportunities();

    expect(provider.opportunities, hasLength(2));
    expect(provider.isLoadingList, isFalse);
    expect(provider.listErrorMessage, isNull);
  });

  test('an empty list is represented correctly, not as an error', () async {
    await provider.loadOpportunities();

    expect(provider.opportunities, isEmpty);
    expect(provider.listErrorMessage, isNull);
  });

  test('load failure is retryable', () async {
    repository.listError = ApiException(
      'Server error, please try again later.',
    );

    await provider.loadOpportunities();

    expect(provider.listErrorMessage, 'Server error, please try again later.');
    expect(provider.opportunities, isEmpty);

    repository.listError = null;
    repository.listResult = PaginatedResult(
      items: [_opportunity()],
      currentPage: 1,
      lastPage: 1,
      total: 1,
    );
    await provider.loadOpportunities(forceRefresh: true);

    expect(provider.listErrorMessage, isNull);
    expect(provider.opportunities, hasLength(1));
  });

  test('concurrent duplicate list fetches are prevented', () async {
    final first = provider.loadOpportunities();
    final second = provider.loadOpportunities();
    await Future.wait([first, second]);

    expect(repository.getPublicOpportunitiesCallCount, 1);
  });

  test(
    'forceRefresh starts a new fetch even while unchanged (supports pull-to-refresh)',
    () async {
      await provider.loadOpportunities();
      await provider.loadOpportunities(forceRefresh: true);

      expect(repository.getPublicOpportunitiesCallCount, 2);
    },
  );

  test(
    'updateKeyword plus loadOpportunities sends the trimmed keyword',
    () async {
      provider.updateKeyword('engineer');
      await provider.loadOpportunities(forceRefresh: true);

      expect(repository.lastKeyword, 'engineer');
    },
  );

  test('an empty keyword is sent as no filter at all (null)', () async {
    provider.updateKeyword('');
    await provider.loadOpportunities(forceRefresh: true);

    expect(repository.lastKeyword, isNull);
  });

  test(
    'applyFilters sets filters, marks hasActiveFilters, and refetches',
    () async {
      await provider.applyFilters(opportunityType: 'job', workMode: 'remote');

      expect(provider.opportunityType, 'job');
      expect(provider.workMode, 'remote');
      expect(provider.hasActiveFilters, isTrue);
      expect(repository.lastOpportunityType, 'job');
    },
  );

  test('clearFilters resets every filter and refetches', () async {
    await provider.applyFilters(opportunityType: 'job');
    expect(provider.hasActiveFilters, isTrue);

    await provider.clearFilters();

    expect(provider.hasActiveFilters, isFalse);
    expect(repository.lastOpportunityType, isNull);
  });

  test('loadMore appends the next page and advances currentPage', () async {
    repository.listResult = PaginatedResult(
      items: [_opportunity(id: 1)],
      currentPage: 1,
      lastPage: 2,
      total: 2,
    );
    await provider.loadOpportunities();
    expect(provider.hasMore, isTrue);

    repository.listResult = PaginatedResult(
      items: [_opportunity(id: 2)],
      currentPage: 2,
      lastPage: 2,
      total: 2,
    );
    await provider.loadMore();

    expect(provider.opportunities.map((o) => o.id), [1, 2]);
    expect(repository.lastPage, 2);
    expect(provider.hasMore, isFalse);
  });

  test('loadMore is a no-op once there is no more to load', () async {
    repository.listResult = PaginatedResult(
      items: [_opportunity(id: 1)],
      currentPage: 1,
      lastPage: 1,
      total: 1,
    );
    await provider.loadOpportunities();
    expect(provider.hasMore, isFalse);

    await provider.loadMore();

    expect(repository.getPublicOpportunitiesCallCount, 1);
  });

  test(
    'loadOpportunityDetails paints instantly from a cached list item, then '
    'a background fetch still runs and its fresh result wins',
    () async {
      repository.listResult = PaginatedResult(
        items: [_opportunity(id: 1, title: 'Cached Title')],
        currentPage: 1,
        lastPage: 1,
        total: 1,
      );
      await provider.loadOpportunities();

      repository.getResult = _opportunity(id: 1, title: 'Fresh Title');
      final future = provider.loadOpportunityDetails(1);

      // Instant paint from the list cache, before the background fetch
      // has had a chance to resolve.
      expect(provider.selectedOpportunity?.title, 'Cached Title');

      await future;

      // The background fetch always runs (even on a cache hit) and its
      // result always wins once it lands -- Apply-gating fields must
      // never stay pinned to a stale list-cache copy.
      expect(provider.selectedOpportunity?.title, 'Fresh Title');
      expect(repository.getPublicOpportunityCallCount, 1);
    },
  );

  test(
    'a stale cached copy with no eligible-majors restriction is replaced by '
    'a fresh copy that has one -- regression test for the reported bug',
    () async {
      // The list was fetched before the Organization added an Eligible
      // Majors restriction -- the cached copy still shows unrestricted.
      repository.listResult = PaginatedResult(
        items: [
          OpportunityModel(
            id: 1,
            title: 'Backend Developer',
            description: 'A great opportunity.',
            opportunityType: 'job',
            employmentType: 'full_time',
            workMode: 'remote',
            experienceLevel: 'junior',
            positionsAvailable: 1,
            status: 'open',
            eligibleMajors: const [],
          ),
        ],
        currentPage: 1,
        lastPage: 1,
        total: 1,
      );
      await provider.loadOpportunities();
      expect(provider.selectedOpportunity, isNull);

      // The backend's current truth now has an explicit restriction.
      repository.getResult = OpportunityModel(
        id: 1,
        title: 'Backend Developer',
        description: 'A great opportunity.',
        opportunityType: 'job',
        employmentType: 'full_time',
        workMode: 'remote',
        experienceLevel: 'junior',
        positionsAvailable: 1,
        status: 'open',
        eligibleMajors: const ['Computer Engineering'],
      );

      await provider.loadOpportunityDetails(1);

      expect(
        provider.selectedOpportunity?.eligibleMajors,
        ['Computer Engineering'],
      );
    },
  );

  test('loadOpportunityDetails fetches when not already in the list', () async {
    repository.getResult = _opportunity(id: 99, title: 'Fresh Title');

    await provider.loadOpportunityDetails(99);

    expect(provider.selectedOpportunity?.title, 'Fresh Title');
    expect(repository.getPublicOpportunityCallCount, 1);
  });

  test('a details failure surfaces the error and clears selection', () async {
    repository.getError = ApiException(
      'Opportunity not found',
      statusCode: 404,
    );

    await provider.loadOpportunityDetails(999);

    expect(provider.detailsErrorMessage, 'Opportunity not found');
    expect(provider.selectedOpportunity, isNull);
  });

  test('state clears on logout', () async {
    repository.listResult = PaginatedResult(
      items: [_opportunity(id: 1)],
      currentPage: 1,
      lastPage: 1,
      total: 1,
    );
    await provider.loadOpportunities();
    await provider.applyFilters(opportunityType: 'job');
    expect(provider.opportunities, isNotEmpty);

    await authProvider.logout();

    expect(provider.opportunities, isEmpty);
    expect(provider.selectedOpportunity, isNull);
    expect(provider.listErrorMessage, isNull);
    expect(provider.hasActiveFilters, isFalse);
    expect(provider.keyword, isEmpty);
  });

  test(
    'switching users cannot leak the previous session\'s search/filter state',
    () async {
      provider.updateKeyword('old search');
      await provider.applyFilters(opportunityType: 'internship');

      await authProvider.logout();

      expect(provider.keyword, isEmpty);
      expect(provider.opportunityType, isNull);
    },
  );
}
