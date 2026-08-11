// Direct unit tests for OfferRepository.
//
// These exercise the real Dio/ApiClient pipeline against a fake HTTP
// transport, exactly like the other repository test files in this project
// — nothing about ApiClient's architecture is duplicated or bypassed.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/offers/data/offer_repository.dart';
import 'package:opportunityhub_flutter/features/offers/data/send_offer_input.dart';

const _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  RequestOptions? lastRequest;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return handler(options);
  }
}

ResponseBody _jsonResponse(Map<String, dynamic> body, int statusCode) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

OfferRepository _repositoryWithAdapter(_FakeHttpClientAdapter adapter) {
  final apiClient = ApiClient(tokenStorageService: TokenStorageService())
    ..dio.httpClientAdapter = adapter;
  return OfferRepository(apiClient: apiClient);
}

Map<String, dynamic> _offerJson({
  int id = 1,
  int applicationId = 5,
  String? title = 'Backend Engineer',
  String? salaryAmount = '90000.00',
  String? salaryCurrency = 'USD',
  String? salaryPeriod = 'yearly',
  String? startDate = '2026-09-01T00:00:00.000000Z',
  String? message = 'Welcome aboard.',
  String status = 'sent',
  String? sentAt = '2026-08-10T09:00:00.000000Z',
  String? respondedAt,
}) {
  return {
    'id': id,
    'application_id': applicationId,
    'title': title,
    'salary_amount': salaryAmount,
    'salary_currency': salaryCurrency,
    'salary_period': salaryPeriod,
    'start_date': startDate,
    'message': message,
    'status': status,
    'sent_at': sentAt,
    'responded_at': respondedAt,
    'created_at': '2026-08-10T09:00:00.000000Z',
    'updated_at': '2026-08-10T09:00:00.000000Z',
  };
}

SendOfferInput _validInput() {
  return SendOfferInput(
    title: 'Backend Engineer',
    salaryAmount: 90000,
    salaryCurrency: 'USD',
    salaryPeriod: 'yearly',
    startDate: DateTime(2026, 9, 1),
    message: 'Welcome aboard.',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async {
          if (call.method == 'read') return null;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  group('getOrganizationOffer', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _offerJson()}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.getOrganizationOffer(5);

      expect(adapter.lastRequest?.method, 'GET');
      expect(adapter.lastRequest?.path, '/organization/applications/5/offer');
    });

    test('parses a valid Offer', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _offerJson()}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getOrganizationOffer(5);

      expect(result.id, 1);
      expect(result.applicationId, 5);
      expect(result.status, 'sent');
      expect(result.salaryAmount, '90000.00');
    });

    test('throws ApiException on a 404 (no Offer yet)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'This application has no offer yet',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getOrganizationOffer(5),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having(
                (e) => e.message,
                'message',
                'This application has no offer yet',
              ),
        ),
      );
    });

    test(
      'a malformed successful response never becomes a fake Offer',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'data': {'id': 'not-an-int'},
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.getOrganizationOffer(5),
          throwsA(isA<TypeError>()),
        );
      },
    );

    test('throws ApiException on a 401', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Unauthenticated',
          'data': null,
        }, 401);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getOrganizationOffer(5),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('throws ApiException on a 403', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'This action is unauthorized for your account type',
          'data': null,
        }, 403);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getOrganizationOffer(5),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });
  });

  group('sendOrganizationOffer', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _offerJson()}, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.sendOrganizationOffer(
        applicationId: 5,
        input: _validInput(),
      );

      expect(adapter.lastRequest?.method, 'POST');
      expect(adapter.lastRequest?.path, '/organization/applications/5/offer');
    });

    test('sends the exact request body', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _offerJson()}, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.sendOrganizationOffer(
        applicationId: 5,
        input: _validInput(),
      );

      final body = adapter.lastRequest?.data as Map<String, dynamic>;
      expect(body['title'], 'Backend Engineer');
      expect(body['salary_amount'], 90000);
      expect(body['salary_currency'], 'USD');
      expect(body['salary_period'], 'yearly');
      expect(body['start_date'], '2026-09-01');
      expect(body['message'], 'Welcome aboard.');
    });

    test('parses the returned Offer', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _offerJson(status: 'sent')}, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.sendOrganizationOffer(
        applicationId: 5,
        input: _validInput(),
      );

      expect(result.status, 'sent');
      expect(result.applicationId, 5);
    });

    test('preserves field validation errors on a 422', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'message': 'The given data was invalid.',
          'errors': {
            'salary_currency': [
              'The salary currency field is required when salary amount is present.',
            ],
          },
        }, 422);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.sendOrganizationOffer(
          applicationId: 5,
          input: _validInput(),
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.errors?['salary_currency'],
            'errors[salary_currency]',
            isNotNull,
          ),
        ),
      );
    });

    test('throws with the exact 409 message on a duplicate Offer', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'An offer already exists for this application',
          'data': null,
        }, 409);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.sendOrganizationOffer(
          applicationId: 5,
          input: _validInput(),
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having(
                (e) => e.message,
                'message',
                'An offer already exists for this application',
              ),
        ),
      );
    });

    test(
      'throws ApiException on a 404 (application not owned/missing)',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'success': false,
            'message': 'Application not found',
            'data': null,
          }, 404);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.sendOrganizationOffer(
            applicationId: 5,
            input: _validInput(),
          ),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 404)
                .having((e) => e.message, 'message', 'Application not found'),
          ),
        );
      },
    );

    test('malformed success response is never silently swallowed', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {'id': 'not-an-int'},
        }, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.sendOrganizationOffer(
          applicationId: 5,
          input: _validInput(),
        ),
        throwsA(anything),
      );
    });
  });
}
