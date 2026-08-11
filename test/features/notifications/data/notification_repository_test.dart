// Direct unit tests for NotificationRepository.
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
import 'package:opportunityhub_flutter/features/notifications/data/notification_repository.dart';

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

NotificationRepository _repositoryWithAdapter(_FakeHttpClientAdapter adapter) {
  final apiClient = ApiClient(tokenStorageService: TokenStorageService())
    ..dio.httpClientAdapter = adapter;
  return NotificationRepository(apiClient: apiClient);
}

Map<String, dynamic> _notificationJson({
  int id = 1,
  int userId = 7,
  String title = 'Application shortlisted',
  String message = 'Your application has been shortlisted.',
  String priority = 'normal',
  String type = 'application',
  String? actionUrl = '/student/applications/42',
  bool isRead = false,
  String? readAt,
}) {
  return {
    'id': id,
    'user_id': userId,
    'title': title,
    'message': message,
    'priority': priority,
    'type': type,
    'action_url': actionUrl,
    'is_read': isRead,
    'read_at': readAt,
    'sent_at': '2026-08-10T09:00:00.000000Z',
    'created_at': '2026-08-10T09:00:00.000000Z',
    'updated_at': '2026-08-10T09:00:00.000000Z',
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

  group('getNotifications', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': [_notificationJson()],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.getNotifications();

      expect(adapter.lastRequest?.method, 'GET');
      expect(adapter.lastRequest?.path, '/notifications');
    });

    test('parses a list of notifications', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': [
            _notificationJson(id: 1, title: 'First'),
            _notificationJson(id: 2, title: 'Second'),
          ],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getNotifications();

      expect(result, hasLength(2));
      expect(result[0].id, 1);
      expect(result[0].title, 'First');
      expect(result[1].id, 2);
      expect(result[1].title, 'Second');
    });

    test('parses an empty list', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': <dynamic>[]}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getNotifications();

      expect(result, isEmpty);
    });

    test('a malformed outer list never becomes a fake empty result', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {'not': 'a list'},
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getNotifications(),
        throwsA(isA<TypeError>()),
      );
    });

    test('a malformed item in an otherwise-valid list throws', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': [
            {'id': 'not-an-int'},
          ],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getNotifications(),
        throwsA(isA<TypeError>()),
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
        repository.getNotifications(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('throws ApiException on a 403', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Account is not active',
          'data': null,
        }, 403);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getNotifications(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.message, 'message', 'Account is not active'),
        ),
      );
    });
  });

  group('markAsRead', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _notificationJson(
            isRead: true,
            readAt: '2026-08-11T09:00:00.000000Z',
          ),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.markAsRead(9);

      expect(adapter.lastRequest?.method, 'PUT');
      expect(adapter.lastRequest?.path, '/notifications/9/read');
    });

    test('parses the returned, now-read notification', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _notificationJson(
            id: 9,
            isRead: true,
            readAt: '2026-08-11T09:00:00.000000Z',
          ),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.markAsRead(9);

      expect(result.id, 9);
      expect(result.isRead, isTrue);
      expect(result.readAt, DateTime.parse('2026-08-11T09:00:00.000000Z'));
    });

    test('throws ApiException on a 404 (not found / not owned)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Notification not found',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.markAsRead(9),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.message, 'message', 'Notification not found'),
        ),
      );
    });

    test('a malformed success response is never silently swallowed', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {'id': 'not-an-int'},
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(repository.markAsRead(9), throwsA(anything));
    });
  });

  group('markAllAsRead', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {'updated_count': 3},
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.markAllAsRead();

      expect(adapter.lastRequest?.method, 'PUT');
      expect(adapter.lastRequest?.path, '/notifications/read-all');
    });

    test('parses updated_count', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {'updated_count': 5},
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.markAllAsRead();

      expect(result, 5);
    });

    test('parses a zero updated_count (nothing was unread)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {'updated_count': 0},
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.markAllAsRead();

      expect(result, 0);
    });

    test('a malformed response is never silently swallowed', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {'updated_count': 'not-an-int'},
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(repository.markAllAsRead(), throwsA(isA<TypeError>()));
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
        repository.markAllAsRead(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('throws ApiException on a 403', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Account is not active',
          'data': null,
        }, 403);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.markAllAsRead(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });
  });
}
