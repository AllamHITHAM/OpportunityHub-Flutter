// Direct unit tests for OrganizationOfferProvider, using a fake repository
// (no real network) and a real AuthProvider (with a fake AuthRepository) so
// the reset-on-logout listener can be exercised genuinely. Mirrors
// organization_assessment_provider_test.dart's structure and conventions.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/offers/data/offer_repository.dart';
import 'package:opportunityhub_flutter/features/offers/data/send_offer_input.dart';
import 'package:opportunityhub_flutter/models/offer_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_offer_provider.dart';

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

OfferModel _offer({
  int id = 1,
  int applicationId = 5,
  String status = 'sent',
  String? title = 'Backend Engineer',
}) {
  return OfferModel(
    id: id,
    applicationId: applicationId,
    title: title,
    status: status,
    sentAt: DateTime(2026, 8, 10, 9),
  );
}

SendOfferInput _validInput() {
  return SendOfferInput(title: 'Backend Engineer', message: 'Welcome aboard.');
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

  OfferModel? sendResult;
  ApiException? sendError;
  Object? sendRuntimeError;
  Duration sendDelay = Duration.zero;
  int sendCallCount = 0;
  SendOfferInput? lastSendInput;

  @override
  Future<OfferModel> getOrganizationOffer(int applicationId) async {
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
      throw ApiException('This application has no offer yet', statusCode: 404);
    }
    return result;
  }

  @override
  Future<OfferModel> sendOrganizationOffer({
    required int applicationId,
    required SendOfferInput input,
  }) async {
    sendCallCount++;
    lastSendInput = input;
    if (sendDelay > Duration.zero) {
      await Future<void>.delayed(sendDelay);
    }
    if (sendRuntimeError != null) throw sendRuntimeError!;
    if (sendError != null) throw sendError!;
    return sendResult ?? _offer(applicationId: applicationId);
  }
}

void main() {
  late AuthProvider authProvider;
  late _FakeOfferRepository repository;
  late OrganizationOfferProvider provider;

  setUp(() {
    authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    repository = _FakeOfferRepository();
    provider = OrganizationOfferProvider(
      repository: repository,
      authProvider: authProvider,
    );
  });

  test('initial state is empty and idle', () {
    expect(provider.offer, isNull);
    expect(provider.loadedApplicationId, isNull);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.isSending, isFalse);
    expect(provider.actionErrorMessage, isNull);
    expect(provider.fieldErrors, isEmpty);
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
      'Application not found',
      statusCode: 403,
    );

    await provider.loadForApplication(5);

    expect(provider.errorMessage, 'Application not found');
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

  test('sendOffer success sets the offer and loadedApplicationId', () async {
    repository.sendResult = _offer(applicationId: 5, title: 'Backend Engineer');

    final success = await provider.sendOffer(
      applicationId: 5,
      input: _validInput(),
    );

    expect(success, isTrue);
    expect(provider.offer, isNotNull);
    expect(provider.offer!.applicationId, 5);
    expect(provider.offer!.title, 'Backend Engineer');
    expect(provider.loadedApplicationId, 5);
    expect(provider.actionErrorMessage, isNull);
    expect(provider.fieldErrors, isEmpty);
    expect(repository.lastSendInput, isNotNull);
  });

  test('sendOffer validation error exposes field errors', () async {
    repository.sendError = ApiException(
      'The given data was invalid.',
      statusCode: 422,
      errors: {
        'salary_currency': [
          'The salary currency field is required when salary amount is present.',
        ],
      },
    );

    final success = await provider.sendOffer(
      applicationId: 5,
      input: _validInput(),
    );

    expect(success, isFalse);
    expect(provider.fieldErrors['salary_currency'], isNotNull);
    expect(provider.offer, isNull);
  });

  test('sendOffer API failure exposes the backend message', () async {
    repository.sendError = ApiException(
      'An offer already exists for this application',
      statusCode: 409,
    );

    final success = await provider.sendOffer(
      applicationId: 5,
      input: _validInput(),
    );

    expect(success, isFalse);
    expect(
      provider.actionErrorMessage,
      'An offer already exists for this application',
    );
    expect(provider.offer, isNull);
  });

  test(
    'sendOffer 409 triggers a background refresh that picks up the real Offer',
    () async {
      repository.sendError = ApiException(
        'An offer already exists for this application',
        statusCode: 409,
      );
      repository.loadResult = _offer(applicationId: 5, status: 'sent');

      final success = await provider.sendOffer(
        applicationId: 5,
        input: _validInput(),
      );
      expect(success, isFalse);

      // The background refresh is fire-and-forget; wait for it to land.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(provider.offer, isNotNull);
      expect(provider.offer!.applicationId, 5);
      expect(repository.getOfferCallCount, greaterThanOrEqualTo(1));
    },
  );

  test('sendOffer unexpected failure exposes a safe message', () async {
    repository.sendRuntimeError = TypeError();

    final success = await provider.sendOffer(
      applicationId: 5,
      input: _validInput(),
    );

    expect(success, isFalse);
    expect(provider.actionErrorMessage, isNotNull);
    expect(provider.actionErrorMessage, isNot(contains('TypeError')));
    expect(
      provider.actionErrorMessage,
      'Something went wrong. Please try again.',
    );
  });

  test(
    'a duplicate send submission for the same application is blocked',
    () async {
      repository.sendDelay = const Duration(milliseconds: 50);
      repository.sendResult = _offer(applicationId: 5);

      final first = provider.sendOffer(applicationId: 5, input: _validInput());
      final second = provider.sendOffer(applicationId: 5, input: _validInput());

      final results = await Future.wait([first, second]);

      expect(repository.sendCallCount, 1);
      expect(results.where((success) => success).length, 1);
      expect(results.where((success) => !success).length, 1);
    },
  );

  test(
    'a previously-visible "no Offer" state is unaffected by a failed send',
    () async {
      await provider.loadForApplication(5);
      expect(provider.offer, isNull);

      repository.sendError = ApiException('Server error.');
      await provider.sendOffer(applicationId: 5, input: _validInput());

      expect(provider.offer, isNull);
    },
  );

  test(
    'clearActionErrors clears both the action error and field errors',
    () async {
      repository.sendError = ApiException(
        'The given data was invalid.',
        statusCode: 422,
        errors: {
          'title': ['The title must not be greater than 255 characters.'],
        },
      );
      await provider.sendOffer(applicationId: 5, input: _validInput());
      expect(provider.actionErrorMessage, isNotNull);
      expect(provider.fieldErrors, isNotEmpty);

      provider.clearActionErrors();

      expect(provider.actionErrorMessage, isNull);
      expect(provider.fieldErrors, isEmpty);
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
    expect(provider.isSending, isFalse);
    expect(provider.actionErrorMessage, isNull);
    expect(provider.fieldErrors, isEmpty);
  });

  test(
    'dispose removes the AuthProvider listener (no error on logout after dispose)',
    () async {
      provider.dispose();

      await expectLater(authProvider.logout(), completes);
    },
  );
}
