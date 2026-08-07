// Direct unit tests for AdminDashboardRepository.
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
import 'package:opportunityhub_flutter/features/admin/data/admin_dashboard_repository.dart';

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

AdminDashboardRepository _repositoryWithAdapter(
  _FakeHttpClientAdapter adapter,
) {
  final apiClient = ApiClient(tokenStorageService: TokenStorageService())
    ..dio.httpClientAdapter = adapter;
  return AdminDashboardRepository(apiClient: apiClient);
}

Map<String, dynamic> _statsJson() {
  return {
    'total_users': 42,
    'total_students': 30,
    'total_organizations': 10,
    'pending_organizations': 3,
    'approved_organizations': 6,
    'rejected_organizations': 1,
    'total_opportunities': 20,
    'open_opportunities': 15,
    'closed_opportunities': 5,
    'total_applications': 100,
    'total_interviews': 8,
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

  group('getDashboardStats', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _statsJson()}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.getDashboardStats();

      expect(adapter.lastRequest?.method, 'GET');
      expect(adapter.lastRequest?.path, '/admin/dashboard');
    });

    test('parses a valid response into AdminDashboardStatsModel', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _statsJson()}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getDashboardStats();

      expect(result.totalUsers, 42);
      expect(result.totalStudents, 30);
      expect(result.totalOrganizations, 10);
      expect(result.pendingOrganizations, 3);
      expect(result.approvedOrganizations, 6);
      expect(result.rejectedOrganizations, 1);
      expect(result.totalOpportunities, 20);
      expect(result.openOpportunities, 15);
      expect(result.closedOpportunities, 5);
      expect(result.totalApplications, 100);
      expect(result.totalInterviews, 8);
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
        repository.getDashboardStats(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', 'Unauthenticated'),
        ),
      );
    });

    test('throws ApiException on a 403 (inactive account)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Account is not active',
          'data': null,
        }, 403);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getDashboardStats(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.message, 'message', 'Account is not active'),
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
        repository.getDashboardStats(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });

    test(
      'a malformed envelope (data is not an object) never becomes empty stats',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'data': ['not', 'an', 'object'],
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.getDashboardStats(),
          throwsA(isA<TypeError>()),
        );
      },
    );

    test('a null data field never becomes empty stats', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': null}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getDashboardStats(),
        throwsA(isA<TypeError>()),
      );
    });

    test(
      'a malformed stats field (missing count) never becomes zeroed stats',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          final json = _statsJson()..remove('total_users');
          return _jsonResponse({'data': json}, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.getDashboardStats(),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test(
      'a malformed stats field (non-numeric count) never becomes zeroed stats',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          final json = _statsJson();
          json['total_interviews'] = 'not-a-number';
          return _jsonResponse({'data': json}, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.getDashboardStats(),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('a network/connection error is mapped through ApiException', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getDashboardStats(),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
