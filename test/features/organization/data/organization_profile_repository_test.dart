// Direct unit tests for OrganizationProfileRepository.getProfile().
//
// These exercise the real Dio/ApiClient pipeline against a fake HTTP
// transport, exactly like student_profile_repository_test.dart — nothing
// about ApiClient's architecture is duplicated or bypassed. There is no
// createProfile test here: the backend has no
// `POST /api/organization/profile` endpoint — an organization's profile is
// created atomically by `POST /register/organization` (see
// auth_repository_test.dart's `registerOrganization` group) — so this
// repository only ever reads one back.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/organization/data/organization_profile_repository.dart';

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

OrganizationProfileRepository _repositoryWithAdapter(
  _FakeHttpClientAdapter adapter,
) {
  final apiClient = ApiClient(tokenStorageService: TokenStorageService())
    ..dio.httpClientAdapter = adapter;
  return OrganizationProfileRepository(apiClient: apiClient);
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

  group('getProfile', () {
    test('parses the profile on 200', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {
            'id': 3,
            'organization_name': 'Acme Corp',
            'organization_type': 'company',
            'approval_status': 'pending',
            'industry': 'Software',
            'description': null,
            'website': 'https://acme.example.com',
            'phone': null,
          },
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final profile = await repository.getProfile();

      expect(adapter.lastRequest?.path, '/organization/profile');
      expect(profile?.id, 3);
      expect(profile?.organizationName, 'Acme Corp');
      expect(profile?.organizationType, 'company');
      expect(profile?.approvalStatus, 'pending');
      expect(profile?.industry, 'Software');
      expect(profile?.website, 'https://acme.example.com');
    });

    test('returns null on the documented 404 (no profile yet)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Organization profile not found',
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
          'message': 'Unauthenticated',
          'data': null,
        }, 401);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(repository.getProfile(), throwsA(isA<ApiException>()));
    });
  });
}
