// Direct unit tests for StudentCvProvider, using a fake repository (no real
// network) and a real AuthProvider (with a fake AuthRepository) so the
// reset-on-logout listener can be exercised genuinely.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/utils/cv_file_open_result.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/cv/data/cv_repository.dart';
import 'package:opportunityhub_flutter/features/cv/data/picked_cv_file.dart';
import 'package:opportunityhub_flutter/features/skills/data/student_skill_repository.dart';
import 'package:opportunityhub_flutter/models/cv_model.dart';
import 'package:opportunityhub_flutter/models/cv_skill_suggestion_model.dart';
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
  PickedCvFile? lastCreateFile;

  ApiException? deleteError;
  Duration deleteDelay = Duration.zero;
  int deleteCallCount = 0;

  CvModel? setDefaultResult;
  ApiException? setDefaultError;
  Duration setDefaultDelay = Duration.zero;
  int setDefaultCallCount = 0;

  Uint8List? downloadResult;
  ApiException? downloadError;
  Object? downloadRuntimeError;
  Duration downloadDelay = Duration.zero;
  int downloadCallCount = 0;

  List<CvSkillSuggestion> extractSkillsResult = [];
  ApiException? extractSkillsError;
  Duration extractSkillsDelay = Duration.zero;
  int extractSkillsCallCount = 0;

  @override
  Future<List<CvSkillSuggestion>> extractSkills(int cvId) async {
    extractSkillsCallCount++;
    if (extractSkillsDelay > Duration.zero) {
      await Future<void>.delayed(extractSkillsDelay);
    }
    if (extractSkillsError != null) throw extractSkillsError!;
    return extractSkillsResult;
  }

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
    required PickedCvFile file,
  }) async {
    createCallCount++;
    lastCreateFile = file;
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

  @override
  Future<Uint8List> downloadCv(int cvId) async {
    downloadCallCount++;
    if (downloadDelay > Duration.zero) {
      await Future<void>.delayed(downloadDelay);
    }
    if (downloadRuntimeError != null) throw downloadRuntimeError!;
    if (downloadError != null) throw downloadError!;
    return downloadResult ?? Uint8List.fromList([0x25, 0x50, 0x44, 0x46]);
  }
}

class _FakeStudentSkillRepository extends StudentSkillRepository {
  _FakeStudentSkillRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  /// skillId -> error to throw for that specific skill, if any. Skills not
  /// present here succeed.
  final Map<int, ApiException> errorsBySkillId = {};
  final List<int> addedSkillIds = [];
  final List<String> addedSources = [];
  final List<int?> addedCvIds = [];

  @override
  Future<void> addSkill({
    required int skillId,
    String level = 'intermediate',
    String source = 'manual',
    int? cvId,
  }) async {
    addedSkillIds.add(skillId);
    addedSources.add(source);
    addedCvIds.add(cvId);
    final error = errorsBySkillId[skillId];
    if (error != null) throw error;
  }
}

PickedCvFile _file({String filename = 'resume.pdf'}) {
  return PickedCvFile(
    filename: filename,
    bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]),
  );
}

/// A fake platform CV-file action (View or Download) — real success means
/// the real `cv_file_opener` implementation was actually invoked with the
/// fetched bytes, never assumed just because the repository call
/// succeeded. Configurable to simulate the platform reporting a real
/// failure (e.g. a popup blocked, or "not supported on this platform").
class _FakeCvFileAction {
  _FakeCvFileAction();

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
  late AuthProvider authProvider;
  late _FakeCvRepository repository;
  late _FakeStudentSkillRepository studentSkillRepository;
  late _FakeCvFileAction fakeViewCvFile;
  late _FakeCvFileAction fakeDownloadCvFile;
  late StudentCvProvider provider;

  setUp(() {
    authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    repository = _FakeCvRepository();
    studentSkillRepository = _FakeStudentSkillRepository();
    fakeViewCvFile = _FakeCvFileAction();
    fakeDownloadCvFile = _FakeCvFileAction();
    provider = StudentCvProvider(
      repository: repository,
      studentSkillRepository: studentSkillRepository,
      authProvider: authProvider,
      viewCvFile: fakeViewCvFile.call,
      downloadCvFile: fakeDownloadCvFile.call,
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
    final created = await provider.createCv(title: 'New CV', file: _file());

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
      final created = await provider.createCv(title: '', file: _file());

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

      final created = await provider.createCv(title: 'x' * 300, file: _file());

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

      await provider.createCv(title: 'New CV', file: _file());

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

  test('create sends the picked file through to the repository', () async {
    repository.createResult = _cv(id: 2, title: 'New CV');
    final file = _file(filename: 'my-resume.pdf');

    await provider.createCv(title: 'New CV', file: file);

    expect(repository.lastCreateFile, same(file));
  });

  group('viewCv (UI Phase 6.3)', () {
    test('success fetches real bytes and invokes the real platform opener', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      repository.downloadResult = bytes;

      final success = await provider.viewCv(1, 'My CV');

      expect(success, isTrue);
      expect(fakeViewCvFile.callCount, 1);
      expect(fakeViewCvFile.lastBytes, bytes);
      expect(fakeViewCvFile.lastFileName, 'My CV.pdf');
      expect(fakeDownloadCvFile.callCount, 0);
      expect(provider.isViewingCv(1), isFalse);
      expect(provider.viewErrorMessage, isNull);
    });

    test('never claims success merely because bytes were fetched', () async {
      // The repository call succeeds, but the real platform opener
      // reports it could not actually open the file (e.g. a blocked
      // popup) — this must never be reported as success.
      fakeViewCvFile.result = const CvFileOpenResult(
        success: false,
        errorMessage: "Couldn't open the CV — your browser may have blocked the new tab.",
      );

      final success = await provider.viewCv(1, 'My CV');

      expect(success, isFalse);
      expect(
        provider.viewErrorMessage,
        "Couldn't open the CV — your browser may have blocked the new tab.",
      );
    });

    test('a backend fetch failure exposes the backend message', () async {
      repository.downloadError = ApiException('CV file not found', statusCode: 404);

      final success = await provider.viewCv(1, 'My CV');

      expect(success, isFalse);
      expect(provider.viewErrorMessage, 'CV file not found');
      expect(fakeViewCvFile.callCount, 0);
    });

    test('an unexpected failure exposes a safe message', () async {
      repository.downloadRuntimeError = TypeError();

      final success = await provider.viewCv(1, 'My CV');

      expect(success, isFalse);
      expect(provider.viewErrorMessage, isNotNull);
      expect(provider.viewErrorMessage, isNot(contains('TypeError')));
    });

    test('isViewingCv is true only during an in-flight view', () async {
      repository.downloadDelay = const Duration(milliseconds: 50);

      expect(provider.isViewingCv(1), isFalse);
      final future = provider.viewCv(1, 'My CV');
      expect(provider.isViewingCv(1), isTrue);

      await future;
      expect(provider.isViewingCv(1), isFalse);
    });

    test('a duplicate view for the same CV while in flight is blocked', () async {
      repository.downloadDelay = const Duration(milliseconds: 50);

      final first = provider.viewCv(1, 'My CV');
      final second = provider.viewCv(1, 'My CV');

      final results = await Future.wait([first, second]);

      expect(repository.downloadCallCount, 1);
      expect(results.where((r) => r).length, 1);
      expect(results.where((r) => !r).length, 1);
    });

    test('reset also clears view state', () async {
      repository.downloadError = ApiException('CV file not found');
      await provider.viewCv(1, 'My CV');
      expect(provider.viewErrorMessage, isNotNull);

      await authProvider.logout();

      expect(provider.viewErrorMessage, isNull);
      expect(provider.isViewingCv(1), isFalse);
    });
  });

  group('downloadCvFile (UI Phase 6.3)', () {
    test(
      'success fetches real bytes and invokes the real platform opener, distinct from viewCv',
      () async {
        final bytes = Uint8List.fromList([1, 2, 3, 4]);
        repository.downloadResult = bytes;

        final success = await provider.downloadCvFile(1, 'My CV');

        expect(success, isTrue);
        expect(fakeDownloadCvFile.callCount, 1);
        expect(fakeDownloadCvFile.lastBytes, bytes);
        expect(fakeDownloadCvFile.lastFileName, 'My CV.pdf');
        expect(fakeViewCvFile.callCount, 0);
        expect(provider.isDownloading(1), isFalse);
        expect(provider.downloadErrorMessage, isNull);
      },
    );

    test('never claims success merely because bytes were fetched', () async {
      fakeDownloadCvFile.result = const CvFileOpenResult(
        success: false,
        errorMessage: "Couldn't download the CV.",
      );

      final success = await provider.downloadCvFile(1, 'My CV');

      expect(success, isFalse);
      expect(provider.downloadErrorMessage, "Couldn't download the CV.");
    });

    test('a backend fetch failure exposes the backend message', () async {
      repository.downloadError = ApiException('CV file not found', statusCode: 404);

      final success = await provider.downloadCvFile(1, 'My CV');

      expect(success, isFalse);
      expect(provider.downloadErrorMessage, 'CV file not found');
    });

    test('isDownloading is true only during an in-flight download', () async {
      repository.downloadDelay = const Duration(milliseconds: 50);

      expect(provider.isDownloading(1), isFalse);
      final future = provider.downloadCvFile(1, 'My CV');
      expect(provider.isDownloading(1), isTrue);

      await future;
      expect(provider.isDownloading(1), isFalse);
    });

    test(
      'a duplicate download for the same CV while in flight is blocked',
      () async {
        repository.downloadDelay = const Duration(milliseconds: 50);

        final first = provider.downloadCvFile(1, 'My CV');
        final second = provider.downloadCvFile(1, 'My CV');

        final results = await Future.wait([first, second]);

        expect(repository.downloadCallCount, 1);
        expect(results.where((r) => r).length, 1);
        expect(results.where((r) => !r).length, 1);
      },
    );

    test('reset also clears download state', () async {
      repository.downloadError = ApiException('CV file not found');
      await provider.downloadCvFile(1, 'My CV');
      expect(provider.downloadErrorMessage, isNotNull);

      await authProvider.logout();

      expect(provider.downloadErrorMessage, isNull);
      expect(provider.isDownloading(1), isFalse);
    });
  });

  // -----------------------------------------------------------------
  // AI CV Skill Extraction (Phase 8A-6)
  // -----------------------------------------------------------------

  test('extractSkills success populates suggestions', () async {
    repository.extractSkillsResult = [
      const CvSkillSuggestion(
        name: 'AutoCAD',
        confidence: 0.9,
        skillId: 5,
        isAvailable: true,
        alreadyAdded: false,
      ),
    ];

    await provider.extractSkills(7);

    expect(provider.skillSuggestions, hasLength(1));
    expect(provider.skillSuggestions.single.name, 'AutoCAD');
    expect(provider.extractionErrorMessage, isNull);
    expect(provider.isExtracting, isFalse);
  });

  test(
    'extractSkills failure surfaces the error and clears suggestions',
    () async {
      repository.extractSkillsError = ApiException(
        'Text could not be extracted from this CV.',
        statusCode: 422,
      );

      await provider.extractSkills(7);

      expect(provider.skillSuggestions, isEmpty);
      expect(
        provider.extractionErrorMessage,
        'Text could not be extracted from this CV.',
      );
    },
  );

  test(
    'extractSkills failure preserves the existing CV list untouched',
    () async {
      repository.listResult = [_cv(id: 1)];
      await provider.loadCvs();

      repository.extractSkillsError = ApiException('AI unavailable');
      await provider.extractSkills(1);

      expect(provider.cvs, hasLength(1));
    },
  );

  test(
    'isExtracting is true only during an in-flight extraction, scoped to the CV',
    () async {
      repository.extractSkillsDelay = const Duration(milliseconds: 50);

      expect(provider.isExtracting, isFalse);
      final future = provider.extractSkills(3);
      expect(provider.isExtracting, isTrue);
      expect(provider.extractingCvId, 3);

      await future;
      expect(provider.isExtracting, isFalse);
    },
  );

  test(
    'a duplicate extractSkills call while one is in flight is ignored',
    () async {
      repository.extractSkillsDelay = const Duration(milliseconds: 50);

      final first = provider.extractSkills(1);
      final second = provider.extractSkills(1);

      await Future.wait([first, second]);

      expect(repository.extractSkillsCallCount, 1);
    },
  );

  test(
    'addSelectedSkills posts each skill and marks it already added',
    () async {
      repository.extractSkillsResult = [
        const CvSkillSuggestion(
          name: 'AutoCAD',
          confidence: 0.9,
          skillId: 5,
          isAvailable: true,
          alreadyAdded: false,
        ),
        const CvSkillSuggestion(
          name: 'Revit',
          confidence: 0.8,
          skillId: 6,
          isAvailable: true,
          alreadyAdded: false,
        ),
      ];
      await provider.extractSkills(1);

      final success = await provider.addSelectedSkills([5, 6]);

      expect(success, isTrue);
      expect(studentSkillRepository.addedSkillIds, containsAll([5, 6]));
      expect(provider.skillSuggestions.every((s) => s.alreadyAdded), isTrue);
    },
  );

  test('addSelectedSkills always claims source cv_ai with the analyzed CV id '
      'as secure evidence -- never a spoofable manual claim', () async {
    repository.extractSkillsResult = [
      const CvSkillSuggestion(
        name: 'AutoCAD',
        confidence: 0.9,
        skillId: 5,
        isAvailable: true,
        alreadyAdded: false,
      ),
    ];
    await provider.extractSkills(42);

    await provider.addSelectedSkills([5]);

    expect(studentSkillRepository.addedSources, ['cv_ai']);
    expect(studentSkillRepository.addedCvIds, [42]);
  });

  test(
    'addSelectedSkills partial failure reports an error but still adds the successful ones',
    () async {
      repository.extractSkillsResult = [
        const CvSkillSuggestion(
          name: 'AutoCAD',
          confidence: 0.9,
          skillId: 5,
          isAvailable: true,
          alreadyAdded: false,
        ),
        const CvSkillSuggestion(
          name: 'Revit',
          confidence: 0.8,
          skillId: 6,
          isAvailable: true,
          alreadyAdded: false,
        ),
      ];
      await provider.extractSkills(1);
      studentSkillRepository.errorsBySkillId[6] = ApiException(
        'You have already added this skill',
        statusCode: 409,
      );

      final success = await provider.addSelectedSkills([5, 6]);

      expect(success, isFalse);
      expect(
        provider.addSkillsErrorMessage,
        'You have already added this skill',
      );
      expect(
        provider.skillSuggestions
            .firstWhere((s) => s.skillId == 5)
            .alreadyAdded,
        isTrue,
      );
    },
  );

  test('addSelectedSkills with an empty selection does nothing', () async {
    final success = await provider.addSelectedSkills([]);

    expect(success, isFalse);
    expect(studentSkillRepository.addedSkillIds, isEmpty);
  });

  test('reset also clears extraction and add-skills state', () async {
    repository.extractSkillsResult = [
      const CvSkillSuggestion(
        name: 'AutoCAD',
        confidence: 0.9,
        skillId: 5,
        isAvailable: true,
        alreadyAdded: false,
      ),
    ];
    await provider.extractSkills(1);
    expect(provider.skillSuggestions, isNotEmpty);

    await authProvider.logout();

    expect(provider.skillSuggestions, isEmpty);
    expect(provider.extractionErrorMessage, isNull);
    expect(provider.extractingCvId, isNull);
    expect(provider.addSkillsErrorMessage, isNull);
  });
}
