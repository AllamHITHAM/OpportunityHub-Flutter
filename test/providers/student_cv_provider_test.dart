// Direct unit tests for StudentCvProvider, using a fake repository (no real
// network) and a real AuthProvider (with a fake AuthRepository) so the
// reset-on-logout listener can be exercised genuinely.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/cv/data/cv_repository.dart';
import 'package:opportunityhub_flutter/models/cv_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/student_cv_provider.dart';

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
    // A no-op: this test only cares that AuthProvider.logout() flips
    // `isAuthenticated` to false (which it does regardless of what the
    // repository does), not about the real network/secure-storage calls
    // that would otherwise require a platform-channel binding.
  }
}

CvModel _cv({
  int id = 1,
  String title = 'My CV',
  bool isDefault = false,
  int version = 1,
}) {
  return CvModel(
    id: id,
    studentId: 1,
    title: title,
    filePath: 'cvs/my-cv.pdf',
    version: version,
    isDefault: isDefault,
    createdByAi: false,
  );
}

class _FakeCvRepository extends CvRepository {
  _FakeCvRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<CvModel> listResult = [];
  ApiException? listError;

  /// A non-[ApiException] error — simulates what the real repository would
  /// throw if the backend ever returned malformed CV JSON (a failed type
  /// cast inside `CvModel.fromJson`), without needing to duplicate that
  /// parsing here.
  Object? listRuntimeError;
  int getStudentCvsCallCount = 0;

  CvModel? createResult;
  ApiException? createError;
  int createCallCount = 0;

  ApiException? deleteError;
  Duration deleteDelay = Duration.zero;
  int deleteCallCount = 0;

  CvModel? setDefaultResult;
  ApiException? setDefaultError;
  Duration setDefaultDelay = Duration.zero;
  int setDefaultCallCount = 0;

  @override
  Future<List<CvModel>> getStudentCvs() async {
    getStudentCvsCallCount++;
    if (listRuntimeError != null) throw listRuntimeError!;
    if (listError != null) throw listError!;
    return listResult;
  }

  @override
  Future<CvModel> createCv({
    required String title,
    required String filePath,
  }) async {
    createCallCount++;
    if (createError != null) throw createError!;
    return createResult!;
  }

  @override
  Future<void> deleteCv(int cvId) async {
    deleteCallCount++;
    if (deleteDelay > Duration.zero) {
      await Future<void>.delayed(deleteDelay);
    }
    if (deleteError != null) throw deleteError!;
  }

  @override
  Future<CvModel> setDefaultCv(int cvId) async {
    setDefaultCallCount++;
    if (setDefaultDelay > Duration.zero) {
      await Future<void>.delayed(setDefaultDelay);
    }
    if (setDefaultError != null) throw setDefaultError!;
    return setDefaultResult!;
  }
}

void main() {
  late AuthProvider authProvider;
  late _FakeCvRepository repository;
  late StudentCvProvider provider;

  setUp(() {
    authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    repository = _FakeCvRepository();
    provider = StudentCvProvider(
      repository: repository,
      authProvider: authProvider,
    );
  });

  test('initial fetch success populates the list', () async {
    repository.listResult = [_cv(id: 1), _cv(id: 2)];

    await provider.loadCvs();

    expect(provider.cvs, hasLength(2));
    expect(provider.isLoadingList, isFalse);
    expect(provider.listErrorMessage, isNull);
  });

  test('initial fetch failure surfaces the error and is retryable', () async {
    repository.listError = ApiException(
      'Server error, please try again later.',
    );

    await provider.loadCvs();

    expect(provider.listErrorMessage, 'Server error, please try again later.');
    expect(provider.cvs, isEmpty);

    repository.listError = null;
    repository.listResult = [_cv()];
    await provider.loadCvs(forceRefresh: true);

    expect(provider.listErrorMessage, isNull);
    expect(provider.cvs, hasLength(1));
  });

  test('malformed list data (an unexpected runtime error) never leaves the '
      'provider stuck loading, and clears the pending fetch', () async {
    repository.listRuntimeError = TypeError();

    await provider.loadCvs();

    expect(provider.isLoadingList, isFalse);
    expect(provider.listErrorMessage, isNotNull);
    // Not a raw exception/stack-trace string — a safe, human-readable
    // fallback message.
    expect(provider.listErrorMessage, isNot(contains('TypeError')));

    // The pending-fetch guard was cleared too, so a subsequent call
    // starts a genuinely new fetch rather than being stuck forever.
    repository.listRuntimeError = null;
    repository.listResult = [_cv()];
    await provider.loadCvs();

    expect(provider.listErrorMessage, isNull);
    expect(provider.cvs, hasLength(1));
  });

  test('concurrent duplicate list fetches are prevented', () async {
    repository.listResult = [_cv()];

    final first = provider.loadCvs();
    final second = provider.loadCvs();
    await Future.wait([first, second]);

    expect(repository.getStudentCvsCallCount, 1);
  });

  test('create success appends the new CV to the list', () async {
    repository.listResult = [_cv(id: 1)];
    await provider.loadCvs();

    repository.createResult = _cv(id: 2, title: 'New CV');
    final created = await provider.createCv(
      title: 'New CV',
      filePath: 'cvs/new.pdf',
    );

    expect(created?.id, 2);
    expect(provider.cvs, hasLength(2));
    expect(provider.cvs.map((cv) => cv.id), containsAll([1, 2]));
  });

  test(
    'create failure preserves the existing list and surfaces an error',
    () async {
      repository.listResult = [_cv(id: 1)];
      await provider.loadCvs();

      repository.createError = ApiException('The given data was invalid.');
      final created = await provider.createCv(
        title: '',
        filePath: 'cvs/new.pdf',
      );

      expect(created, isNull);
      expect(provider.formErrorMessage, 'The given data was invalid.');
      expect(provider.cvs, hasLength(1));
    },
  );

  test(
    'create failure prefers the first field-specific validation message over the generic one',
    () async {
      repository.createError = ApiException(
        'The given data was invalid.',
        statusCode: 422,
        errors: {
          'title': ['The title field must not be greater than 255 characters.'],
        },
      );

      final created = await provider.createCv(
        title: 'x' * 300,
        filePath: 'cvs/new.pdf',
      );

      expect(created, isNull);
      expect(
        provider.formErrorMessage,
        'The title field must not be greater than 255 characters.',
      );
    },
  );

  test(
    'create failure falls back to the generic message when there are no field errors',
    () async {
      repository.createError = ApiException(
        'Server error, please try again later.',
      );

      await provider.createCv(title: 'New CV', filePath: 'cvs/new.pdf');

      expect(
        provider.formErrorMessage,
        'Server error, please try again later.',
      );
    },
  );

  test('delete success removes the item from the list', () async {
    repository.listResult = [_cv(id: 1), _cv(id: 2)];
    await provider.loadCvs();

    final success = await provider.deleteCv(1);

    expect(success, isTrue);
    expect(provider.cvs.map((cv) => cv.id), [2]);
  });

  test(
    'delete 409 keeps the item visible and exposes the exact backend message',
    () async {
      repository.listResult = [_cv(id: 1), _cv(id: 2)];
      await provider.loadCvs();

      repository.deleteError = ApiException(
        'Cannot delete a CV that has been used in an application',
        statusCode: 409,
      );
      final success = await provider.deleteCv(1);

      expect(success, isFalse);
      expect(provider.cvs.map((cv) => cv.id), containsAll([1, 2]));
      expect(
        provider.actionErrorMessage,
        'Cannot delete a CV that has been used in an application',
      );
    },
  );

  test('setDefaultCv results in only one default CV in local state', () async {
    repository.listResult = [
      _cv(id: 1, isDefault: true),
      _cv(id: 2, isDefault: false),
    ];
    await provider.loadCvs();

    repository.setDefaultResult = _cv(id: 2, isDefault: true);
    final success = await provider.setDefaultCv(2);

    expect(success, isTrue);
    expect(provider.cvs.where((cv) => cv.isDefault).length, 1);
    expect(provider.cvs.firstWhere((cv) => cv.id == 2).isDefault, isTrue);
    expect(provider.cvs.firstWhere((cv) => cv.id == 1).isDefault, isFalse);
    expect(provider.defaultCv?.id, 2);
  });

  test('setDefaultCv failure leaves the previous default intact', () async {
    repository.listResult = [
      _cv(id: 1, isDefault: true),
      _cv(id: 2, isDefault: false),
    ];
    await provider.loadCvs();

    repository.setDefaultError = ApiException('CV not found', statusCode: 404);
    final success = await provider.setDefaultCv(2);

    expect(success, isFalse);
    expect(provider.defaultCv?.id, 1);
    expect(provider.actionErrorMessage, 'CV not found');
  });

  test(
    'busy-state protection: isBusy is true only during an in-flight action',
    () async {
      repository.listResult = [_cv(id: 1)];
      await provider.loadCvs();

      expect(provider.isBusy(1), isFalse);

      final future = provider.deleteCv(1);
      expect(provider.isBusy(1), isTrue);

      await future;
      expect(provider.isBusy(1), isFalse);
    },
  );

  test(
    'a second deleteCv call for the same CV while one is in flight triggers only one repository call',
    () async {
      repository.listResult = [_cv(id: 1)];
      repository.deleteDelay = const Duration(milliseconds: 50);
      await provider.loadCvs();

      final first = provider.deleteCv(1);
      final second = provider.deleteCv(1);

      final results = await Future.wait([first, second]);

      expect(repository.deleteCallCount, 1);
      // Exactly one of the two calls actually performed the delete; the
      // other was blocked and returned false immediately.
      expect(results.where((success) => success).length, 1);
      expect(results.where((success) => !success).length, 1);
    },
  );

  test(
    'a second setDefaultCv call for the same CV while one is in flight triggers only one repository call',
    () async {
      repository.listResult = [_cv(id: 1)];
      repository.setDefaultDelay = const Duration(milliseconds: 50);
      repository.setDefaultResult = _cv(id: 1, isDefault: true);
      await provider.loadCvs();

      final first = provider.setDefaultCv(1);
      final second = provider.setDefaultCv(1);

      final results = await Future.wait([first, second]);

      expect(repository.setDefaultCallCount, 1);
      expect(results.where((success) => success).length, 1);
      expect(results.where((success) => !success).length, 1);
    },
  );

  test(
    'a conflicting setDefaultCv is blocked while a deleteCv is in flight for the same CV',
    () async {
      repository.listResult = [_cv(id: 1)];
      repository.deleteDelay = const Duration(milliseconds: 50);
      await provider.loadCvs();

      final deleteFuture = provider.deleteCv(1);
      final setDefaultResult = await provider.setDefaultCv(1);

      expect(setDefaultResult, isFalse);
      expect(repository.setDefaultCallCount, 0);

      await deleteFuture;
      expect(repository.deleteCallCount, 1);
    },
  );

  test(
    'deleteCv for a different CV is not blocked while another CV is busy',
    () async {
      repository.listResult = [_cv(id: 1), _cv(id: 2)];
      repository.deleteDelay = const Duration(milliseconds: 50);
      await provider.loadCvs();

      final first = provider.deleteCv(1);
      final second = provider.deleteCv(2);

      final results = await Future.wait([first, second]);

      expect(repository.deleteCallCount, 2);
      expect(results, [true, true]);
    },
  );

  test('defaultCv is null when no CV is marked default', () async {
    repository.listResult = [_cv(id: 1), _cv(id: 2)];
    await provider.loadCvs();

    expect(provider.defaultCv, isNull);
  });

  test('reset clears all state (called on logout)', () async {
    repository.listResult = [_cv(id: 1)];
    await provider.loadCvs();
    expect(provider.cvs, isNotEmpty);

    await authProvider.logout();

    expect(provider.cvs, isEmpty);
    expect(provider.listErrorMessage, isNull);
    expect(provider.formErrorMessage, isNull);
    expect(provider.actionErrorMessage, isNull);
  });

  test('switching users cannot leak the previous student\'s CVs', () async {
    repository.listResult = [_cv(id: 1, title: 'Student A CV')];
    await provider.loadCvs();
    expect(provider.cvs.single.title, 'Student A CV');

    await authProvider.logout();
    repository.listResult = [_cv(id: 2, title: 'Student B CV')];
    await provider.loadCvs();

    expect(provider.cvs, hasLength(1));
    expect(provider.cvs.single.title, 'Student B CV');
  });
}
