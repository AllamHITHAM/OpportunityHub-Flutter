// Direct unit tests for StudentApplicationsProvider, using a fake
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
import 'package:opportunityhub_flutter/providers/student_applications_provider.dart';

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

CvModel _cv({int id = 1, String title = 'My CV'}) {
  return CvModel(
    id: id,
    studentId: 1,
    title: title,
    filePath: 'cvs/my-cv.pdf',
    version: 1,
    isDefault: false,
    createdByAi: false,
  );
}

ApplicationModel _application({
  int id = 1,
  int opportunityId = 1,
  int cvId = 1,
  String status = 'pending',
}) {
  return ApplicationModel(
    id: id,
    studentId: 1,
    opportunityId: opportunityId,
    cvId: cvId,
    status: status,
    opportunity: _opportunity(id: opportunityId),
    cv: _cv(id: cvId),
  );
}

class _FakeApplicationRepository extends ApplicationRepository {
  _FakeApplicationRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<ApplicationModel> listResult = [];
  ApiException? listError;

  /// A non-[ApiException] error — simulates what the real repository would
  /// throw if the backend ever returned malformed application JSON.
  Object? listRuntimeError;
  int getStudentApplicationsCallCount = 0;

  ApplicationModel? applyResult;
  ApiException? applyError;
  Duration applyDelay = Duration.zero;
  int applyCallCount = 0;
  int? lastOpportunityId;
  int? lastCvId;
  String? lastCoverLetter;

  @override
  Future<List<ApplicationModel>> getStudentApplications() async {
    getStudentApplicationsCallCount++;
    if (listRuntimeError != null) throw listRuntimeError!;
    if (listError != null) throw listError!;
    return listResult;
  }

  @override
  Future<ApplicationModel> applyToOpportunity({
    required int opportunityId,
    required int cvId,
    String? coverLetter,
  }) async {
    applyCallCount++;
    lastOpportunityId = opportunityId;
    lastCvId = cvId;
    lastCoverLetter = coverLetter;
    if (applyDelay > Duration.zero) {
      await Future<void>.delayed(applyDelay);
    }
    if (applyError != null) throw applyError!;
    return applyResult!;
  }
}

void main() {
  late AuthProvider authProvider;
  late _FakeApplicationRepository repository;
  late StudentApplicationsProvider provider;

  setUp(() {
    authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    repository = _FakeApplicationRepository();
    provider = StudentApplicationsProvider(
      repository: repository,
      authProvider: authProvider,
    );
  });

  test('initial load succeeds and populates the list', () async {
    repository.listResult = [_application(id: 1), _application(id: 2)];

    await provider.loadApplications();

    expect(provider.applications, hasLength(2));
    expect(provider.isLoadingList, isFalse);
    expect(provider.listErrorMessage, isNull);
  });

  test('load failure surfaces the error and is retryable', () async {
    repository.listError = ApiException(
      'Server error, please try again later.',
    );

    await provider.loadApplications();

    expect(provider.listErrorMessage, 'Server error, please try again later.');
    expect(provider.applications, isEmpty);

    repository.listError = null;
    repository.listResult = [_application()];
    await provider.refresh();

    expect(provider.listErrorMessage, isNull);
    expect(provider.applications, hasLength(1));
  });

  test(
    'malformed list data never leaves the provider stuck loading, and clears the pending fetch',
    () async {
      repository.listRuntimeError = TypeError();

      await provider.loadApplications();

      expect(provider.isLoadingList, isFalse);
      expect(provider.listErrorMessage, isNotNull);
      expect(provider.listErrorMessage, isNot(contains('TypeError')));

      repository.listRuntimeError = null;
      repository.listResult = [_application()];
      await provider.loadApplications();

      expect(provider.listErrorMessage, isNull);
      expect(provider.applications, hasLength(1));
    },
  );

  test('concurrent duplicate list fetches are prevented', () async {
    repository.listResult = [_application()];

    final first = provider.loadApplications();
    final second = provider.loadApplications();
    await Future.wait([first, second]);

    expect(repository.getStudentApplicationsCallCount, 1);
  });

  test('apply success appends the new application to the list', () async {
    repository.listResult = [_application(id: 1, opportunityId: 1)];
    await provider.loadApplications();

    repository.applyResult = _application(id: 2, opportunityId: 5);
    final created = await provider.apply(opportunityId: 5, cvId: 1);

    expect(created?.id, 2);
    expect(provider.applications, hasLength(2));
    expect(repository.lastOpportunityId, 5);
    expect(repository.lastCvId, 1);
  });

  test('apply success makes hasAppliedTo true for that opportunity', () async {
    repository.applyResult = _application(id: 1, opportunityId: 9);

    expect(provider.hasAppliedTo(9), isFalse);

    await provider.apply(opportunityId: 9, cvId: 1);

    expect(provider.hasAppliedTo(9), isTrue);
  });

  test('apply 422 validation surfaces the field-specific message', () async {
    repository.applyError = ApiException(
      'The given data was invalid.',
      statusCode: 422,
      errors: {
        'cv_id': ['The selected cv id is invalid.'],
      },
    );

    final created = await provider.apply(opportunityId: 1, cvId: 999);

    expect(created, isNull);
    expect(provider.formErrorMessage, 'The selected cv id is invalid.');
  });

  test(
    'apply 409 duplicate surfaces the exact backend message and does not add a duplicate',
    () async {
      repository.listResult = [_application(id: 1, opportunityId: 5)];
      await provider.loadApplications();

      repository.applyError = ApiException(
        'You have already applied to this opportunity',
        statusCode: 409,
      );
      final created = await provider.apply(opportunityId: 5, cvId: 1);

      expect(created, isNull);
      expect(
        provider.formErrorMessage,
        'You have already applied to this opportunity',
      );
      expect(provider.applications, hasLength(1));
    },
  );

  test(
    'a second apply call for the same opportunity while one is in flight is blocked (duplicate-action protection)',
    () async {
      repository.applyDelay = const Duration(milliseconds: 50);
      repository.applyResult = _application(id: 1, opportunityId: 5);

      final first = provider.apply(opportunityId: 5, cvId: 1);
      final second = provider.apply(opportunityId: 5, cvId: 1);

      final results = await Future.wait([first, second]);

      expect(repository.applyCallCount, 1);
      expect(results.where((r) => r != null).length, 1);
      expect(results.where((r) => r == null).length, 1);
    },
  );

  test(
    'applying to a different opportunity is not blocked while another is in flight',
    () async {
      repository.applyDelay = const Duration(milliseconds: 50);
      repository.applyResult = _application(id: 1, opportunityId: 5);

      final first = provider.apply(opportunityId: 5, cvId: 1);
      final second = provider.apply(opportunityId: 6, cvId: 1);

      await Future.wait([first, second]);

      expect(repository.applyCallCount, 2);
    },
  );

  test(
    'isApplying/isSubmitting are cleared via finally after success',
    () async {
      repository.applyResult = _application(id: 1, opportunityId: 5);

      await provider.apply(opportunityId: 5, cvId: 1);

      expect(provider.isApplying(5), isFalse);
      expect(provider.isSubmitting, isFalse);
    },
  );

  test(
    'isApplying/isSubmitting are cleared via finally after failure',
    () async {
      repository.applyError = ApiException(
        'Server error, please try again later.',
      );

      await provider.apply(opportunityId: 5, cvId: 1);

      expect(provider.isApplying(5), isFalse);
      expect(provider.isSubmitting, isFalse);
    },
  );

  test(
    'loadApplicationDetails reuses an already-loaded list item without a new fetch',
    () async {
      repository.listResult = [_application(id: 7)];
      await provider.loadApplications();

      final callsBefore = repository.getStudentApplicationsCallCount;
      await provider.loadApplicationDetails(7);

      expect(provider.selectedApplication?.id, 7);
      expect(repository.getStudentApplicationsCallCount, callsBefore);
    },
  );

  test(
    'loadApplicationDetails loads the full list once when nothing is cached yet',
    () async {
      repository.listResult = [_application(id: 3), _application(id: 7)];

      await provider.loadApplicationDetails(7);

      expect(provider.selectedApplication?.id, 7);
      expect(repository.getStudentApplicationsCallCount, 1);
    },
  );

  test(
    'loadApplicationDetails surfaces not-found when the ID does not exist',
    () async {
      repository.listResult = [_application(id: 3)];

      await provider.loadApplicationDetails(999);

      expect(provider.selectedApplication, isNull);
      expect(provider.detailsErrorMessage, 'Application not found');
    },
  );

  test('reset clears all state (called on logout)', () async {
    repository.listResult = [_application(id: 1)];
    await provider.loadApplications();
    expect(provider.applications, isNotEmpty);

    await authProvider.logout();

    expect(provider.applications, isEmpty);
    expect(provider.selectedApplication, isNull);
    expect(provider.listErrorMessage, isNull);
    expect(provider.hasAppliedTo(1), isFalse);
  });

  test(
    'switching users cannot leak the previous student\'s applications',
    () async {
      repository.listResult = [_application(id: 1, opportunityId: 1)];
      await provider.loadApplications();
      expect(provider.hasAppliedTo(1), isTrue);

      await authProvider.logout();
      repository.listResult = [_application(id: 2, opportunityId: 2)];
      await provider.loadApplications();

      expect(provider.hasAppliedTo(1), isFalse);
      expect(provider.hasAppliedTo(2), isTrue);
    },
  );
}
