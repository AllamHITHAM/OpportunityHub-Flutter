// Direct unit tests for AdminEducationVerificationsProvider, using a fake
// repository (no real network) and a real AuthProvider (with a fake
// AuthRepository) so the reset-on-logout listener can be exercised
// genuinely. Mirrors admin_skill_suggestions_provider_test.dart's own
// conventions.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/admin/data/admin_education_verifications_repository.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/models/admin_education_verification_model.dart';
import 'package:opportunityhub_flutter/providers/admin_education_verifications_provider.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  @override
  Future<String?> getSavedToken() async => null;

  @override
  Future<void> logout() async {
    // A no-op -- this test only cares that AuthProvider.logout() flips
    // `isAuthenticated` to false, not the real network/secure-storage calls.
  }
}

AdminEducationVerificationModel _verification({
  int id = 1,
  String status = 'pending',
  String studentName = 'Jane Student',
}) {
  return AdminEducationVerificationModel(
    id: id,
    institutionName: 'State University',
    degreeOrProgram: 'BSc Computer Science',
    status: status,
    studentName: studentName,
  );
}

class _FakeAdminEducationVerificationsRepository
    extends AdminEducationVerificationsRepository {
  _FakeAdminEducationVerificationsRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<AdminEducationVerificationModel>? loadResult;
  ApiException? loadError;
  Duration loadDelay = Duration.zero;
  int getVerificationsCallCount = 0;

  ApiException? verifyError;
  Duration verifyDelay = Duration.zero;
  final List<int> verifiedIds = [];

  ApiException? rejectError;
  final List<int> rejectedIds = [];
  final List<String> rejectReasons = [];

  Uint8List? downloadResult;
  ApiException? downloadError;
  int downloadCallCount = 0;

  @override
  Future<List<AdminEducationVerificationModel>> getVerifications() async {
    getVerificationsCallCount++;
    if (loadDelay > Duration.zero) {
      await Future<void>.delayed(loadDelay);
    }
    if (loadError != null) throw loadError!;
    return loadResult ?? [];
  }

  @override
  Future<void> verify(int verificationId) async {
    verifiedIds.add(verificationId);
    if (verifyDelay > Duration.zero) {
      await Future<void>.delayed(verifyDelay);
    }
    if (verifyError != null) throw verifyError!;
  }

  @override
  Future<void> reject(int verificationId, {required String reason}) async {
    rejectedIds.add(verificationId);
    rejectReasons.add(reason);
    if (rejectError != null) throw rejectError!;
  }

  @override
  Future<Uint8List> downloadDocument(int verificationId) async {
    downloadCallCount++;
    if (downloadError != null) throw downloadError!;
    return downloadResult ?? Uint8List.fromList([0x25, 0x50, 0x44, 0x46]);
  }
}

void main() {
  group('load', () {
    test('populates verifications on success', () async {
      final repository = _FakeAdminEducationVerificationsRepository()
        ..loadResult = [_verification(id: 1)];
      final provider = AdminEducationVerificationsProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );

      await provider.load();

      expect(provider.verifications, hasLength(1));
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test('sets errorMessage on ApiException failure', () async {
      final repository = _FakeAdminEducationVerificationsRepository()
        ..loadError = ApiException('Server error, please try again later.');
      final provider = AdminEducationVerificationsProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );

      await provider.load();

      expect(provider.verifications, isEmpty);
      expect(provider.errorMessage, 'Server error, please try again later.');
    });
  });

  group('verify', () {
    test('removes the verification from the local list on success', () async {
      final repository = _FakeAdminEducationVerificationsRepository()
        ..loadResult = [_verification(id: 1), _verification(id: 2)];
      final provider = AdminEducationVerificationsProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );
      await provider.load();

      final success = await provider.verify(1);

      expect(success, isTrue);
      expect(repository.verifiedIds, [1]);
      expect(provider.verifications.map((v) => v.id), [2]);
    });

    test('keeps the row and sets actionErrorMessage on failure', () async {
      final repository = _FakeAdminEducationVerificationsRepository()
        ..loadResult = [_verification(id: 1)]
        ..verifyError = ApiException(
          'This education verification has already been reviewed.',
          statusCode: 409,
        );
      final provider = AdminEducationVerificationsProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );
      await provider.load();

      final success = await provider.verify(1);

      expect(success, isFalse);
      expect(provider.verifications, hasLength(1));
      expect(
        provider.actionErrorMessage,
        'This education verification has already been reviewed.',
      );
    });

    test('a duplicate in-flight verify for the same id is ignored', () async {
      final repository = _FakeAdminEducationVerificationsRepository()
        ..loadResult = [_verification(id: 1)]
        ..verifyDelay = const Duration(milliseconds: 50);
      final provider = AdminEducationVerificationsProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );
      await provider.load();

      final results = await Future.wait([
        provider.verify(1),
        provider.verify(1),
      ]);

      expect(repository.verifiedIds, [1]);
      expect(results.where((success) => success), hasLength(1));
    });
  });

  group('reject', () {
    test(
      'sends the reason and removes the row from the list on success',
      () async {
        final repository = _FakeAdminEducationVerificationsRepository()
          ..loadResult = [_verification(id: 1)];
        final provider = AdminEducationVerificationsProvider(
          repository: repository,
          authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
        );
        await provider.load();

        final success = await provider.reject(
          1,
          reason: 'Document is unreadable.',
        );

        expect(success, isTrue);
        expect(repository.rejectedIds, [1]);
        expect(repository.rejectReasons, ['Document is unreadable.']);
        expect(provider.verifications, isEmpty);
      },
    );

    test('keeps the row and sets actionErrorMessage on failure', () async {
      final repository = _FakeAdminEducationVerificationsRepository()
        ..loadResult = [_verification(id: 1)]
        ..rejectError = ApiException('Something went wrong.', statusCode: 500);
      final provider = AdminEducationVerificationsProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );
      await provider.load();

      final success = await provider.reject(1, reason: 'Blurry.');

      expect(success, isFalse);
      expect(provider.verifications, hasLength(1));
      expect(provider.actionErrorMessage, isNotNull);
    });
  });

  group('downloadDocument', () {
    test('returns bytes on success', () async {
      final repository = _FakeAdminEducationVerificationsRepository();
      final provider = AdminEducationVerificationsProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );

      final bytes = await provider.downloadDocument(1);

      expect(bytes, isNotNull);
      expect(repository.downloadCallCount, 1);
    });

    test('sets downloadErrorMessage on failure', () async {
      final repository = _FakeAdminEducationVerificationsRepository()
        ..downloadError = ApiException('Document not found.', statusCode: 404);
      final provider = AdminEducationVerificationsProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );

      final bytes = await provider.downloadDocument(1);

      expect(bytes, isNull);
      expect(provider.downloadErrorMessage, 'Document not found.');
    });
  });

  test('reset() clears state and is called on logout', () async {
    final repository = _FakeAdminEducationVerificationsRepository()
      ..loadResult = [_verification(id: 1)];
    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final provider = AdminEducationVerificationsProvider(
      repository: repository,
      authProvider: authProvider,
    );

    await provider.load();
    expect(provider.verifications, hasLength(1));

    await authProvider.logout();

    expect(provider.verifications, isEmpty);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.actionErrorMessage, isNull);
    expect(provider.downloadErrorMessage, isNull);
    expect(provider.busyIds, isEmpty);
  });
}
