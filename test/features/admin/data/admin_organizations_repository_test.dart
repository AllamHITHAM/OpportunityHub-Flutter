// Direct unit tests for AdminOrganizationsRepository.
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
import 'package:opportunityhub_flutter/features/admin/data/admin_organizations_repository.dart';

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

AdminOrganizationsRepository _repositoryWithAdapter(
  _FakeHttpClientAdapter adapter,
) {
  final apiClient = ApiClient(tokenStorageService: TokenStorageService())
    ..dio.httpClientAdapter = adapter;
  return AdminOrganizationsRepository(apiClient: apiClient);
}

Map<String, dynamic> _organizationJson({
  int id = 1,
  String organizationName = 'Acme Corp',
  String organizationType = 'company',
  String approvalStatus = 'pending',
}) {
  return {
    'id': id,
    'user_id': 9,
    'organization_name': organizationName,
    'organization_type': organizationType,
    'approval_status': approvalStatus,
    'industry': 'Tech',
    'description': null,
    'website': null,
    'logo': null,
    'phone': null,
    'created_at': '2026-07-01T10:00:00.000000Z',
    'updated_at': '2026-07-01T10:00:00.000000Z',
    'user': {
      'id': 9,
      'name': 'Acme Contact',
      'email': 'contact@acme.example',
      'role': 'organization',
      'status': 'active',
    },
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

  group('getOrganizations', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': []}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.getOrganizations();

      expect(adapter.lastRequest?.method, 'GET');
      expect(adapter.lastRequest?.path, '/admin/organizations');
    });

    test('parses all organizations, including nested user', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': [
            _organizationJson(id: 1, approvalStatus: 'pending'),
            _organizationJson(id: 2, approvalStatus: 'approved'),
            _organizationJson(id: 3, approvalStatus: 'rejected'),
          ],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getOrganizations();

      expect(result, hasLength(3));
      expect(result[0].id, 1);
      expect(result[0].approvalStatus, 'pending');
      expect(result[1].approvalStatus, 'approved');
      expect(result[2].approvalStatus, 'rejected');
      expect(result[0].user, isNotNull);
      expect(result[0].user!.email, 'contact@acme.example');
    });

    test('an empty list is represented correctly, not as an error', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': []}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getOrganizations();

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

        await expectLater(
          repository.getOrganizations(),
          throwsA(isA<TypeError>()),
        );
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
          repository.getOrganizations(),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('a list item missing id never becomes an empty list', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        final json = _organizationJson()..remove('id');
        return _jsonResponse({
          'data': [json],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getOrganizations(),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'a list item with id as a string never becomes an empty list',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          final json = _organizationJson();
          json['id'] = 'not-an-int';
          return _jsonResponse({
            'data': [json],
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.getOrganizations(),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test(
      'a list item missing organization_name never becomes an empty list',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          final json = _organizationJson()..remove('organization_name');
          return _jsonResponse({
            'data': [json],
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.getOrganizations(),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test(
      'a list item with a malformed organization_type never becomes an empty list',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          final json = _organizationJson();
          json['organization_type'] = 42;
          return _jsonResponse({
            'data': [json],
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.getOrganizations(),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test(
      'a list item with a malformed approval_status never becomes an empty list',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          final json = _organizationJson();
          json['approval_status'] = null;
          return _jsonResponse({
            'data': [json],
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.getOrganizations(),
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
        repository.getOrganizations(),
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
        repository.getOrganizations(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });
  });

  group('getOrganization', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _organizationJson(id: 5)}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.getOrganization(5);

      expect(adapter.lastRequest?.method, 'GET');
      expect(adapter.lastRequest?.path, '/admin/organizations/5');
    });

    test('parses the organization on success', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _organizationJson(id: 5, organizationName: 'Beta LLC'),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getOrganization(5);

      expect(result.id, 5);
      expect(result.organizationName, 'Beta LLC');
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
        repository.getOrganization(5),
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
        repository.getOrganization(5),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });

    test('throws ApiException on a 404 (organization not found)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message':
              'No query results for model [App\\Models\\OrganizationProfile] 999',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getOrganization(999),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });

    test(
      'a malformed detail response never becomes a fake organization',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'data': {'id': 'not-an-int'},
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.getOrganization(5),
          throwsA(isA<FormatException>()),
        );
      },
    );
  });

  group('approveOrganization', () {
    test('uses the exact documented method, path, and body', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _organizationJson(id: 5, approvalStatus: 'approved'),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.approveOrganization(5);

      expect(adapter.lastRequest?.method, 'PUT');
      expect(adapter.lastRequest?.path, '/admin/organizations/5/approval');
      final body = adapter.lastRequest?.data as Map<String, dynamic>;
      expect(body, {'approval_status': 'approved'});
    });

    test('parses the updated organization on success', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _organizationJson(id: 5, approvalStatus: 'approved'),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.approveOrganization(5);

      expect(result.id, 5);
      expect(result.approvalStatus, 'approved');
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
        repository.approveOrganization(5),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test(
      'throws ApiException on a 403 (organization cannot approve itself)',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'success': false,
            'message': 'This action is unauthorized for your account type',
            'data': null,
          }, 403);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.approveOrganization(5),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
          ),
        );
      },
    );

    test('throws ApiException on a 404', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'No query results.',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.approveOrganization(999),
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
            'approval_status': ['The selected approval status is invalid.'],
          },
        }, 422);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.approveOrganization(5),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 422)
              .having(
                (e) => e.errors?['approval_status'],
                'errors[approval_status]',
                isNotNull,
              ),
        ),
      );
    });

    test(
      'a malformed mutation response never becomes a fake organization',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'data': {'id': 'not-an-int'},
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.approveOrganization(5),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test(
      'an approve response missing required fields never becomes a fake organization',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          final json = _organizationJson(id: 5)..remove('organization_name');
          return _jsonResponse({'data': json}, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.approveOrganization(5),
          throwsA(isA<FormatException>()),
        );
      },
    );
  });

  group('rejectOrganization', () {
    test('uses the exact documented method, path, and body', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _organizationJson(id: 5, approvalStatus: 'rejected'),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.rejectOrganization(5);

      expect(adapter.lastRequest?.method, 'PUT');
      expect(adapter.lastRequest?.path, '/admin/organizations/5/approval');
      final body = adapter.lastRequest?.data as Map<String, dynamic>;
      expect(body, {'approval_status': 'rejected'});
    });

    test('parses the updated organization on success', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _organizationJson(id: 5, approvalStatus: 'rejected'),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.rejectOrganization(5);

      expect(result.id, 5);
      expect(result.approvalStatus, 'rejected');
    });

    test('throws ApiException on a 404', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'No query results.',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.rejectOrganization(999),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });

    test(
      'a malformed mutation response never becomes a fake organization',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({'data': null}, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.rejectOrganization(5),
          throwsA(isA<FormatException>()),
        );
      },
    );
  });
}
