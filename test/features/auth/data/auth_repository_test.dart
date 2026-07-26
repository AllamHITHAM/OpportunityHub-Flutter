// Direct unit tests for AuthRepository.registerStudent().
//
// These exercise the real Dio/ApiClient pipeline against a fake HTTP
// transport — Dio's own `HttpClientAdapter` extension point, swapped onto
// an otherwise-real `ApiClient`/`Dio` instance. No mocking package is
// added; nothing about `ApiClient`'s architecture is changed. This lets
// the request body and response parsing be genuinely verified, rather
// than bypassed with a fake repository.
//
// `TokenStorageService` talks to `flutter_secure_storage` over a platform
// channel, which has no real implementation registered under `flutter
// test`. `ApiClient`'s own request interceptor calls
// `tokenStorageService.readToken()` on every request, so even the HTTP
// tests below need a working (mocked) channel, not just the "token
// stored" test — hence the mock handler covering the whole file.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';

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

AuthRepository _repositoryWithAdapter(
  _FakeHttpClientAdapter adapter,
  TokenStorageService tokenStorageService,
) {
  final apiClient = ApiClient(tokenStorageService: tokenStorageService)
    ..dio.httpClientAdapter = adapter;
  return AuthRepository(
    apiClient: apiClient,
    tokenStorageService: tokenStorageService,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // An in-memory stand-in for the platform's secure storage, since no real
  // implementation is registered under `flutter test`. Reset before every
  // test so nothing leaks between them.
  late Map<String, String> secureStorageBackingMap;

  setUp(() {
    secureStorageBackingMap = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async {
          switch (call.method) {
            case 'write':
              final args = call.arguments as Map<Object?, Object?>;
              secureStorageBackingMap[args['key'] as String] =
                  args['value'] as String;
              return null;
            case 'read':
              final args = call.arguments as Map<Object?, Object?>;
              return secureStorageBackingMap[args['key'] as String];
            case 'delete':
              final args = call.arguments as Map<Object?, Object?>;
              secureStorageBackingMap.remove(args['key'] as String);
              return null;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  test('sends only name, email, password, and password_confirmation', () async {
    final adapter = _FakeHttpClientAdapter((options) {
      return _jsonResponse({
        'data': {
          'user': {
            'id': 1,
            'name': 'Jane Doe',
            'email': 'jane@example.com',
            'role': 'student',
            'status': 'active',
          },
          'token': 'test-token',
        },
      }, 201);
    });
    final repository = _repositoryWithAdapter(adapter, TokenStorageService());

    await repository.registerStudent(
      name: 'Jane Doe',
      email: 'jane@example.com',
      password: 'password123',
    );

    expect(adapter.lastRequest?.path, '/register/student');
    final sentBody = adapter.lastRequest?.data as Map<String, dynamic>;
    expect(sentBody.keys.toSet(), {
      'name',
      'email',
      'password',
      'password_confirmation',
    });
    expect(sentBody['name'], 'Jane Doe');
    expect(sentBody['email'], 'jane@example.com');
    expect(sentBody['password'], 'password123');
    expect(sentBody['password_confirmation'], 'password123');
  });

  test('saves the token and returns the user on success', () async {
    final adapter = _FakeHttpClientAdapter((options) {
      return _jsonResponse({
        'data': {
          'user': {
            'id': 42,
            'name': 'Jane Doe',
            'email': 'jane@example.com',
            'role': 'student',
            'status': 'active',
          },
          'token': 'saved-token-value',
        },
      }, 201);
    });
    final tokenStorageService = TokenStorageService();
    final repository = _repositoryWithAdapter(adapter, tokenStorageService);

    final user = await repository.registerStudent(
      name: 'Jane Doe',
      email: 'jane@example.com',
      password: 'password123',
    );

    expect(user.id, 42);
    expect(user.role, 'student');
    expect(await tokenStorageService.readToken(), 'saved-token-value');
  });

  test(
    'throws with the backend message on 422 validation (e.g. duplicate email)',
    () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'message': 'The given data was invalid.',
          'errors': {
            'email': ['The email has already been taken.'],
          },
        }, 422);
      });
      final tokenStorageService = TokenStorageService();
      final repository = _repositoryWithAdapter(adapter, tokenStorageService);

      await expectLater(
        repository.registerStudent(
          name: 'Jane Doe',
          email: 'jane@example.com',
          password: 'password123',
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 422)
              .having(
                (e) => e.errors?['email'],
                'errors[email]',
                contains('The email has already been taken.'),
              ),
        ),
      );
      expect(await tokenStorageService.readToken(), isNull);
    },
  );

  test('throws a friendly message on a 500 server error', () async {
    final adapter = _FakeHttpClientAdapter((options) {
      return _jsonResponse({
        'success': false,
        'message': 'Server error, please try again later.',
        'data': null,
      }, 500);
    });
    final repository = _repositoryWithAdapter(adapter, TokenStorageService());

    await expectLater(
      repository.registerStudent(
        name: 'Jane Doe',
        email: 'jane@example.com',
        password: 'password123',
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
    final repository = _repositoryWithAdapter(adapter, TokenStorageService());

    await expectLater(
      repository.registerStudent(
        name: 'Jane Doe',
        email: 'jane@example.com',
        password: 'password123',
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

  test('throws with the backend message on 400 bad request', () async {
    final adapter = _FakeHttpClientAdapter((options) {
      return _jsonResponse({
        'success': false,
        'message': 'Malformed request.',
        'data': null,
      }, 400);
    });
    final repository = _repositoryWithAdapter(adapter, TokenStorageService());

    await expectLater(
      repository.registerStudent(
        name: 'Jane Doe',
        email: 'jane@example.com',
        password: 'password123',
      ),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'Malformed request.',
        ),
      ),
    );
  });

  group('registerOrganization', () {
    test(
      'sends the exact documented account + organization-profile fields',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'data': {
              'user': {
                'id': 1,
                'name': 'Jane Recruiter',
                'email': 'jane@acme.example.com',
                'role': 'organization',
                'status': 'active',
              },
              'token': 'test-token',
            },
          }, 201);
        });
        final repository = _repositoryWithAdapter(
          adapter,
          TokenStorageService(),
        );

        await repository.registerOrganization(
          name: 'Jane Recruiter',
          email: 'jane@acme.example.com',
          password: 'password123',
          organizationName: 'Acme Corp',
          organizationType: 'company',
          industry: 'Software',
          website: 'https://acme.example.com',
        );

        expect(adapter.lastRequest?.path, '/register/organization');
        final sentBody = adapter.lastRequest?.data as Map<String, dynamic>;
        expect(sentBody.keys.toSet(), {
          'name',
          'email',
          'password',
          'password_confirmation',
          'organization_name',
          'organization_type',
          'industry',
          'website',
        });
        expect(sentBody['name'], 'Jane Recruiter');
        expect(sentBody['email'], 'jane@acme.example.com');
        expect(sentBody['password'], 'password123');
        expect(sentBody['password_confirmation'], 'password123');
        expect(sentBody['organization_name'], 'Acme Corp');
        expect(sentBody['organization_type'], 'company');
        expect(sentBody['industry'], 'Software');
        expect(sentBody['website'], 'https://acme.example.com');
      },
    );

    test(
      'omits null/blank optional fields entirely rather than sending them empty',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'data': {
              'user': {
                'id': 1,
                'name': 'Jane Recruiter',
                'email': 'jane@acme.example.com',
                'role': 'organization',
                'status': 'active',
              },
              'token': 'test-token',
            },
          }, 201);
        });
        final repository = _repositoryWithAdapter(
          adapter,
          TokenStorageService(),
        );

        await repository.registerOrganization(
          name: 'Jane Recruiter',
          email: 'jane@acme.example.com',
          password: 'password123',
          organizationName: 'Acme Corp',
          organizationType: 'company',
        );

        final sentBody = adapter.lastRequest?.data as Map<String, dynamic>;
        expect(sentBody.keys.toSet(), {
          'name',
          'email',
          'password',
          'password_confirmation',
          'organization_name',
          'organization_type',
        });
        expect(sentBody.containsKey('industry'), isFalse);
        expect(sentBody.containsKey('description'), isFalse);
        expect(sentBody.containsKey('website'), isFalse);
        expect(sentBody.containsKey('phone'), isFalse);
      },
    );

    test('saves the token and returns the user on success', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {
            'user': {
              'id': 42,
              'name': 'Jane Recruiter',
              'email': 'jane@acme.example.com',
              'role': 'organization',
              'status': 'active',
            },
            'token': 'saved-org-token-value',
          },
        }, 201);
      });
      final tokenStorageService = TokenStorageService();
      final repository = _repositoryWithAdapter(adapter, tokenStorageService);

      final user = await repository.registerOrganization(
        name: 'Jane Recruiter',
        email: 'jane@acme.example.com',
        password: 'password123',
        organizationName: 'Acme Corp',
        organizationType: 'company',
      );

      expect(user.id, 42);
      expect(user.role, 'organization');
      expect(await tokenStorageService.readToken(), 'saved-org-token-value');
    });

    test('throws with the backend message on 422 validation', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'message': 'The given data was invalid.',
          'errors': {
            'organization_name': ['The organization name field is required.'],
          },
        }, 422);
      });
      final repository = _repositoryWithAdapter(adapter, TokenStorageService());

      await expectLater(
        repository.registerOrganization(
          name: 'Jane Recruiter',
          email: 'jane@acme.example.com',
          password: 'password123',
          organizationName: '',
          organizationType: 'company',
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 422)
              .having(
                (e) => e.errors?['organization_name'],
                'errors[organization_name]',
                contains('The organization name field is required.'),
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
      final repository = _repositoryWithAdapter(adapter, TokenStorageService());

      await expectLater(
        repository.registerOrganization(
          name: 'Jane Recruiter',
          email: 'jane@acme.example.com',
          password: 'password123',
          organizationName: 'Acme Corp',
          organizationType: 'company',
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
      final repository = _repositoryWithAdapter(adapter, TokenStorageService());

      await expectLater(
        repository.registerOrganization(
          name: 'Jane Recruiter',
          email: 'jane@acme.example.com',
          password: 'password123',
          organizationName: 'Acme Corp',
          organizationType: 'company',
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
}
