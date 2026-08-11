// Direct unit tests for StudentOfferProvider, using a fake repository (no
// real network) and a real AuthProvider (with a fake AuthRepository) so the
// reset-on-logout listener can be exercised genuinely. Mirrors
// organization_offer_provider_test.dart's structure and conventions.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/offers/data/offer_repository.dart';
import 'package:opportunityhub_flutter/models/offer_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/student_offer_provider.dart';

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
    // `isAuthenticated` to false, not the real network/secure-storage
    // calls that would otherwise require a platform-channel binding.
  }
}

OfferModel _offer({int id = 1, int applicationId = 5, String status = 'sent'}) {
  return OfferModel(
    id: id,
    applicationId: applicationId,
    status: status,
    sentAt: DateTime(2026, 8, 10, 9),
  );
}

class _FakeOfferRepository extends OfferRepository {
  _FakeOfferRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  ApiException? loadError;
  Object? loadRuntimeError;
  int getOfferCallCount = 0;
  final List<int> requestedApplicationIds = [];

  /// Per-application overrides — when set for a given ID, take priority
  /// over the single [loadResult]/no-delay defaults. Lets a test give two
  /// different applications two different results and/or delays, to
  /// exercise the stale-response-must-not-win scenario.
  Map<int, OfferModel?>? resultsByApplication;
  Map<int, Duration>? delaysByApplication;
  OfferModel? loadResult;

  OfferModel? acceptResult;
  ApiException? acceptError;
  Object? acceptRuntimeError;
  int acceptCallCount = 0;
  final List<int> acceptedOfferIds = [];

  OfferModel? declineResult;
  ApiException? declineError;
  Object? declineRuntimeError;
  int declineCallCount = 0;
  final List<int> declinedOfferIds = [];

  @override
  Future<OfferModel> getStudentOffer(int applicationId) async {
    getOfferCallCount++;
    requestedApplicationIds.add(applicationId);

    final delay = delaysByApplication?[applicationId] ?? Duration.zero;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (loadRuntimeError != null) throw loadRuntimeError!;
    if (loadError != null) throw loadError!;

    final OfferModel? result;
    if (resultsByApplication != null) {
      result = resultsByApplication![applicationId];
    } else {
      result = loadResult;
    }
    if (result == null) {
      throw ApiException('Offer not found', statusCode: 404);
    }
    return result;
  }

  @override
  Future<OfferModel> acceptStudentOffer(int offerId) async {
    acceptCallCount++;
    acceptedOfferIds.add(offerId);
    if (acceptRuntimeError != null) throw acceptRuntimeError!;
    if (acceptError != null) throw acceptError!;
    return acceptResult ?? _offer(status: 'accepted');
  }

  @override
  Future<OfferModel> declineStudentOffer(int offerId) async {
    declineCallCount++;
    declinedOfferIds.add(offerId);
    if (declineRuntimeError != null) throw declineRuntimeError!;
    if (declineError != null) throw declineError!;
    return declineResult ?? _offer(status: 'declined');
  }
}

void main() {
  late AuthProvider authProvider;
  late _FakeOfferRepository repository;
  late StudentOfferProvider provider;

  setUp(() {
    authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    repository = _FakeOfferRepository();
    provider = StudentOfferProvider(
      repository: repository,
      authProvider: authProvider,
    );
  });

  test('initial state is empty and idle', () {
    expect(provider.offer, isNull);
    expect(provider.loadedApplicationId, isNull);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.isResponding, isFalse);
    expect(provider.actionErrorMessage, isNull);
  });

  test('loading an existing Offer populates state', () async {
    repository.loadResult = _offer(applicationId: 5);

    await provider.loadForApplication(5);

    expect(provider.offer, isNotNull);
    expect(provider.offer!.applicationId, 5);
    expect(provider.loadedApplicationId, 5);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.hasOfferFor(5), isTrue);
  });

  test(
    'a 404 (no Offer yet) is represented correctly, not as an error',
    () async {
      await provider.loadForApplication(5);

      expect(provider.offer, isNull);
      expect(provider.errorMessage, isNull);
      expect(provider.hasOfferFor(5), isFalse);
    },
  );

  test('a non-404 load failure surfaces the error and is retryable', () async {
    repository.loadError = ApiException(
      'Server error, please try again.',
      statusCode: 500,
    );

    await provider.loadForApplication(5);

    expect(provider.errorMessage, 'Server error, please try again.');
    expect(provider.offer, isNull);

    repository.loadError = null;
    repository.loadResult = _offer(applicationId: 5);
    await provider.loadForApplication(5, forceRefresh: true);

    expect(provider.errorMessage, isNull);
    expect(provider.offer, isNotNull);
  });

  test('malformed load data never leaves the provider stuck loading', () async {
    repository.loadRuntimeError = TypeError();

    await provider.loadForApplication(5);

    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNotNull);
    expect(provider.errorMessage, isNot(contains('TypeError')));
  });

  test('forceRefresh starts a new fetch even while unchanged', () async {
    repository.loadResult = _offer(applicationId: 5);

    await provider.loadForApplication(5);
    await provider.loadForApplication(5, forceRefresh: true);

    expect(repository.getOfferCallCount, 2);
  });

  test(
    'concurrent duplicate loads for the same application are prevented',
    () async {
      repository.loadResult = _offer(applicationId: 5);

      final first = provider.loadForApplication(5);
      final second = provider.loadForApplication(5);
      await Future.wait([first, second]);

      expect(repository.getOfferCallCount, 1);
    },
  );

  test(
    'loading application 5 then application 9 loads application 9 correctly, not application 5\'s in-flight future',
    () async {
      repository.delaysByApplication = {5: const Duration(milliseconds: 100)};
      repository.resultsByApplication = {
        5: _offer(id: 1, applicationId: 5),
        9: _offer(id: 2, applicationId: 9),
      };

      final firstCall = provider.loadForApplication(5);
      final secondCall = provider.loadForApplication(9);
      await Future.wait([firstCall, secondCall]);

      expect(provider.offer?.applicationId, 9);
      expect(provider.loadedApplicationId, 9);
      expect(repository.requestedApplicationIds, containsAll([5, 9]));
    },
  );

  test(
    'a slower stale response for application 5 cannot overwrite the newer application 9 state',
    () async {
      repository.resultsByApplication = {
        9: _offer(id: 9, applicationId: 9),
        5: _offer(id: 5, applicationId: 5),
      };

      await provider.loadForApplication(9);
      expect(provider.offer?.applicationId, 9);

      repository.delaysByApplication = {5: const Duration(milliseconds: 100)};
      final staleCall = provider.loadForApplication(5);

      // Switch back to application 9 before the stale application-5
      // response arrives.
      await provider.loadForApplication(9, forceRefresh: true);
      expect(provider.offer?.applicationId, 9);

      await staleCall;

      expect(provider.offer?.applicationId, 9);
      expect(provider.loadedApplicationId, 9);
    },
  );

  test('accept with no Offer loaded is a no-op', () async {
    final success = await provider.accept();

    expect(success, isFalse);
    expect(repository.acceptCallCount, 0);
  });

  test('decline with no Offer loaded is a no-op', () async {
    final success = await provider.decline();

    expect(success, isFalse);
    expect(repository.declineCallCount, 0);
  });

  test(
    'accept success replaces the Offer with the accepted response',
    () async {
      repository.loadResult = _offer(id: 3, applicationId: 5, status: 'sent');
      await provider.loadForApplication(5);

      repository.acceptResult = _offer(
        id: 3,
        applicationId: 5,
        status: 'accepted',
      );
      final success = await provider.accept();

      expect(success, isTrue);
      expect(provider.offer?.status, 'accepted');
      expect(repository.acceptedOfferIds, [3]);
      expect(provider.actionErrorMessage, isNull);
    },
  );

  test(
    'decline success replaces the Offer with the declined response',
    () async {
      repository.loadResult = _offer(id: 3, applicationId: 5, status: 'sent');
      await provider.loadForApplication(5);

      repository.declineResult = _offer(
        id: 3,
        applicationId: 5,
        status: 'declined',
      );
      final success = await provider.decline();

      expect(success, isTrue);
      expect(provider.offer?.status, 'declined');
      expect(repository.declinedOfferIds, [3]);
      expect(provider.actionErrorMessage, isNull);
    },
  );

  test('a duplicate response attempt for the same Offer is blocked', () async {
    repository.loadResult = _offer(id: 3, applicationId: 5, status: 'sent');
    await provider.loadForApplication(5);

    // Neither accept() nor decline() should overlap while one is already
    // in flight -- simulate by not awaiting the first call before firing
    // the second.
    final first = provider.accept();
    final second = provider.accept();

    final results = await Future.wait([first, second]);

    expect(repository.acceptCallCount, 1);
    expect(results.where((success) => success).length, 1);
    expect(results.where((success) => !success).length, 1);
  });

  test('accept failure keeps the previous Offer state', () async {
    repository.loadResult = _offer(id: 3, applicationId: 5, status: 'sent');
    await provider.loadForApplication(5);

    repository.acceptError = ApiException('Server error.');
    final success = await provider.accept();

    expect(success, isFalse);
    expect(provider.offer?.status, 'sent');
    expect(provider.actionErrorMessage, 'Server error.');
  });

  test('decline failure keeps the previous Offer state', () async {
    repository.loadResult = _offer(id: 3, applicationId: 5, status: 'sent');
    await provider.loadForApplication(5);

    repository.declineError = ApiException('Server error.');
    final success = await provider.decline();

    expect(success, isFalse);
    expect(provider.offer?.status, 'sent');
    expect(provider.actionErrorMessage, 'Server error.');
  });

  test('accept unexpected failure exposes a safe message', () async {
    repository.loadResult = _offer(id: 3, applicationId: 5, status: 'sent');
    await provider.loadForApplication(5);

    repository.acceptRuntimeError = TypeError();
    final success = await provider.accept();

    expect(success, isFalse);
    expect(provider.actionErrorMessage, isNotNull);
    expect(provider.actionErrorMessage, isNot(contains('TypeError')));
    expect(
      provider.actionErrorMessage,
      'Something went wrong. Please try again.',
    );
  });

  test(
    'a 409 (already responded) refreshes the Offer in the background',
    () async {
      repository.loadResult = _offer(id: 3, applicationId: 5, status: 'sent');
      await provider.loadForApplication(5);

      repository.acceptError = ApiException(
        'This offer has already been responded to.',
        statusCode: 409,
      );
      // Set before calling accept() -- the 409 handler's background
      // refresh is fire-and-forget and starts synchronously inside the
      // catch block, so the new result must already be in place by then.
      repository.loadResult = _offer(
        id: 3,
        applicationId: 5,
        status: 'declined',
      );

      final success = await provider.accept();
      expect(success, isFalse);

      // The background refresh is fire-and-forget; wait for it to land.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(provider.offer?.status, 'declined');
      expect(repository.getOfferCallCount, greaterThanOrEqualTo(2));
      // No duplicate accept call was ever attempted by the provider itself.
      expect(repository.acceptCallCount, 1);
    },
  );

  test('reset clears all state (called on logout)', () async {
    repository.loadResult = _offer(applicationId: 5);
    await provider.loadForApplication(5);
    expect(provider.offer, isNotNull);

    await authProvider.logout();

    expect(provider.offer, isNull);
    expect(provider.loadedApplicationId, isNull);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.isResponding, isFalse);
    expect(provider.actionErrorMessage, isNull);
  });

  test('clearActionError clears the action error message', () async {
    repository.loadResult = _offer(id: 3, applicationId: 5, status: 'sent');
    await provider.loadForApplication(5);
    repository.acceptError = ApiException('Server error.');
    await provider.accept();
    expect(provider.actionErrorMessage, isNotNull);

    provider.clearActionError();

    expect(provider.actionErrorMessage, isNull);
  });

  test(
    'dispose removes the AuthProvider listener (no error on logout after dispose)',
    () async {
      provider.dispose();

      await expectLater(authProvider.logout(), completes);
    },
  );
}
