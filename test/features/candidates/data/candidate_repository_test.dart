// Direct unit tests for CandidateRepository, using the real Dio/ApiClient
// pipeline against a fake HTTP transport — same convention as every other
// repository test file in this project.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/candidates/data/candidate_repository.dart';

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

CandidateRepository _repositoryWithAdapter(_FakeHttpClientAdapter adapter) {
  final apiClient = ApiClient(tokenStorageService: TokenStorageService())
    ..dio.httpClientAdapter = adapter;
  return CandidateRepository(apiClient: apiClient);
}

Map<String, dynamic> _candidateJson({
  int id = 1,
  String name = 'Omar Hassan',
  bool? alreadyApplied,
  bool? alreadyInvited,
}) {
  return {
    'id': id,
    'name': name,
    'university': 'State University',
    'major': 'Computer Science',
    'graduation_year': 2026,
    'education_verification_status': 'verified',
    'skills': [
      {'name': 'PHP', 'source': 'manual'},
    ],
    'already_applied': ?alreadyApplied,
    'already_invited': ?alreadyInvited,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async {
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  group('searchCandidates', () {
    test('uses the exact documented method and path with no filters', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': []}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.searchCandidates();

      expect(adapter.lastRequest?.method, 'GET');
      expect(adapter.lastRequest?.path, '/organization/candidates');
      expect(adapter.lastRequest?.queryParameters, isEmpty);
    });

    test('sends only the provided filters', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': []}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.searchCandidates(name: 'Omar', graduationYear: 2026);

      final params = adapter.lastRequest?.queryParameters;
      expect(params?['name'], 'Omar');
      expect(params?['graduation_year'], 2026);
      expect(params?.containsKey('major'), isFalse);
      expect(params?.containsKey('skill'), isFalse);
      expect(params?.containsKey('opportunity_id'), isFalse);
    });

    test('sends opportunity_id when provided', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': []}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.searchCandidates(opportunityId: 7);

      expect(adapter.lastRequest?.queryParameters['opportunity_id'], 7);
    });

    test('parses a list of candidates', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': [
            _candidateJson(id: 1, name: 'Omar Hassan'),
            _candidateJson(id: 2, name: 'Leem Khaled'),
          ],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.searchCandidates();

      expect(result, hasLength(2));
      expect(result[0].name, 'Omar Hassan');
      expect(result[1].name, 'Leem Khaled');
    });

    test('parses skills with name and source', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': [_candidateJson()],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.searchCandidates();

      expect(result.single.skills.single.name, 'PHP');
      expect(result.single.skills.single.source, 'manual');
      expect(result.single.skills.single.evidenceLabel, 'Self-declared');
    });

    test(
      'already_applied/already_invited are null when the backend omits them',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'data': [_candidateJson()],
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        final result = await repository.searchCandidates();

        expect(result.single.alreadyApplied, isNull);
        expect(result.single.alreadyInvited, isNull);
      },
    );

    test(
      'already_applied/already_invited parse correctly when present',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'data': [
              _candidateJson(alreadyApplied: true, alreadyInvited: false),
            ],
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        final result = await repository.searchCandidates(opportunityId: 1);

        expect(result.single.alreadyApplied, isTrue);
        expect(result.single.alreadyInvited, isFalse);
      },
    );

    test('parses an empty list', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': []}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.searchCandidates();

      expect(result, isEmpty);
    });

    test('throws ApiException on a 403 (Student/Admin denied)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'This action is unauthorized for your account type',
          'data': null,
        }, 403);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.searchCandidates(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });

    test('throws with the exact 404 message for a foreign opportunity', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Opportunity not found',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.searchCandidates(opportunityId: 999),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Opportunity not found',
          ),
        ),
      );
    });
  });
}
