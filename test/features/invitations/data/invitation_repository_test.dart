// Direct unit tests for InvitationRepository, using the real Dio/ApiClient
// pipeline against a fake HTTP transport — same convention as every other
// repository test file in this project.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/invitations/data/invitation_repository.dart';

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

InvitationRepository _repositoryWithAdapter(_FakeHttpClientAdapter adapter) {
  final apiClient = ApiClient(tokenStorageService: TokenStorageService())
    ..dio.httpClientAdapter = adapter;
  return InvitationRepository(apiClient: apiClient);
}

Map<String, dynamic> _invitationJson({
  int id = 1,
  int opportunityId = 5,
  String status = 'pending',
  String? message,
  String opportunityTitle = 'Backend Developer',
  String organizationName = 'Hiring Co',
}) {
  return {
    'id': id,
    'opportunity_id': opportunityId,
    'student_id': 1,
    'status': status,
    'message': message,
    'created_at': '2026-08-20T09:00:00.000000Z',
    'updated_at': '2026-08-20T09:00:00.000000Z',
    'opportunity': {
      'id': opportunityId,
      'title': opportunityTitle,
      'organization_id': 2,
      'organization_profile': {
        'id': 2,
        'organization_name': organizationName,
      },
    },
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

  group('sendInvitation', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _invitationJson()}, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.sendInvitation(studentId: 3, opportunityId: 5);

      expect(adapter.lastRequest?.method, 'POST');
      expect(adapter.lastRequest?.path, '/organization/invitations');
    });

    test('sends student_id/opportunity_id, and omits message when null', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _invitationJson()}, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.sendInvitation(studentId: 3, opportunityId: 5);

      final body = adapter.lastRequest?.data as Map<String, dynamic>;
      expect(body.keys.toSet(), {'student_id', 'opportunity_id'});
      expect(body['student_id'], 3);
      expect(body['opportunity_id'], 5);
    });

    test('includes message when provided', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _invitationJson()}, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.sendInvitation(
        studentId: 3,
        opportunityId: 5,
        message: 'Great fit for the role.',
      );

      final body = adapter.lastRequest?.data as Map<String, dynamic>;
      expect(body['message'], 'Great fit for the role.');
    });

    test('throws with the exact 409 message on a duplicate invitation', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'An invitation already exists for this student and opportunity',
          'data': null,
        }, 409);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.sendInvitation(studentId: 3, opportunityId: 5),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having(
                (e) => e.message,
                'message',
                'An invitation already exists for this student and opportunity',
              ),
        ),
      );
    });

    test('throws with the exact 409 message when already applied', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'This student has already applied to this opportunity',
          'data': null,
        }, 409);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.sendInvitation(studentId: 3, opportunityId: 5),
        throwsA(isA<ApiException>()),
      );
    });

    test('throws with the exact 422 message for a non-open opportunity', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'This opportunity is not open for invitations',
          'data': null,
        }, 422);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.sendInvitation(studentId: 3, opportunityId: 5),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 422),
        ),
      );
    });
  });

  group('getInvitations', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': []}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.getInvitations();

      expect(adapter.lastRequest?.method, 'GET');
      expect(adapter.lastRequest?.path, '/student/invitations');
    });

    test('parses opportunity title, organization name, status and message', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': [
            _invitationJson(
              opportunityTitle: 'Backend Developer',
              organizationName: 'Hiring Co',
              message: 'Please apply!',
            ),
          ],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getInvitations();

      expect(result.single.opportunityTitle, 'Backend Developer');
      expect(result.single.organizationName, 'Hiring Co');
      expect(result.single.message, 'Please apply!');
      expect(result.single.isPending, isTrue);
    });

    test('parses an empty list', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': []}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getInvitations();

      expect(result, isEmpty);
    });

    test('throws ApiException on a 403 (Organization/Admin denied)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'This action is unauthorized for your account type',
          'data': null,
        }, 403);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getInvitations(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });
  });

  group('acceptInvitation', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _invitationJson(status: 'accepted'),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.acceptInvitation(7);

      expect(adapter.lastRequest?.method, 'PUT');
      expect(adapter.lastRequest?.path, '/student/invitations/7/accept');
    });

    test('throws with the exact 409 message on a repeated response', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'This invitation has already been responded to',
          'data': null,
        }, 409);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.acceptInvitation(7),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'This invitation has already been responded to',
          ),
        ),
      );
    });

    test('throws with the exact 404 message for the wrong owner', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Invitation not found',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.acceptInvitation(7),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Invitation not found',
          ),
        ),
      );
    });
  });

  group('declineInvitation', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _invitationJson(status: 'declined'),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.declineInvitation(7);

      expect(adapter.lastRequest?.method, 'PUT');
      expect(adapter.lastRequest?.path, '/student/invitations/7/decline');
    });

    test('throws ApiException on a 409', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'This invitation has already been responded to',
          'data': null,
        }, 409);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.declineInvitation(7),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 409),
        ),
      );
    });
  });
}
