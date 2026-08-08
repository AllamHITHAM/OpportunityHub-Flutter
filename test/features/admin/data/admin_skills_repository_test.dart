// Direct unit tests for AdminSkillsRepository.
//
// These exercise the real Dio/ApiClient pipeline against a fake HTTP
// transport, exactly like the other repository test files in this project
// (see admin_users_repository_test.dart) — nothing about ApiClient's
// architecture is duplicated or bypassed.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_skills_repository.dart';

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

AdminSkillsRepository _repositoryWithAdapter(_FakeHttpClientAdapter adapter) {
  final apiClient = ApiClient(tokenStorageService: TokenStorageService())
    ..dio.httpClientAdapter = adapter;
  return AdminSkillsRepository(apiClient: apiClient);
}

Map<String, dynamic> _skillJson({
  int id = 1,
  String name = 'Flutter',
  String? category,
}) {
  return {
    'id': id,
    'name': name,
    'category': category,
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

  group('getSkills', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': []}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.getSkills();

      expect(adapter.lastRequest?.method, 'GET');
      expect(adapter.lastRequest?.path, '/admin/skills');
    });

    test('parses all skills', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': [
            _skillJson(id: 1, name: 'Flutter'),
            _skillJson(id: 2, name: 'Laravel'),
          ],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getSkills();

      expect(result, hasLength(2));
      expect(result[0].name, 'Flutter');
      expect(result[1].name, 'Laravel');
    });

    test('an empty list is represented correctly, not as an error', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': []}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getSkills();

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

        await expectLater(repository.getSkills(), throwsA(isA<TypeError>()));
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
          repository.getSkills(),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('a list item missing id never becomes an empty list', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        final json = _skillJson()..remove('id');
        return _jsonResponse({
          'data': [json],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getSkills(),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'a list item with id as a string never becomes an empty list',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          final json = _skillJson();
          json['id'] = 'not-an-int';
          return _jsonResponse({
            'data': [json],
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.getSkills(),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('a list item missing name never becomes an empty list', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        final json = _skillJson()..remove('name');
        return _jsonResponse({
          'data': [json],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getSkills(),
        throwsA(isA<FormatException>()),
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
        repository.getSkills(),
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
        repository.getSkills(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });
  });

  group('createSkill', () {
    test('uses the exact documented method, path, and body', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _skillJson(id: 5, name: 'Docker')}, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.createSkill(name: 'Docker');

      expect(adapter.lastRequest?.method, 'POST');
      expect(adapter.lastRequest?.path, '/admin/skills');
      final body = adapter.lastRequest?.data as Map<String, dynamic>;
      expect(body, {'name': 'Docker'});
    });

    test('parses the created skill on success', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _skillJson(id: 5, name: 'Docker')}, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.createSkill(name: 'Docker');

      expect(result.id, 5);
      expect(result.name, 'Docker');
    });

    test(
      'throws ApiException with fieldErrors on a duplicate-name 422',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'message': 'The given data was invalid.',
            'errors': {
              'name': ['The name has already been taken.'],
            },
          }, 422);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.createSkill(name: 'Docker'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 422)
                .having((e) => e.errors?['name'], 'errors[name]', isNotNull),
          ),
        );
      },
    );

    test(
      'throws ApiException on a 409 (unique-check race condition)',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'success': false,
            'message': 'A skill with this name already exists',
            'data': null,
          }, 409);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.createSkill(name: 'Docker'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 409)
                .having(
                  (e) => e.message,
                  'message',
                  'A skill with this name already exists',
                ),
          ),
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
        repository.createSkill(name: 'Docker'),
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
        repository.createSkill(name: 'Docker'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });

    test(
      'a malformed successful response never becomes a fake skill',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'data': {'id': 'not-an-int'},
          }, 201);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.createSkill(name: 'Docker'),
          throwsA(isA<FormatException>()),
        );
      },
    );
  });

  group('updateSkill', () {
    test('uses the exact documented method, path, and body', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _skillJson(id: 5, name: 'New Name'),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.updateSkill(skillId: 5, name: 'New Name');

      expect(adapter.lastRequest?.method, 'PUT');
      expect(adapter.lastRequest?.path, '/admin/skills/5');
      final body = adapter.lastRequest?.data as Map<String, dynamic>;
      expect(body, {'name': 'New Name'});
    });

    test('parses the updated skill on success', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _skillJson(id: 5, name: 'New Name'),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.updateSkill(skillId: 5, name: 'New Name');

      expect(result.id, 5);
      expect(result.name, 'New Name');
    });

    test(
      'a malformed successful response never becomes a fake skill',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({'data': null}, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.updateSkill(skillId: 5, name: 'New Name'),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('throws ApiException on a 404 (skill not found)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'No query results for model [App\\Models\\Skill] 999',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.updateSkill(skillId: 999, name: 'New Name'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });

    test(
      'throws ApiException with fieldErrors on a duplicate-name 422',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'message': 'The given data was invalid.',
            'errors': {
              'name': ['The name has already been taken.'],
            },
          }, 422);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.updateSkill(skillId: 5, name: 'Docker'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 422)
                .having((e) => e.errors?['name'], 'errors[name]', isNotNull),
          ),
        );
      },
    );

    test(
      'throws ApiException on a 409 (unique-check race condition)',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'success': false,
            'message': 'A skill with this name already exists',
            'data': null,
          }, 409);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.updateSkill(skillId: 5, name: 'Docker'),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 409),
          ),
        );
      },
    );
  });

  group('deleteSkill', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': true,
          'message': 'Skill deleted successfully',
          'data': null,
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.deleteSkill(5);

      expect(adapter.lastRequest?.method, 'DELETE');
      expect(adapter.lastRequest?.path, '/admin/skills/5');
    });

    test(
      'completes successfully without attempting to parse a skill',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'success': true,
            'message': 'Skill deleted successfully',
            'data': null,
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(repository.deleteSkill(5), completes);
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
        repository.deleteSkill(5),
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
        repository.deleteSkill(5),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });

    test('throws ApiException on a 404 (skill not found)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'No query results for model [App\\Models\\Skill] 999',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.deleteSkill(999),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });

    test(
      'throws ApiException with the exact backend message on a 409 delete conflict',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'success': false,
            'message': 'Cannot delete a skill that is currently in use',
            'data': null,
          }, 409);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.deleteSkill(5),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 409)
                .having(
                  (e) => e.message,
                  'message',
                  'Cannot delete a skill that is currently in use',
                ),
          ),
        );
      },
    );
  });
}
