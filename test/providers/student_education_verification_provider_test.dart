// Direct unit tests for StudentEducationVerificationProvider, using a fake
// repository (no real network) and a real AuthProvider (with a fake
// AuthRepository) so the reset-on-logout listener can be exercised
// genuinely. Mirrors student_skill_provider_test.dart's own conventions.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/utils/cv_file_open_result.dart';
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

/// A fake, injectable platform file action (view or download) — mirrors
/// `test/providers/student_cv_provider_test.dart`'s own fake, since both
/// providers share the exact same `DocumentFileAction`/`CvFileAction`
/// signature.
class _FakeFileAction {
  _FakeFileAction();
  CvFileOpenResult result = const CvFileOpenResult(success: true);
  Duration delay = Duration.zero;
  int callCount = 0;
  Uint8List? lastBytes;
  String? lastFileName;

  Future<CvFileOpenResult> call(Uint8List bytes, String fileName) async {
    callCount++;
    lastBytes = bytes;
    lastFileName = fileName;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return result;
  }
}

void main() {
  late _FakeFileAction fakeViewDocumentFile;
  late _FakeFileAction fakeDownloadDocumentFile;

  StudentEducationVerificationProvider buildProvider(
    _FakeEducationVerificationRepository repository,
  ) {
    return StudentEducationVerificationProvider(
      repository: repository,
      authProvider: AuthProvider(authRepository: _FakeAuthRepository()),
      viewDocumentFile: fakeViewDocumentFile.call,
      downloadDocumentFile: fakeDownloadDocumentFile.call,
    );
  }

  setUp(() {
    fakeViewDocumentFile = _FakeFileAction();
    fakeDownloadDocumentFile = _FakeFileAction();
  });

  group('load', () {
    test('populates verification on success', () async {
      final repository = _FakeEducationVerificationRepository()
        ..statusResult = _verification(status: 'pending');
      final provider = buildProvider(repository);

      await provider.load();

      expect(provider.verification?.status, 'pending');
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test('sets errorMessage on ApiException failure', () async {
      final repository = _FakeEducationVerificationRepository()
        ..statusError = ApiException('Server error, please try again later.');
      final provider = buildProvider(repository);

      await provider.load();

      expect(provider.verification, isNull);
      expect(provider.errorMessage, 'Server error, please try again later.');
    });

    test('concurrent calls share a single in-flight request', () async {
      final repository = _FakeEducationVerificationRepository()
        ..statusDelay = const Duration(milliseconds: 50);
      final provider = buildProvider(repository);

      await Future.wait([provider.load(), provider.load()]);

      expect(repository.getStatusCallCount, 1);
    });
  });

  group('submit', () {
    test('updates verification immediately on success', () async {
      final repository = _FakeEducationVerificationRepository()
        ..submitResult = _verification(status: 'pending');
      final provider = buildProvider(repository);

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
        final provider = buildProvider(repository);
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

  group('viewDocument (Phase 8)', () {
    test(
      'fetches the real bytes and triggers the real platform viewer, with no false success',
      () async {
        final repository = _FakeEducationVerificationRepository()
          ..downloadResult = Uint8List(2048);
        final provider = buildProvider(repository);

        final success = await provider.viewDocument('State University - Education Verification.pdf');

        expect(success, isTrue);
        expect(repository.downloadCallCount, 1);
        expect(fakeViewDocumentFile.callCount, 1);
        expect(
          fakeViewDocumentFile.lastFileName,
          'State University - Education Verification.pdf',
        );
        expect(fakeDownloadDocumentFile.callCount, 0);
        expect(provider.isViewingDocument, isFalse);
        expect(provider.viewErrorMessage, isNull);
      },
    );

    test('never claims success merely because bytes were fetched', () async {
      final repository = _FakeEducationVerificationRepository();
      fakeViewDocumentFile.result = const CvFileOpenResult(
        success: false,
        errorMessage: "Couldn't open the document.",
      );
      final provider = buildProvider(repository);

      final success = await provider.viewDocument('doc.pdf');

      expect(success, isFalse);
      expect(provider.viewErrorMessage, "Couldn't open the document.");
    });

    test('a backend fetch failure exposes the backend message', () async {
      final repository = _FakeEducationVerificationRepository()
        ..downloadError = ApiException('Server error, please try again later.');
      final provider = buildProvider(repository);

      final success = await provider.viewDocument('doc.pdf');

      expect(success, isFalse);
      expect(provider.viewErrorMessage, 'Server error, please try again later.');
      expect(fakeViewDocumentFile.callCount, 0);
    });

    test('isViewingDocument is true only during an in-flight view', () async {
      final repository = _FakeEducationVerificationRepository()
        ..downloadDelay = const Duration(milliseconds: 50);
      final provider = buildProvider(repository);

      expect(provider.isViewingDocument, isFalse);
      final future = provider.viewDocument('doc.pdf');
      expect(provider.isViewingDocument, isTrue);

      await future;
      expect(provider.isViewingDocument, isFalse);
    });

    test('a duplicate view while in flight is blocked', () async {
      final repository = _FakeEducationVerificationRepository()
        ..downloadDelay = const Duration(milliseconds: 50);
      final provider = buildProvider(repository);

      final results = await Future.wait([
        provider.viewDocument('doc.pdf'),
        provider.viewDocument('doc.pdf'),
      ]);

      expect(repository.downloadCallCount, 1);
      expect(results.where((r) => r).length, 1);
    });
  });

  group('downloadDocumentFile (Phase 8)', () {
    test(
      'fetches the real bytes and triggers the real platform download, distinct from view',
      () async {
        final repository = _FakeEducationVerificationRepository()
          ..downloadResult = Uint8List(2048);
        final provider = buildProvider(repository);

        final success = await provider.downloadDocumentFile('doc.pdf');

        expect(success, isTrue);
        expect(fakeDownloadDocumentFile.callCount, 1);
        expect(fakeViewDocumentFile.callCount, 0);
        expect(provider.isDownloading, isFalse);
        expect(provider.downloadErrorMessage, isNull);
      },
    );

    test('sets downloadErrorMessage on failure', () async {
      final repository = _FakeEducationVerificationRepository()
        ..downloadError = ApiException('Server error, please try again later.');
      final provider = buildProvider(repository);

      final success = await provider.downloadDocumentFile('doc.pdf');

      expect(success, isFalse);
      expect(
        provider.downloadErrorMessage,
        'Server error, please try again later.',
      );
    });

    test('a duplicate in-flight download is ignored', () async {
      final repository = _FakeEducationVerificationRepository()
        ..downloadDelay = const Duration(milliseconds: 50);
      final provider = buildProvider(repository);

      final results = await Future.wait([
        provider.downloadDocumentFile('doc.pdf'),
        provider.downloadDocumentFile('doc.pdf'),
      ]);

      expect(repository.downloadCallCount, 1);
      expect(results.where((r) => r).length, 1);
    });
  });

  test('reset() clears state and is called on logout', () async {
    final repository = _FakeEducationVerificationRepository()
      ..statusResult = _verification(status: 'pending');
    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final provider = StudentEducationVerificationProvider(
      repository: repository,
      authProvider: authProvider,
      viewDocumentFile: fakeViewDocumentFile.call,
      downloadDocumentFile: fakeDownloadDocumentFile.call,
    );

    await provider.load();
    expect(provider.verification, isNotNull);

    await authProvider.logout();

    expect(provider.verification, isNull);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, isNull);
    expect(provider.isSubmitting, isFalse);
    expect(provider.formErrorMessage, isNull);
    expect(provider.isViewingDocument, isFalse);
    expect(provider.viewErrorMessage, isNull);
    expect(provider.isDownloading, isFalse);
    expect(provider.downloadErrorMessage, isNull);
  });
}
