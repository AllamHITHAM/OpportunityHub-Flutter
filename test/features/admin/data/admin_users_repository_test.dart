// Direct unit tests for AdminUsersRepository.
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
import 'package:opportunityhub_flutter/features/admin/data/admin_users_repository.dart';

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

ResponseBody _jsonResponse(dynamic body, int statusCode) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

AdminUsersRepository _repositoryWithAdapter(_FakeHttpClientAdapter adapter) {
  final apiClient = ApiClient(tokenStorageService: TokenStorageService())
    ..dio.httpClientAdapter = adapter;
  return AdminUsersRepository(apiClient: apiClient);
}

Map<String, dynamic> _userJson({
  int id = 1,
  String name = 'Jane Student',
  String email = 'jane@example.com',
  String role = 'student',
  String status = 'active',
}) {
  return {
    'id': id,
    'name': name,
    'email': email,
    'email_verified_at': null,
    'role': role,
    'status': status,
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

  group('getUsers', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': []}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.getUsers();

      expect(adapter.lastRequest?.method, 'GET');
      expect(adapter.lastRequest?.path, '/admin/users');
    });

    test('parses all users', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': [
            _userJson(id: 1, name: 'Jane Student', role: 'student'),
            _userJson(id: 2, name: 'Acme Corp', role: 'organization'),
            _userJson(id: 3, name: 'Root Admin', role: 'admin'),
          ],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getUsers();

      expect(result, hasLength(3));
      expect(result[0].id, 1);
      expect(result[0].role, 'student');
      expect(result[1].role, 'organization');
      expect(result[2].role, 'admin');
      expect(result[0].createdAt, isNotNull);
    });

    test('an empty list is represented correctly, not as an error', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': []}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getUsers();

      expect(result, isEmpty);
    });

    test(
      'a malformed response (data is not a list) never becomes an empty list',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'data': {'not': 'a list'},
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(repository.getUsers(), throwsA(isA<TypeError>()));
      },
    );

    test(
      'a list item that is not an object never becomes an empty list',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'data': ['not-an-object'],
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.getUsers(),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('a list item missing id never becomes an empty list', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        final json = _userJson()..remove('id');
        return _jsonResponse({
          'data': [json],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(repository.getUsers(), throwsA(isA<FormatException>()));
    });

    test(
      'a list item with id as a string never becomes an empty list',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          final json = _userJson();
          json['id'] = 'not-an-int';
          return _jsonResponse({
            'data': [json],
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.getUsers(),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('a list item missing name never becomes an empty list', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        final json = _userJson()..remove('name');
        return _jsonResponse({
          'data': [json],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(repository.getUsers(), throwsA(isA<FormatException>()));
    });

    test(
      'a list item with a malformed role never becomes an empty list',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          final json = _userJson();
          json['role'] = 42;
          return _jsonResponse({
            'data': [json],
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.getUsers(),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test(
      'a list item with a malformed status never becomes an empty list',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          final json = _userJson();
          json['status'] = null;
          return _jsonResponse({
            'data': [json],
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.getUsers(),
          throwsA(isA<FormatException>()),
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
        repository.getUsers(),
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
        repository.getUsers(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });
  });

  group('updateUserStatus', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _userJson(id: 7, status: 'suspended'),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.updateUserStatus(userId: 7, status: 'suspended');

      expect(adapter.lastRequest?.method, 'PUT');
      expect(adapter.lastRequest?.path, '/admin/users/7/status');
    });

    test('sends the exact request body', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _userJson(id: 7, status: 'active')}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.updateUserStatus(userId: 7, status: 'active');

      final body = adapter.lastRequest?.data as Map<String, dynamic>;
      expect(body, {'status': 'active'});
    });

    test('parses the updated user on success', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _userJson(id: 7, name: 'Jane Student', status: 'suspended'),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.updateUserStatus(
        userId: 7,
        status: 'suspended',
      );

      expect(result.id, 7);
      expect(result.status, 'suspended');
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
        repository.updateUserStatus(userId: 7, status: 'suspended'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('throws ApiException on a 403 (wrong role)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'This action is unauthorized for your account type',
          'data': null,
        }, 403);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.updateUserStatus(userId: 7, status: 'suspended'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });

    test('throws ApiException on a 403 (self-status-change guard)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'You cannot change your own account status',
          'data': null,
        }, 403);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.updateUserStatus(userId: 1, status: 'suspended'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having(
                (e) => e.message,
                'message',
                'You cannot change your own account status',
              ),
        ),
      );
    });

    test('throws ApiException on a 404 (user not found)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'No query results for model [App\\Models\\User] 999',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.updateUserStatus(userId: 999, status: 'suspended'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });

    test('throws ApiException with fieldErrors on a 422', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'message': 'The given data was invalid.',
          'errors': {
            'status': ['The selected status is invalid.'],
          },
        }, 422);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.updateUserStatus(userId: 7, status: 'pending'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 422)
              .having((e) => e.errors?['status'], 'errors[status]', isNotNull),
        ),
      );
    });

    test(
      'an update response with id as a string never becomes a fake user (never id=0)',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'data': {'id': 'not-an-int'},
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.updateUserStatus(userId: 7, status: 'suspended'),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test(
      'an update response missing required fields never becomes a fake user',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          final json = _userJson(id: 7)..remove('name');
          return _jsonResponse({'data': json}, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.updateUserStatus(userId: 7, status: 'suspended'),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('a null data field never becomes a fake user', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': null}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.updateUserStatus(userId: 7, status: 'suspended'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
