// Direct unit tests for CvRepository.
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
import 'package:opportunityhub_flutter/features/cv/data/cv_repository.dart';

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

CvRepository _repositoryWithAdapter(_FakeHttpClientAdapter adapter) {
  final apiClient = ApiClient(tokenStorageService: TokenStorageService())
    ..dio.httpClientAdapter = adapter;
  return CvRepository(apiClient: apiClient);
}

Map<String, dynamic> _cvJson({
  int id = 1,
  int studentId = 1,
  String title = 'My CV',
  String filePath = 'cvs/my-cv.pdf',
  dynamic version = 1,
  dynamic isDefault = false,
  dynamic createdByAi = false,
}) {
  return {
    'id': id,
    'student_id': studentId,
    'title': title,
    'file_path': filePath,
    'version': version,
    'is_default': isDefault,
    'created_by_ai': createdByAi,
    'created_at': '2026-07-01T10:00:00.000000Z',
    'updated_at': '2026-07-01T10:00:00.000000Z',
  };
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

  group('getStudentCvs', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': []}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.getStudentCvs();

      expect(adapter.lastRequest?.method, 'GET');
      expect(adapter.lastRequest?.path, '/student/cvs');
    });

    test('parses a valid CV list', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': [
            _cvJson(id: 1, title: 'CV One'),
            _cvJson(id: 2, title: 'CV Two'),
          ],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getStudentCvs();

      expect(result, hasLength(2));
      expect(result[0].id, 1);
      expect(result[0].title, 'CV One');
      expect(result[1].id, 2);
      expect(result[1].title, 'CV Two');
    });

    test(
      'parses boolean and integer fields safely from string forms',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'data': [_cvJson(version: '3', isDefault: 1, createdByAi: 'true')],
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        final result = await repository.getStudentCvs();

        expect(result.single.version, 3);
        expect(result.single.version, isA<int>());
        expect(result.single.isDefault, isTrue);
        expect(result.single.createdByAi, isTrue);
      },
    );

    test('parses an empty list', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': []}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getStudentCvs();

      expect(result, isEmpty);
    });

    test(
      'malformed response data is never silently swallowed (surfaces as an error)',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'data': [
              {'id': 1},
            ],
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        // Missing required fields fail the parse loudly (a TypeError from
        // the failed cast), exactly like every other repository in this
        // project — there is no silent fallback to an empty/default CV.
        await expectLater(repository.getStudentCvs(), throwsA(anything));
      },
    );

    test('throws ApiException on a server error', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Server error, please try again later.',
          'data': null,
        }, 500);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getStudentCvs(),
        throwsA(isA<ApiException>()),
      );
    });

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
        repository.getStudentCvs(),
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
        repository.getStudentCvs(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });

    test('throws ApiException on a 404', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'You must create a student profile first',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getStudentCvs(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'You must create a student profile first',
          ),
        ),
      );
    });
  });

  group('createCv', () {
    test('sends the correct POST body', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _cvJson()}, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.createCv(
        title: 'Software Engineer CV',
        filePath: 'cvs/software-engineer.pdf',
      );

      expect(adapter.lastRequest?.method, 'POST');
      expect(adapter.lastRequest?.path, '/student/cvs');
      final body = adapter.lastRequest?.data as Map<String, dynamic>;
      expect(body, {
        'title': 'Software Engineer CV',
        'file_path': 'cvs/software-engineer.pdf',
      });
    });

    test('returns the parsed created CV', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _cvJson(id: 9, title: 'New CV')}, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.createCv(
        title: 'New CV',
        filePath: 'cvs/new.pdf',
      );

      expect(result.id, 9);
      expect(result.title, 'New CV');
    });

    test('throws with the backend message on 422 validation', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'message': 'The given data was invalid.',
          'errors': {
            'title': ['The title field is required.'],
          },
        }, 422);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.createCv(title: '', filePath: 'cvs/new.pdf'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.errors?['title'],
            'errors[title]',
            contains('The title field is required.'),
          ),
        ),
      );
    });
  });

  group('deleteCv', () {
    test('calls the correct delete endpoint', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': true,
          'message': 'CV deleted successfully',
          'data': null,
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.deleteCv(5);

      expect(adapter.lastRequest?.method, 'DELETE');
      expect(adapter.lastRequest?.path, '/student/cvs/5');
    });

    test(
      'preserves the exact backend 409 message when the CV is in use',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'success': false,
            'message':
                'Cannot delete a CV that has been used in an application',
            'data': null,
          }, 409);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.deleteCv(5),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 409)
                .having(
                  (e) => e.message,
                  'message',
                  'Cannot delete a CV that has been used in an application',
                ),
          ),
        );
      },
    );

    test('throws on the documented 404 (not found / not yours)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'CV not found',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(repository.deleteCv(999), throwsA(isA<ApiException>()));
    });
  });

  group('setDefaultCv', () {
    test('calls the correct set-default endpoint', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _cvJson(id: 5, isDefault: true)}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.setDefaultCv(5);

      expect(adapter.lastRequest?.method, 'PUT');
      expect(adapter.lastRequest?.path, '/student/cvs/5/default');
      expect(result.isDefault, isTrue);
    });

    test('throws on the documented 404 (not found / not yours)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'CV not found',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.setDefaultCv(999),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
