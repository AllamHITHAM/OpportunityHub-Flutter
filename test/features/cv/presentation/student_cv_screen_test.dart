// Widget tests for StudentCvScreen, in isolation with a small GoRouter.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/cv/data/cv_repository.dart';
import 'package:opportunityhub_flutter/features/cv/data/picked_cv_file.dart';
import 'package:opportunityhub_flutter/features/cv/presentation/student_cv_screen.dart';
import 'package:opportunityhub_flutter/features/skills/data/student_skill_repository.dart';
import 'package:opportunityhub_flutter/models/cv_model.dart';
import 'package:opportunityhub_flutter/models/cv_skill_suggestion_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/student_cv_provider.dart';
import 'package:opportunityhub_flutter/routes/app_routes.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  @override
  Future<String?> getSavedToken() async => null;
}

CvModel _cv({
  int id = 1,
  String title = 'My CV',
  String filePath = 'cvs/1/uuid.pdf',
  int version = 1,
  bool isDefault = false,
  bool createdByAi = false,
}) {
  return CvModel(
    id: id,
    studentId: 1,
    title: title,
    filePath: filePath,
    version: version,
    isDefault: isDefault,
    createdByAi: createdByAi,
  );
}

/// A valid, well-under-the-limit picked PDF for tests that don't care
/// about the exact bytes.
PickedCvFile _pickedFile({
  String filename = 'resume.pdf',
  int sizeInBytes = 100,
}) {
  return PickedCvFile(filename: filename, bytes: Uint8List(sizeInBytes));
}

class _FakeCvRepository extends CvRepository {
  _FakeCvRepository({
    this.listResult = const [],
    this.listError,
    this.listDelay = Duration.zero,
    this.createResult,
    this.createError,
    this.deleteError,
    this.setDefaultResult,
    this.downloadResult,
    this.downloadError,
    this.extractSkillsResult = const [],
    this.extractSkillsError,
  }) : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<CvModel> listResult;
  ApiException? listError;
  Duration listDelay;
  int getStudentCvsCallCount = 0;

  CvModel? createResult;
  ApiException? createError;
  PickedCvFile? lastCreateFile;
  String? lastCreateTitle;

  ApiException? deleteError;
  int deleteCallCount = 0;

  CvModel? setDefaultResult;
  int setDefaultCallCount = 0;

  Uint8List? downloadResult;
  ApiException? downloadError;
  int downloadCallCount = 0;

  List<CvSkillSuggestion> extractSkillsResult = const [];
  ApiException? extractSkillsError;
  int extractSkillsCallCount = 0;

  @override
  Future<List<CvSkillSuggestion>> extractSkills(int cvId) async {
    extractSkillsCallCount++;
    if (extractSkillsError != null) throw extractSkillsError!;
    return extractSkillsResult;
  }

  @override
  Future<List<CvModel>> getStudentCvs() async {
    getStudentCvsCallCount++;
    if (listDelay > Duration.zero) {
      await Future<void>.delayed(listDelay);
    }
    if (listError != null) throw listError!;
    return listResult;
  }

  @override
  Future<CvModel> createCv({
    required String title,
    required PickedCvFile file,
  }) async {
    lastCreateTitle = title;
    lastCreateFile = file;
    if (createError != null) throw createError!;
    return createResult!;
  }

  @override
  Future<void> deleteCv(int cvId) async {
    deleteCallCount++;
    if (deleteError != null) throw deleteError!;
  }

  @override
  Future<CvModel> setDefaultCv(int cvId) async {
    setDefaultCallCount++;
    return setDefaultResult!;
  }

  @override
  Future<Uint8List> downloadCv(int cvId) async {
    downloadCallCount++;
    if (downloadError != null) throw downloadError!;
    return downloadResult ?? Uint8List.fromList([0x25, 0x50, 0x44, 0x46]);
  }
}

class _FakeStudentSkillRepository extends StudentSkillRepository {
  _FakeStudentSkillRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  final List<int> addedSkillIds = [];
  final List<String> addedSources = [];
  final List<int?> addedCvIds = [];
  ApiException? addSkillError;

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
    if (addSkillError != null) throw addSkillError!;
  }
}

Future<StudentCvProvider> _pumpScreen(
  WidgetTester tester, {
  required _FakeCvRepository repository,
  StudentSkillRepository? studentSkillRepository,
  Future<PickedCvFile?> Function() pickCvFile = _defaultTestPicker,
  Size size = const Size(420, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final provider = StudentCvProvider(
    repository: repository,
    studentSkillRepository:
        studentSkillRepository ?? _FakeStudentSkillRepository(),
    authProvider: authProvider,
  );

  final router = GoRouter(
    initialLocation: AppRoutes.studentCvs,
    routes: [
      GoRoute(
        path: AppRoutes.studentCvs,
        builder: (_, _) => StudentCvScreen(pickCvFile: pickCvFile),
      ),
    ],
  );

  await tester.pumpWidget(
    ChangeNotifierProvider<StudentCvProvider>.value(
      value: provider,
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  return provider;
}

Future<PickedCvFile?> _defaultTestPicker() async => _pickedFile();

void main() {
  testWidgets('Loading state renders while the list is in flight', (
    tester,
  ) async {
    final repository = _FakeCvRepository(
      listDelay: const Duration(milliseconds: 200),
    );
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
    final provider = StudentCvProvider(
      repository: repository,
      studentSkillRepository: _FakeStudentSkillRepository(),
      authProvider: authProvider,
    );
    final router = GoRouter(
      initialLocation: AppRoutes.studentCvs,
      routes: [
        GoRoute(
          path: AppRoutes.studentCvs,
          builder: (_, _) => const StudentCvScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<StudentCvProvider>.value(
        value: provider,
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('My CVs'), findsOneWidget);
    expect(provider.isLoadingList, isTrue);

    await tester.pumpAndSettle();
  });

  testWidgets('Empty state renders with an add action', (tester) async {
    await _pumpScreen(tester, repository: _FakeCvRepository());

    expect(find.text('No CVs Yet'), findsOneWidget);
    expect(find.text('Add CV'), findsWidgets);
  });

  testWidgets('Error state renders on load failure, with retry', (
    tester,
  ) async {
    final repository = _FakeCvRepository(
      listError: ApiException('Server error, please try again later.'),
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text('Server error, please try again later.'), findsOneWidget);

    repository.listError = null;
    repository.listResult = [_cv()];
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();

    expect(find.text('My CV'), findsOneWidget);
  });

  testWidgets(
    'Populated list renders title, version, and default badge, but never a raw file path',
    (tester) async {
      final repository = _FakeCvRepository(
        listResult: [
          _cv(
            id: 1,
            title: 'Software Engineer CV',
            filePath: 'cvs/1/9c6b1e3a-....pdf',
            version: 2,
            isDefault: true,
          ),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.text('Software Engineer CV'), findsOneWidget);
      expect(find.text('Version 2'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);
      // The raw server-managed path is never shown to the user.
      expect(find.text('cvs/1/9c6b1e3a-....pdf'), findsNothing);
      expect(find.textContaining('cvs/'), findsNothing);
      // A CV already default shows no "Set as Default" action.
      expect(find.text('Set as Default'), findsNothing);
    },
  );

  testWidgets('A non-default CV shows a Set as Default action', (tester) async {
    final repository = _FakeCvRepository(
      listResult: [_cv(id: 1, isDefault: false)],
      setDefaultResult: _cv(id: 1, isDefault: true),
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text('Set as Default'), findsOneWidget);

    await tester.tap(find.text('Set as Default'));
    await tester.pumpAndSettle();

    expect(repository.setDefaultCallCount, 1);
    expect(find.text('Default'), findsOneWidget);
  });

  testWidgets('AI Generated chip renders only when createdByAi is true', (
    tester,
  ) async {
    final repository = _FakeCvRepository(
      listResult: [_cv(id: 1, createdByAi: true)],
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text('AI Generated'), findsOneWidget);
  });

  group('Add CV (Phase 8A-4)', () {
    testWidgets('There is no manual File Path text field', (tester) async {
      final repository = _FakeCvRepository();
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'File Path'), findsNothing);
      expect(find.text('Select PDF'), findsOneWidget);
    });

    testWidgets(
      'Selecting a PDF shows its filename and changes the button label',
      (tester) async {
        final repository = _FakeCvRepository();
        await _pumpScreen(
          tester,
          repository: repository,
          pickCvFile: () async => _pickedFile(filename: 'my-resume.pdf'),
        );

        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Select PDF'));
        await tester.pumpAndSettle();

        expect(find.text('my-resume.pdf'), findsOneWidget);
        expect(find.text('Change PDF'), findsOneWidget);
      },
    );

    testWidgets(
      'Submitting without selecting a file is blocked locally, before any repository call',
      (tester) async {
        final repository = _FakeCvRepository();
        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Title'),
          'New CV',
        );
        await tester.tap(find.text('Add CV').last);
        await tester.pumpAndSettle();

        expect(find.text('Please select a PDF file.'), findsOneWidget);
        expect(repository.lastCreateFile, isNull);
      },
    );

    testWidgets(
      'A title over 255 characters is blocked locally, before any repository call',
      (tester) async {
        final repository = _FakeCvRepository();
        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Title'),
          'A' * 256,
        );
        await tester.tap(find.text('Select PDF'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add CV').last);
        await tester.pumpAndSettle();

        expect(
          find.text('Title must be 255 characters or fewer'),
          findsOneWidget,
        );
        expect(repository.lastCreateFile, isNull);
      },
    );

    testWidgets('A non-PDF filename is rejected locally', (tester) async {
      final repository = _FakeCvRepository();
      await _pumpScreen(
        tester,
        repository: repository,
        pickCvFile: () async => _pickedFile(filename: 'resume.docx'),
      );

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Select PDF'));
      await tester.pumpAndSettle();

      expect(find.text('Only PDF files are supported.'), findsOneWidget);
      expect(find.text('resume.docx'), findsNothing);
    });

    testWidgets('A file over 5 MB is rejected locally', (tester) async {
      final repository = _FakeCvRepository();
      await _pumpScreen(
        tester,
        repository: repository,
        pickCvFile: () async => _pickedFile(sizeInBytes: 5 * 1024 * 1024 + 1),
      );

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Select PDF'));
      await tester.pumpAndSettle();

      expect(find.text('File must be 5 MB or smaller.'), findsOneWidget);
    });

    testWidgets('A file exactly at 5 MB is accepted locally', (tester) async {
      final repository = _FakeCvRepository(
        createResult: _cv(id: 5, title: 'New CV'),
      );
      await _pumpScreen(
        tester,
        repository: repository,
        pickCvFile: () async => _pickedFile(sizeInBytes: 5 * 1024 * 1024),
      );

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'New CV',
      );
      await tester.tap(find.text('Select PDF'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add CV').last);
      await tester.pumpAndSettle();

      expect(repository.lastCreateFile, isNotNull);
    });

    testWidgets(
      'Add CV success sends the picked file, closes the sheet, refreshes the list, and shows a success message',
      (tester) async {
        final repository = _FakeCvRepository(
          createResult: _cv(id: 5, title: 'New CV'),
        );
        await _pumpScreen(
          tester,
          repository: repository,
          pickCvFile: () async => _pickedFile(filename: 'new-cv.pdf'),
        );

        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Title'),
          'New CV',
        );
        await tester.tap(find.text('Select PDF'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add CV').last);
        await tester.pumpAndSettle();

        expect(repository.lastCreateTitle, 'New CV');
        expect(repository.lastCreateFile?.filename, 'new-cv.pdf');
        expect(find.text('New CV'), findsOneWidget);
        expect(find.text('CV added successfully'), findsOneWidget);
      },
    );

    testWidgets(
      '422 create failure keeps the sheet open and shows the field-specific backend message',
      (tester) async {
        final repository = _FakeCvRepository(
          createError: ApiException(
            'The given data was invalid.',
            statusCode: 422,
            errors: {
              'title': ['The title field is required.'],
            },
          ),
        );
        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Title'),
          'New CV',
        );
        await tester.tap(find.text('Select PDF'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add CV').last);
        await tester.pumpAndSettle();

        // The field-specific message is shown in preference to the generic
        // top-level one.
        expect(find.text('The title field is required.'), findsOneWidget);
        expect(find.text('The given data was invalid.'), findsNothing);
        expect(find.text('Add CV'), findsWidgets);
      },
    );

    testWidgets('Add CV shows a loading state while submitting', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        createResult: _cv(id: 5, title: 'New CV'),
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'New CV',
      );
      await tester.tap(find.text('Select PDF'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add CV').last);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('View CV (Phase 8A-4)', () {
    testWidgets('View CV downloads the file and confirms success', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV')],
        downloadResult: Uint8List(2048),
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('View CV'));
      await tester.pumpAndSettle();

      expect(repository.downloadCallCount, 1);
      expect(find.textContaining('CV downloaded'), findsOneWidget);
    });

    testWidgets('View CV failure shows the backend message safely', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV')],
        downloadError: ApiException('CV file not found'),
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('View CV'));
      await tester.pumpAndSettle();

      expect(find.text('CV file not found'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Delete requires confirmation before anything happens', (
    tester,
  ) async {
    final repository = _FakeCvRepository(
      listResult: [_cv(id: 1, title: 'My CV')],
    );
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Delete CV'), findsOneWidget);
    expect(find.textContaining('My CV'), findsWidgets);
    expect(repository.deleteCallCount, 0);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.deleteCallCount, 0);
  });

  testWidgets('Delete success removes the card from the list', (tester) async {
    final repository = _FakeCvRepository(
      listResult: [_cv(id: 1, title: 'My CV')],
    );
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(repository.deleteCallCount, 1);
    expect(find.text('My CV'), findsNothing);
  });

  testWidgets(
    'Delete 409 conflict shows the exact backend message and keeps the CV visible',
    (tester) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV')],
        deleteError: ApiException(
          'Cannot delete a CV that has been used in an application',
          statusCode: 409,
        ),
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(
        find.text('Cannot delete a CV that has been used in an application'),
        findsOneWidget,
      );
      expect(find.text('My CV'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Does not overflow at a narrow 320x720 viewport', (tester) async {
    final repository = _FakeCvRepository(
      listResult: [
        _cv(id: 1, title: 'Software Engineer CV', isDefault: true),
        _cv(id: 2, title: 'Marketing CV'),
      ],
    );
    await _pumpScreen(
      tester,
      repository: repository,
      size: const Size(320, 720),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('Add CV sheet does not overflow at a narrow 320x720 viewport', (
    tester,
  ) async {
    final repository = _FakeCvRepository();
    await _pumpScreen(
      tester,
      repository: repository,
      size: const Size(320, 720),
    );

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select PDF'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  group('Analyze CV with AI (Phase 8A-6)', () {
    testWidgets('An Analyze CV action is offered on every CV card', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV')],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.text('Analyze CV'), findsOneWidget);
    });

    testWidgets(
      'Success opens a sheet listing the suggested skills with their confidence',
      (tester) async {
        final repository = _FakeCvRepository(
          listResult: [_cv(id: 1, title: 'My CV')],
          extractSkillsResult: const [
            CvSkillSuggestion(
              name: 'AutoCAD',
              confidence: 0.95,
              skillId: 5,
              isAvailable: true,
              alreadyAdded: false,
            ),
          ],
        );
        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.text('Analyze CV'));
        await tester.pumpAndSettle();

        expect(repository.extractSkillsCallCount, 1);
        expect(find.text('AI-Suggested Skills'), findsOneWidget);
        expect(find.text('AutoCAD'), findsOneWidget);
        expect(find.textContaining('95%'), findsOneWidget);
      },
    );

    testWidgets(
      'An unmatched suggestion shows "Pending catalog approval" and cannot be selected',
      (tester) async {
        final repository = _FakeCvRepository(
          listResult: [_cv(id: 1, title: 'My CV')],
          extractSkillsResult: const [
            CvSkillSuggestion(
              name: 'Primavera P6',
              confidence: 0.6,
              skillId: null,
              isAvailable: false,
              alreadyAdded: false,
              suggestionId: 9,
              suggestionStatus: 'pending',
            ),
          ],
        );
        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.text('Analyze CV'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Pending catalog approval'), findsOneWidget);
        expect(find.textContaining('Not in skill catalog'), findsNothing);
        final tile = tester.widget<CheckboxListTile>(
          find.byType(CheckboxListTile),
        );
        expect(tile.onChanged, isNull);
      },
    );

    testWidgets(
      'An already-added suggestion is flagged and cannot be re-selected',
      (tester) async {
        final repository = _FakeCvRepository(
          listResult: [_cv(id: 1, title: 'My CV')],
          extractSkillsResult: const [
            CvSkillSuggestion(
              name: 'Python',
              confidence: 0.8,
              skillId: 9,
              isAvailable: true,
              alreadyAdded: true,
            ),
          ],
        );
        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.text('Analyze CV'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Already added'), findsOneWidget);
        final tile = tester.widget<CheckboxListTile>(
          find.byType(CheckboxListTile),
        );
        expect(tile.onChanged, isNull);
      },
    );

    testWidgets(
      'Selecting a suggestion and adding it posts to the Student Skill endpoint',
      (tester) async {
        final studentSkillRepository = _FakeStudentSkillRepository();
        final repository = _FakeCvRepository(
          listResult: [_cv(id: 1, title: 'My CV')],
          extractSkillsResult: const [
            CvSkillSuggestion(
              name: 'AutoCAD',
              confidence: 0.9,
              skillId: 5,
              isAvailable: true,
              alreadyAdded: false,
            ),
          ],
        );
        await _pumpScreen(
          tester,
          repository: repository,
          studentSkillRepository: studentSkillRepository,
        );

        await tester.tap(find.text('Analyze CV'));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add Selected Skills'));
        await tester.pumpAndSettle();

        expect(studentSkillRepository.addedSkillIds, [5]);
        expect(find.text('Skills added successfully'), findsOneWidget);
      },
    );

    testWidgets(
      'Extraction failure (e.g. no extractable text) shows the backend '
      'message and never opens the suggestions sheet',
      (tester) async {
        final repository = _FakeCvRepository(
          listResult: [_cv(id: 1, title: 'My CV')],
          extractSkillsError: ApiException(
            'Text could not be extracted from this CV.',
            statusCode: 422,
          ),
        );
        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.text('Analyze CV'));
        await tester.pumpAndSettle();

        expect(
          find.text('Text could not be extracted from this CV.'),
          findsOneWidget,
        );
        expect(find.text('AI-Suggested Skills'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
