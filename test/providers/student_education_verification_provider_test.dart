// Direct unit tests for StudentEducationVerificationProvider, using a fake
// repository (no real network) and a real AuthProvider (with a fake
// AuthRepository) so the reset-on-logout listener can be exercised
// genuinely. Mirrors student_skill_provider_test.dart's own conventions.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/cv/data/picked_cv_file.dart';
import 'package:opportunityhub_flutter/features/education_verification/data/education_verification_repository.dart';
import 'package:opportunityhub_flutter/models/education_verification_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/student_education_verification_provider.dart';

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

EducationVerificationModel _verification({
  String status = 'pending',
  String institutionName = 'State University',
  String degreeOrProgram = 'BSc Computer Science',
  String? rejectionReason,
}) {
  return EducationVerificationModel(
    institutionName: institutionName,
    degreeOrProgram: degreeOrProgram,
    status: status,
    rejectionReason: rejectionReason,
  );
}

PickedCvFile _file() =>
    PickedCvFile(filename: 'proof.pdf', bytes: Uint8List.fromList([1, 2, 3]));

class _FakeEducationVerificationRepository
    extends EducationVerificationRepository {
  _FakeEducationVerificationRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  EducationVerificationModel? statusResult;
  ApiException? statusError;
  Duration statusDelay = Duration.zero;
  int getStatusCallCount = 0;

  EducationVerificationModel? submitResult;
  ApiException? submitError;
  int submitCallCount = 0;

  Uint8List? downloadResult;
  ApiException? downloadError;
  Duration downloadDelay = Duration.zero;
  int downloadCallCount = 0;

  @override
  Future<EducationVerificationModel> getStatus() async {
    getStatusCallCount++;
    if (statusDelay > Duration.zero) {
      await Future<void>.delayed(statusDelay);
    }
    if (statusError != null) throw statusError!;
    return statusResult ?? _verification(status: 'not_submitted');
  }

  @override
  Future<EducationVerificationModel> submit({
    required String institutionName,
    required String degreeOrProgram,
    required PickedCvFile file,
  }) async {
    submitCallCount++;
    if (submitError != null) throw submitError!;
    return submitResult ??
        _verification(
          institutionName: institutionName,
          degreeOrProgram: degreeOrProgram,
        );
  }

  @override
  Future<Uint8List> downloadDocument() async {
    downloadCallCount++;
    if (downloadDelay > Duration.zero) {
      await Future<void>.delayed(downloadDelay);
    }
    if (downloadError != null) throw downloadError!;
    return downloadResult ?? Uint8List.fromList([0x25, 0x50, 0x44, 0x46]);
  }
}

void main() {
  group('load', () {
    test('populates verification on success', () async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification(status: 'pending');
      final provider = StudentEducationVerificationProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );

      await provider.load();

      expect(provider.verification?.status, 'pending');
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test('sets errorMessage on ApiException failure', () async {
      final repository = _FakeEducationVerificationRepository()
        ..statusError = ApiException('Server error, please try again later.');
      final provider = StudentEducationVerificationProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );

      await provider.load();

      expect(provider.verification, isNull);
      expect(provider.errorMessage, 'Server error, please try again later.');
    });

    test('concurrent calls share a single in-flight request', () async {
      final repository = _FakeEducationVerificationRepository()
        ..statusDelay = const Duration(milliseconds: 50);
      final provider = StudentEducationVerificationProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );

      await Future.wait([provider.load(), provider.load()]);

      expect(repository.getStatusCallCount, 1);
    });
  });

  group('submit', () {
    test('updates verification immediately on success', () async {
      final repository = _FakeEducationVerificationRepository()
        ..submitResult = _verification(status: 'pending');
      final provider = StudentEducationVerificationProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );

      final success = await provider.submit(
        institutionName: 'State University',
        degreeOrProgram: 'BSc',
        file: _file(),
      );

      expect(success, isTrue);
      expect(provider.verification?.status, 'pending');
      expect(provider.isSubmitting, isFalse);
      expect(repository.submitCallCount, 1);
    });

    test(
      'keeps the previous verification and sets formErrorMessage on failure',
      () async {
        final repository = _FakeEducationVerificationRepository()
          ..statusResult = _verification(
            status: 'rejected',
            rejectionReason: 'Blurry.',
          )
          ..submitError = ApiException(
            'Your education has already been verified and cannot be resubmitted.',
            statusCode: 409,
          );
        final provider = StudentEducationVerificationProvider(
          repository: repository,
          authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
        );
        await provider.load();

        final success = await provider.submit(
          institutionName: 'State University',
          degreeOrProgram: 'BSc',
          file: _file(),
        );

        expect(success, isFalse);
        expect(provider.verification?.status, 'rejected');
        expect(
          provider.formErrorMessage,
          'Your education has already been verified and cannot be resubmitted.',
        );
      },
    );
  });

  group('downloadDocument', () {
    test('returns bytes on success', () async {
      final repository = _FakeEducationVerificationRepository();
      final provider = StudentEducationVerificationProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );

      final bytes = await provider.downloadDocument();

      expect(bytes, isNotNull);
      expect(provider.downloadErrorMessage, isNull);
    });

    test('sets downloadErrorMessage on failure', () async {
      final repository = _FakeEducationVerificationRepository()
        ..downloadError = ApiException('Server error, please try again later.');
      final provider = StudentEducationVerificationProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );

      final bytes = await provider.downloadDocument();

      expect(bytes, isNull);
      expect(
        provider.downloadErrorMessage,
        'Server error, please try again later.',
      );
    });

    test('a duplicate in-flight download is ignored', () async {
      final repository = _FakeEducationVerificationRepository()
        ..downloadDelay = const Duration(milliseconds: 50);
      final provider = StudentEducationVerificationProvider(
        repository: repository,
        authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      );

      final results = await Future.wait([
        provider.downloadDocument(),
        provider.downloadDocument(),
      ]);

      expect(repository.downloadCallCount, 1);
      expect(results.where((bytes) => bytes != null), hasLength(1));
    });
  });

  test('reset() clears state and is called on logout', () async {
    final repository = _FakeEducationVerificationRepository()
      ..statusResult = _verification(status: 'pending');
    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final provider = StudentEducationVerificationProvider(
      repository: repository,
      authProvider: authProvider,
    );

    await provider.load();
    expect(provider.verification, isNotNull);

    await authProvider.logout();

    expect(provider.verification, isNull);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.isSubmitting, isFalse);
    expect(provider.formErrorMessage, isNull);
    expect(provider.isDownloading, isFalse);
    expect(provider.downloadErrorMessage, isNull);
  });
}
