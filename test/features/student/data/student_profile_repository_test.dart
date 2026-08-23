// Direct unit tests for StudentProfileRepository.
//
// These exercise the real Dio/ApiClient pipeline against a fake HTTP
// transport, exactly like auth_repository_test.dart — nothing about
// ApiClient's architecture is duplicated or bypassed.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/student/data/student_profile_repository.dart';

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

StudentProfileRepository _repositoryWithAdapter(
  _FakeHttpClientAdapter adapter,
) {
  final apiClient = ApiClient(tokenStorageService: TokenStorageService())
    ..dio.httpClientAdapter = adapter;
  return StudentProfileRepository(apiClient: apiClient);
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

  group('createProfile', () {
    test('sends exactly university, major, and graduation_year', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {
            'id': 1,
            'university': 'State University',
            'major': 'Computer Science',
            'graduation_year': 2027,
          },
        }, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.createProfile(
        university: 'State University',
        major: 'Computer Science',
        graduationYear: 2027,
      );

      expect(adapter.lastRequest?.path, '/student/profile');
      final sentBody = adapter.lastRequest?.data as Map<String, dynamic>;
      expect(sentBody.keys.toSet(), {'university', 'major', 'graduation_year'});
      expect(sentBody['university'], 'State University');
      expect(sentBody['major'], 'Computer Science');
      expect(sentBody['graduation_year'], 2027);
    });

    test('never sends name, email, password, or gpa', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {
            'id': 1,
            'university': 'State University',
            'major': 'Computer Science',
            'graduation_year': 2027,
          },
        }, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.createProfile(
        university: 'State University',
        major: 'Computer Science',
        graduationYear: 2027,
      );

      final sentBody = adapter.lastRequest?.data as Map<String, dynamic>;
      expect(sentBody.containsKey('name'), isFalse);
      expect(sentBody.containsKey('email'), isFalse);
      expect(sentBody.containsKey('password'), isFalse);
      expect(sentBody.containsKey('gpa'), isFalse);
    });

    test('parses the created profile on success', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {
            'id': 42,
            'university': 'State University',
            'major': 'Computer Science',
            'graduation_year': 2027,
          },
        }, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      final profile = await repository.createProfile(
        university: 'State University',
        major: 'Computer Science',
        graduationYear: 2027,
      );

      expect(profile.id, 42);
      expect(profile.university, 'State University');
      expect(profile.major, 'Computer Science');
      expect(profile.graduationYear, 2027);
    });

    test(
      'throws with the backend message on 409 (profile already exists)',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'success': false,
            'message': 'Profile already exists',
            'data': null,
          }, 409);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.createProfile(
            university: 'State University',
            major: 'Computer Science',
            graduationYear: 2027,
          ),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 409)
                .having((e) => e.message, 'message', 'Profile already exists'),
          ),
        );
      },
    );

    test('throws with the backend message on 422 validation', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'message': 'The given data was invalid.',
          'errors': {
            'graduation_year': ['The graduation year field is required.'],
          },
        }, 422);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.createProfile(
          university: 'State University',
          major: 'Computer Science',
          graduationYear: 2027,
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.errors?['graduation_year'],
            'errors[graduation_year]',
            contains('The graduation year field is required.'),
          ),
        ),
      );
    });

    test('throws a friendly message on a 500 server error', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Server error, please try again later.',
          'data': null,
        }, 500);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.createProfile(
          university: 'State University',
          major: 'Computer Science',
          graduationYear: 2027,
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Server error, please try again later.',
          ),
        ),
      );
    });

    test('throws a connectivity message on a network failure', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'Failed host lookup',
        );
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.createProfile(
          university: 'State University',
          major: 'Computer Science',
          graduationYear: 2027,
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'No internet connection.',
          ),
        ),
      );
    });
  });

  group('getProfile', () {
    test('parses the profile on 200', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {
            'id': 7,
            'university': 'State University',
            'major': 'Computer Science',
            'graduation_year': 2027,
          },
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final profile = await repository.getProfile();

      expect(adapter.lastRequest?.path, '/student/profile');
      expect(profile?.id, 7);
    });

    test('returns null on the documented 404 (no profile yet)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Student profile not found',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      final profile = await repository.getProfile();

      expect(profile, isNull);
    });

    test('throws on a non-404 error instead of returning null', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Unauthenticated.',
          'data': null,
        }, 401);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(repository.getProfile(), throwsA(isA<ApiException>()));
    });
  });

  group('updateProfile', () {
    test('sends a PUT with university, major, graduation_year, phone, bio', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {
            'id': 1,
            'university': 'New University',
            'major': 'Computer Science',
            'graduation_year': 2028,
            'phone': '0791234567',
            'bio': 'Updated bio.',
          },
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.updateProfile(
        university: 'New University',
        major: 'Computer Science',
        graduationYear: 2028,
        phone: '0791234567',
        bio: 'Updated bio.',
      );

      expect(adapter.lastRequest?.method, 'PUT');
      expect(adapter.lastRequest?.path, '/student/profile');
      final sentBody = adapter.lastRequest?.data as Map<String, dynamic>;
      expect(sentBody['university'], 'New University');
      expect(sentBody['major'], 'Computer Science');
      expect(sentBody['graduation_year'], 2028);
      expect(sentBody['phone'], '0791234567');
      expect(sentBody['bio'], 'Updated bio.');
    });

    test('never sends name, email, password, or gpa', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {
            'id': 1,
            'university': 'New University',
            'major': 'Computer Science',
            'graduation_year': 2028,
          },
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.updateProfile(
        university: 'New University',
        major: 'Computer Science',
        graduationYear: 2028,
      );

      final sentBody = adapter.lastRequest?.data as Map<String, dynamic>;
      expect(sentBody.containsKey('name'), isFalse);
      expect(sentBody.containsKey('email'), isFalse);
      expect(sentBody.containsKey('password'), isFalse);
      expect(sentBody.containsKey('gpa'), isFalse);
    });

    test('parses the canonical updated profile on success', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {
            'id': 42,
            'university': 'New University',
            'major': 'Computer Science',
            'graduation_year': 2028,
            'phone': '0791234567',
            'bio': 'Updated bio.',
          },
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final profile = await repository.updateProfile(
        university: 'New University',
        major: 'Computer Science',
        graduationYear: 2028,
        phone: '0791234567',
        bio: 'Updated bio.',
      );

      expect(profile.id, 42);
      expect(profile.university, 'New University');
      expect(profile.phone, '0791234567');
      expect(profile.bio, 'Updated bio.');
    });

    test('throws with the backend field errors on 422 validation', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'message': 'The given data was invalid.',
          'errors': {
            'graduation_year': ['The graduation year field must be between 1950 and 2100.'],
          },
        }, 422);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.updateProfile(
          university: 'New University',
          major: 'Computer Science',
          graduationYear: 1800,
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.errors?['graduation_year'],
            'errors[graduation_year]',
            isNotNull,
          ),
        ),
      );
    });

    test('throws on 404 when the profile does not exist yet', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Student profile not found',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.updateProfile(
          university: 'New University',
          major: 'Computer Science',
          graduationYear: 2028,
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Student profile not found',
          ),
        ),
      );
    });
  });
}
