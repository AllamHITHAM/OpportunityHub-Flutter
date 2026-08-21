// Direct unit tests for OrganizationOpportunitiesProvider, using a fake
// repository (no real network) and a real AuthProvider (with a fake
// AuthRepository) so the reset-on-logout listener can be exercised
// genuinely.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/opportunities/data/opportunity_repository.dart';
import 'package:opportunityhub_flutter/models/opportunity_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_opportunities_provider.dart';

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
  String status = 'open',
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
    status: status,
  );
}

class _FakeOpportunityRepository extends OpportunityRepository {
  _FakeOpportunityRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<OpportunityModel> listResult = [];
  ApiException? listError;
  int getOpportunitiesCallCount = 0;

  OpportunityModel? getResult;
  ApiException? getError;
  int getOpportunityCallCount = 0;

  OpportunityModel? createResult;
  ApiException? createError;
  int createCallCount = 0;

  OpportunityModel? updateResult;
  ApiException? updateError;
  int updateCallCount = 0;

  ApiException? deleteError;
  int deleteCallCount = 0;

  @override
  Future<List<OpportunityModel>> getOpportunities() async {
    getOpportunitiesCallCount++;
    if (listError != null) throw listError!;
    return listResult;
  }

  @override
  Future<OpportunityModel> getOpportunity(int id) async {
    getOpportunityCallCount++;
    if (getError != null) throw getError!;
    return getResult!;
  }

  @override
  Future<OpportunityModel> createOpportunity({
    required String title,
    required String description,
    required String opportunityType,
    required String employmentType,
    required String workMode,
    required String experienceLevel,
    String? educationLevel,
    String? fieldOfStudy,
    String? location,
    double? salaryMin,
    double? salaryMax,
    DateTime? applicationDeadline,
    int? positionsAvailable,
    String? status,
    List<String>? eligibleMajors,
  }) async {
    createCallCount++;
    if (createError != null) throw createError!;
    return createResult!;
  }

  @override
  Future<OpportunityModel> updateOpportunity({
    required int id,
    required String title,
    required String description,
    required String opportunityType,
    required String employmentType,
    required String workMode,
    required String experienceLevel,
    String? educationLevel,
    String? fieldOfStudy,
    String? location,
    double? salaryMin,
    double? salaryMax,
    DateTime? applicationDeadline,
    int? positionsAvailable,
    String? status,
    List<String>? eligibleMajors,
  }) async {
    updateCallCount++;
    if (updateError != null) throw updateError!;
    return updateResult!;
  }

  @override
  Future<void> deleteOpportunity(int id) async {
    deleteCallCount++;
    if (deleteError != null) throw deleteError!;
  }
}

void main() {
  late AuthProvider authProvider;
  late _FakeOpportunityRepository repository;
  late OrganizationOpportunitiesProvider provider;

  setUp(() {
    authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    repository = _FakeOpportunityRepository();
    provider = OrganizationOpportunitiesProvider(
      repository: repository,
      authProvider: authProvider,
    );
  });

  test('initial load succeeds and populates the list', () async {
    repository.listResult = [_opportunity(id: 1), _opportunity(id: 2)];

    await provider.loadOpportunities();

    expect(provider.opportunities, hasLength(2));
    expect(provider.isLoadingList, isFalse);
    expect(provider.listErrorMessage, isNull);
  });

  test('an empty list is represented correctly, not as an error', () async {
    repository.listResult = [];

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
    repository.listResult = [_opportunity()];
    await provider.loadOpportunities();

    expect(provider.listErrorMessage, isNull);
    expect(provider.opportunities, hasLength(1));
  });

  test('concurrent duplicate list fetches are prevented', () async {
    repository.listResult = [_opportunity()];

    final first = provider.loadOpportunities();
    final second = provider.loadOpportunities();
    await Future.wait([first, second]);

    expect(repository.getOpportunitiesCallCount, 1);
  });

  test(
    'a fresh call after completion starts a new fetch (supports pull-to-refresh)',
    () async {
      repository.listResult = [_opportunity()];
      await provider.loadOpportunities();
      await provider.loadOpportunities();

      expect(repository.getOpportunitiesCallCount, 2);
    },
  );

  test('create appends the new opportunity to the list exactly once', () async {
    repository.listResult = [_opportunity(id: 1)];
    await provider.loadOpportunities();

    repository.createResult = _opportunity(id: 2, title: 'New Role');
    final created = await provider.createOpportunity(
      title: 'New Role',
      description: 'A great opportunity.',
      opportunityType: 'job',
      employmentType: 'full_time',
      workMode: 'remote',
      experienceLevel: 'junior',
    );

    expect(created?.id, 2);
    expect(provider.opportunities, hasLength(2));
    expect(provider.opportunities.map((o) => o.id), containsAll([1, 2]));
  });

  test(
    'create failure preserves the existing list and surfaces an error',
    () async {
      repository.listResult = [_opportunity(id: 1)];
      await provider.loadOpportunities();

      repository.createError = ApiException(
        'Organization is not approved to publish opportunities',
        statusCode: 403,
      );
      final created = await provider.createOpportunity(
        title: 'New Role',
        description: 'A great opportunity.',
        opportunityType: 'job',
        employmentType: 'full_time',
        workMode: 'remote',
        experienceLevel: 'junior',
      );

      expect(created, isNull);
      expect(
        provider.formErrorMessage,
        'Organization is not approved to publish opportunities',
      );
      expect(provider.opportunities, hasLength(1));
    },
  );

  test(
    'update changes only the matching item in the list and selected details',
    () async {
      repository.listResult = [
        _opportunity(id: 1, title: 'Old Title'),
        _opportunity(id: 2, title: 'Other'),
      ];
      await provider.loadOpportunities();
      await provider.loadOpportunityDetails(1);

      repository.updateResult = _opportunity(id: 1, title: 'New Title');
      await provider.updateOpportunity(
        id: 1,
        title: 'New Title',
        description: 'A great opportunity.',
        opportunityType: 'job',
        employmentType: 'full_time',
        workMode: 'remote',
        experienceLevel: 'junior',
      );

      final updated = provider.opportunities.firstWhere((o) => o.id == 1);
      expect(updated.title, 'New Title');
      expect(
        provider.opportunities.firstWhere((o) => o.id == 2).title,
        'Other',
      );
      expect(provider.selectedOpportunity?.title, 'New Title');
    },
  );

  test('delete removes the item only after confirmed success', () async {
    repository.listResult = [_opportunity(id: 1), _opportunity(id: 2)];
    await provider.loadOpportunities();

    final success = await provider.deleteOpportunity(1);

    expect(success, isTrue);
    expect(provider.opportunities.map((o) => o.id), [2]);
  });

  test('delete failure keeps the item visible', () async {
    repository.listResult = [_opportunity(id: 1), _opportunity(id: 2)];
    await provider.loadOpportunities();

    repository.deleteError = ApiException(
      'Cannot delete an opportunity that has applications',
      statusCode: 409,
    );
    final success = await provider.deleteOpportunity(1);

    expect(success, isFalse);
    expect(provider.opportunities.map((o) => o.id), containsAll([1, 2]));
    expect(
      provider.deleteErrorMessage,
      'Cannot delete an opportunity that has applications',
    );
  });

  test('state clears on logout', () async {
    repository.listResult = [_opportunity(id: 1)];
    await provider.loadOpportunities();
    expect(provider.opportunities, isNotEmpty);

    await authProvider.logout();

    expect(provider.opportunities, isEmpty);
    expect(provider.selectedOpportunity, isNull);
    expect(provider.listErrorMessage, isNull);
  });

  test(
    'switching users cannot leak the previous organization\'s opportunities',
    () async {
      repository.listResult = [_opportunity(id: 1, title: 'Org A Role')];
      await provider.loadOpportunities();
      expect(provider.opportunities.single.title, 'Org A Role');

      // Simulate a different organization signing in on the same app
      // instance: logout resets state, then a fresh load only reflects
      // whatever the (now different) authenticated session's repository
      // returns.
      await authProvider.logout();
      repository.listResult = [_opportunity(id: 2, title: 'Org B Role')];
      await provider.loadOpportunities();

      expect(provider.opportunities, hasLength(1));
      expect(provider.opportunities.single.title, 'Org B Role');
    },
  );
}
