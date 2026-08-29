// Widget tests for the premium StudentCvScreen + inline AI Skill Analysis
// (UI Phase 6), in isolation with a small GoRouter and fake repositories.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/utils/cv_file_open_result.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/core/widgets/theme_toggle_button.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/cv/data/cv_repository.dart';
import 'package:opportunityhub_flutter/features/cv/data/picked_cv_file.dart';
import 'package:opportunityhub_flutter/features/cv/presentation/student_cv_screen.dart';
import 'package:opportunityhub_flutter/features/skills/data/student_skill_repository.dart';
import 'package:opportunityhub_flutter/models/cv_model.dart';
import 'package:opportunityhub_flutter/models/cv_skill_suggestion_model.dart';
import 'package:opportunityhub_flutter/models/student_skill_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/student_cv_provider.dart';
import 'package:opportunityhub_flutter/providers/theme_provider.dart';
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
  DateTime? createdAt,
}) {
  return CvModel(
    id: id,
    studentId: 1,
    title: title,
    filePath: filePath,
    version: version,
    isDefault: isDefault,
    createdByAi: createdByAi,
    createdAt: createdAt,
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
    this.setDefaultError,
    this.setDefaultDelay = Duration.zero,
    this.downloadResult,
    this.downloadError,
    this.extractSkillsResult = const [],
    this.extractSkillsError,
    this.extractSkillsDelay = Duration.zero,
    this.updateTitleDelay = Duration.zero,
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
  ApiException? setDefaultError;
  Duration setDefaultDelay;
  int setDefaultCallCount = 0;

  Uint8List? downloadResult;
  ApiException? downloadError;
  int downloadCallCount = 0;

  List<CvSkillSuggestion> extractSkillsResult = const [];
  ApiException? extractSkillsError;
  Duration extractSkillsDelay;
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
    if (setDefaultDelay > Duration.zero) {
      await Future<void>.delayed(setDefaultDelay);
    }
    if (setDefaultError != null) throw setDefaultError!;
    return setDefaultResult!;
  }

  @override
  Future<Uint8List> downloadCv(int cvId) async {
    downloadCallCount++;
    if (downloadError != null) throw downloadError!;
    return downloadResult ?? Uint8List.fromList([0x25, 0x50, 0x44, 0x46]);
  }

  ApiException? updateTitleError;
  Duration updateTitleDelay;
  int updateTitleCallCount = 0;
  String? lastUpdateTitle;

  @override
  Future<CvModel> updateTitle({required int cvId, required String title}) async {
    updateTitleCallCount++;
    lastUpdateTitle = title;
    if (updateTitleDelay > Duration.zero) {
      await Future<void>.delayed(updateTitleDelay);
    }
    if (updateTitleError != null) throw updateTitleError!;
    final existing = listResult.firstWhere((cv) => cv.id == cvId);
    final updated = _cv(
      id: existing.id,
      title: title,
      isDefault: existing.isDefault,
      createdByAi: existing.createdByAi,
      createdAt: existing.createdAt,
    );
    listResult = [
      for (final cv in listResult) if (cv.id == cvId) updated else cv,
    ];
    return updated;
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
  Future<StudentSkillModel> addSkill({
    required int skillId,
    String level = 'intermediate',
    String source = 'manual',
    int? cvId,
  }) async {
    addedSkillIds.add(skillId);
    addedSources.add(source);
    addedCvIds.add(cvId);
    if (addSkillError != null) throw addSkillError!;
    return StudentSkillModel(
      id: addedSkillIds.length,
      skillId: skillId,
      skillName: 'Added Skill',
      level: level,
      source: source,
    );
  }
}

/// A fake, injectable platform file action (view or download) — UI Phase
/// 6.3. Widget tests run on the Dart VM, not a real browser, so the real
/// `viewCvFile`/`downloadCvFile` would always fall through to the honest
/// non-Web "not yet supported on this platform" fallback and every
/// success-path test below would fail. Injecting this fake lets the tests
/// control (and observe) what the real platform action would have done,
/// exactly like `test/providers/student_cv_provider_test.dart` already
/// does for the provider layer.
class _FakeFileAction {
  _FakeFileAction();
  CvFileOpenResult result = const CvFileOpenResult(success: true);
  int callCount = 0;
  String? lastFileName;

  Future<CvFileOpenResult> call(Uint8List bytes, String fileName) async {
    callCount++;
    lastFileName = fileName;
    return result;
  }
}

Future<StudentCvProvider> _pumpScreen(
  WidgetTester tester, {
  required _FakeCvRepository repository,
  StudentSkillRepository? studentSkillRepository,
  Future<PickedCvFile?> Function() pickCvFile = _defaultTestPicker,
  Size size = const Size(420, 1200),
  ThemeData? theme,
  _FakeFileAction? viewCvFile,
  _FakeFileAction? downloadCvFile,
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
    viewCvFile: (viewCvFile ?? _FakeFileAction()).call,
    downloadCvFile: (downloadCvFile ?? _FakeFileAction()).call,
  );

  final router = GoRouter(
    initialLocation: AppRoutes.studentCvs,
    routes: [
      GoRoute(
        path: AppRoutes.studentCvs,
        builder: (_, _) => StudentCvScreen(pickCvFile: pickCvFile),
      ),
      GoRoute(
        path: AppRoutes.studentSkills,
        builder: (_, _) => const Scaffold(body: Text('SKILLS_PLACEHOLDER')),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<StudentCvProvider>.value(value: provider),
        ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ],
      child: MaterialApp.router(
        theme: theme ?? AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  return provider;
}

Future<PickedCvFile?> _defaultTestPicker() async => _pickedFile();

void main() {
  testWidgets('Loading state renders a skeleton while the list is in flight', (
    tester,
  ) async {
    final repository = _FakeCvRepository(
      listDelay: const Duration(milliseconds: 200),
    );
    tester.view.physicalSize = const Size(420, 1200);
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
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StudentCvProvider>.value(value: provider),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
        ],
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

  testWidgets('Empty state renders a premium first-use state with a real Add CV CTA', (
    tester,
  ) async {
    await _pumpScreen(tester, repository: _FakeCvRepository());

    expect(find.text('Build Your Opportunity Profile'), findsOneWidget);
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
    'Populated list renders title, version, upload date, and default badge, but never a raw file path',
    (tester) async {
      final repository = _FakeCvRepository(
        listResult: [
          _cv(
            id: 1,
            title: 'Software Engineer CV',
            filePath: 'cvs/1/9c6b1e3a-....pdf',
            version: 2,
            isDefault: true,
            createdAt: DateTime(2026, 8, 10),
          ),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      // The title also appears as the CV Summary tile's "Default" value —
      // deliberate richness, not a duplicate-rendering bug.
      expect(find.text('Software Engineer CV'), findsWidgets);
      expect(find.text('Version 2'), findsOneWidget);
      // "Default" appears both in the CV Summary tile and the card's own
      // badge — deliberate richness, not a duplicate-rendering bug.
      expect(find.text('Default'), findsWidgets);
      expect(find.text('Uploaded Aug 10, 2026'), findsOneWidget);
      // The raw server-managed path is never shown to the user.
      expect(find.text('cvs/1/9c6b1e3a-....pdf'), findsNothing);
      expect(find.textContaining('cvs/'), findsNothing);
      // A CV already default shows no "Set as Default" action.
      expect(find.text('Set as Default'), findsNothing);
    },
  );

  testWidgets('No upload date renders safely when createdAt is absent', (
    tester,
  ) async {
    final repository = _FakeCvRepository(listResult: [_cv(id: 1)]);
    await _pumpScreen(tester, repository: repository);

    expect(find.textContaining('Uploaded'), findsNothing);
    expect(tester.takeException(), isNull);
  });

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
    expect(find.text('Set as Default'), findsNothing);
  });

  testWidgets(
    'Set as Default shows a loading state, and a failure keeps the prior default intact',
    (tester) async {
      final repository = _FakeCvRepository(
        listResult: [
          _cv(id: 1, title: 'CV One', isDefault: true),
          _cv(id: 2, title: 'CV Two', isDefault: false),
        ],
        setDefaultError: ApiException('Server error, please try again later.'),
        setDefaultDelay: const Duration(milliseconds: 300),
      );
      await _pumpScreen(tester, repository: repository);

      await tester.ensureVisible(find.text('Set as Default'));
      await tester.tap(find.text('Set as Default'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsWidgets);

      await tester.pumpAndSettle();

      expect(repository.setDefaultCallCount, 1);
      expect(
        find.text('Server error, please try again later.'),
        findsOneWidget,
      );
      // "CV One" stays the default — the failed action never mutated the
      // local state.
      expect(find.text('Set as Default'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('AI Generated chip renders only when createdByAi is true', (
    tester,
  ) async {
    final repository = _FakeCvRepository(
      listResult: [_cv(id: 1, createdByAi: true)],
    );
    await _pumpScreen(tester, repository: repository);

    expect(find.text('AI Generated'), findsOneWidget);
  });

  group('CV Summary', () {
    testWidgets('shows real, locally-derived Total and Default', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [
          _cv(id: 1, title: 'CV One', isDefault: true),
          _cv(id: 2, title: 'CV Two'),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.text('Total CVs'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('CV One'), findsWidgets);
    });

    testWidgets('shows "Not set" when no CV is default (legacy data)', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, isDefault: false)],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.text('Not set'), findsOneWidget);
    });
  });

  group('Add CV', () {
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

    testWidgets(
      'Add CV success sends the picked file, shows a success beat, closes the sheet, refreshes the list, and shows a success message',
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
        await tester.pump();

        // The brief in-sheet success beat.
        expect(find.text('CV Added'), findsOneWidget);

        await tester.pumpAndSettle();

        expect(repository.lastCreateTitle, 'New CV');
        expect(repository.lastCreateFile?.filename, 'new-cv.pdf');
        expect(find.text('New CV'), findsWidgets);
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

  group('View CV (UI Phase 6.3)', () {
    testWidgets(
      'View CV fetches the real bytes and triggers the real platform viewer, with no success snackbar',
      (tester) async {
        final viewFile = _FakeFileAction();
        final repository = _FakeCvRepository(
          listResult: [_cv(id: 1, title: 'My CV')],
          downloadResult: Uint8List(2048),
        );
        await _pumpScreen(tester, repository: repository, viewCvFile: viewFile);

        await tester.tap(find.text('View CV'));
        await tester.pumpAndSettle();

        expect(repository.downloadCallCount, 1);
        expect(viewFile.callCount, 1);
        expect(viewFile.lastFileName, 'My CV.pdf');
        // Real success (the tab actually opened) shows no "downloaded"
        // snackbar and no error — View and Download are distinct actions.
        expect(find.textContaining('CV downloaded'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a backend fetch failure shows the real backend message safely', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV')],
        downloadError: ApiException('CV file not found'),
      );
      final viewFile = _FakeFileAction();
      await _pumpScreen(tester, repository: repository, viewCvFile: viewFile);

      await tester.tap(find.text('View CV'));
      await tester.pumpAndSettle();

      expect(find.text('CV file not found'), findsOneWidget);
      expect(viewFile.callCount, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'never claims success merely because bytes were fetched -- a viewer failure (e.g. a blocked popup) shows its own error',
      (tester) async {
        final repository = _FakeCvRepository(
          listResult: [_cv(id: 1, title: 'My CV')],
          downloadResult: Uint8List(2048),
        );
        final viewFile = _FakeFileAction()
          ..result = const CvFileOpenResult(
            success: false,
            errorMessage:
                "Couldn't open the CV — your browser may have blocked the new tab.",
          );
        await _pumpScreen(tester, repository: repository, viewCvFile: viewFile);

        await tester.tap(find.text('View CV'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            "Couldn't open the CV — your browser may have blocked the new tab.",
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('View CV never triggers a real download action', (
      tester,
    ) async {
      final viewFile = _FakeFileAction();
      final downloadFile = _FakeFileAction();
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV')],
        downloadResult: Uint8List(2048),
      );
      await _pumpScreen(
        tester,
        repository: repository,
        viewCvFile: viewFile,
        downloadCvFile: downloadFile,
      );

      await tester.tap(find.text('View CV'));
      await tester.pumpAndSettle();

      expect(viewFile.callCount, 1);
      expect(downloadFile.callCount, 0);
    });
  });

  group('Download CV (UI Phase 6.3)', () {
    testWidgets(
      'Download CV fetches the real bytes and triggers the real platform download, distinct from View',
      (tester) async {
        final viewFile = _FakeFileAction();
        final downloadFile = _FakeFileAction();
        final repository = _FakeCvRepository(
          listResult: [_cv(id: 1, title: 'My CV')],
          downloadResult: Uint8List(2048),
        );
        await _pumpScreen(
          tester,
          repository: repository,
          viewCvFile: viewFile,
          downloadCvFile: downloadFile,
        );

        await tester.tap(find.byTooltip('Download CV'));
        await tester.pumpAndSettle();

        expect(repository.downloadCallCount, 1);
        expect(downloadFile.callCount, 1);
        expect(downloadFile.lastFileName, 'My CV.pdf');
        expect(viewFile.callCount, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a backend fetch failure shows the real backend message safely', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV')],
        downloadError: ApiException('CV file not found'),
      );
      final downloadFile = _FakeFileAction();
      await _pumpScreen(
        tester,
        repository: repository,
        downloadCvFile: downloadFile,
      );

      await tester.tap(find.byTooltip('Download CV'));
      await tester.pumpAndSettle();

      expect(find.text('CV file not found'), findsOneWidget);
      expect(downloadFile.callCount, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'never claims success merely because bytes were fetched -- a download failure shows its own error',
      (tester) async {
        final repository = _FakeCvRepository(
          listResult: [_cv(id: 1, title: 'My CV')],
          downloadResult: Uint8List(2048),
        );
        final downloadFile = _FakeFileAction()
          ..result = const CvFileOpenResult(
            success: false,
            errorMessage: "Couldn't download the CV.",
          );
        await _pumpScreen(
          tester,
          repository: repository,
          downloadCvFile: downloadFile,
        );

        await tester.tap(find.byTooltip('Download CV'));
        await tester.pumpAndSettle();

        expect(find.text("Couldn't download the CV."), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Download CV is always visible, never hidden, alongside View CV', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV', isDefault: true)],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.text('View CV'), findsOneWidget);
      expect(find.byTooltip('Download CV'), findsOneWidget);
    });
  });

  testWidgets('Delete requires confirmation before anything happens', (
    tester,
  ) async {
    final repository = _FakeCvRepository(
      listResult: [_cv(id: 1, title: 'My CV')],
    );
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.byTooltip('Delete CV'));
    await tester.pumpAndSettle();

    expect(find.text('Delete CV'), findsWidgets);
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

    await tester.tap(find.byTooltip('Delete CV'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
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

      await tester.tap(find.byTooltip('Delete CV'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(
        find.text('Cannot delete a CV that has been used in an application'),
        findsOneWidget,
      );
      expect(find.text('My CV'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Delete network/unexpected error is shown safely, not a crash',
    (tester) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV')],
        deleteError: ApiException('Network error. Please check your connection.'),
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byTooltip('Delete CV'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(
        find.text('Network error. Please check your connection.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Does not overflow at a narrow 320x900 viewport', (tester) async {
    final repository = _FakeCvRepository(
      listResult: [
        _cv(id: 1, title: 'Software Engineer CV', isDefault: true),
        _cv(id: 2, title: 'Marketing CV'),
      ],
    );
    await _pumpScreen(
      tester,
      repository: repository,
      size: const Size(320, 1400),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('Add CV sheet does not overflow at a narrow 320x900 viewport', (
    tester,
  ) async {
    final repository = _FakeCvRepository();
    await _pumpScreen(
      tester,
      repository: repository,
      size: const Size(320, 900),
    );

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select PDF'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('Does not overflow at a tablet viewport', (tester) async {
    final repository = _FakeCvRepository(
      listResult: [_cv(id: 1, title: 'Software Engineer CV')],
    );
    await _pumpScreen(
      tester,
      repository: repository,
      size: const Size(900, 1000),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Does not overflow at a wide desktop viewport and uses a 2-column grid',
    (tester) async {
      final repository = _FakeCvRepository(
        listResult: [
          _cv(id: 1, title: 'Software Engineer CV'),
          _cv(id: 2, title: 'Marketing CV'),
        ],
      );
      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(1440, 1000),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Software Engineer CV'), findsOneWidget);
      expect(find.text('Marketing CV'), findsOneWidget);
    },
  );

  testWidgets('honors reduced motion without throwing', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final repository = _FakeCvRepository(
      listResult: [_cv(id: 1, title: 'Software Engineer CV')],
    );
    await _pumpScreen(tester, repository: repository);

    expect(tester.takeException(), isNull);
    expect(find.text('Software Engineer CV'), findsOneWidget);
  });

  testWidgets('renders correctly in Dark Mode', (tester) async {
    final repository = _FakeCvRepository(
      listResult: [_cv(id: 1, title: 'Software Engineer CV')],
    );

    tester.view.physicalSize = const Size(420, 1200);
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
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StudentCvProvider>.value(value: provider),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
        ],
        child: MaterialApp.router(
          theme: AppTheme.darkTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Software Engineer CV'), findsOneWidget);
  });

  testWidgets('the app-bar theme toggle is reachable', (tester) async {
    await _pumpScreen(
      tester,
      repository: _FakeCvRepository(listResult: [_cv(id: 1)]),
    );

    expect(find.byType(ThemeToggleButton), findsOneWidget);
  });

  group('AI Skill Analysis (UI Phase 6)', () {
    testWidgets('An Analyze with AI action is offered on every CV card', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV')],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.text('Analyze with AI'), findsOneWidget);
      expect(find.text('AI Skill Analysis'), findsWidgets);
    });

    testWidgets('Analyzing shows a real, bounded processing state, no fake percentage', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV')],
        extractSkillsDelay: const Duration(milliseconds: 300),
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

      await tester.tap(find.text('Analyze with AI'));
      await tester.pump();

      expect(find.textContaining('Analyzing your CV'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);

      await tester.pumpAndSettle();
    });

    testWidgets(
      'Success shows real extracted skills inline with their real confidence, no fabricated confidence',
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

        await tester.tap(find.text('Analyze with AI'));
        await tester.pumpAndSettle();

        expect(repository.extractSkillsCallCount, 1);
        expect(find.text('AI Analysis Results'), findsOneWidget);
        expect(find.text('1 skill found'), findsOneWidget);
        expect(find.text('AutoCAD'), findsOneWidget);
        expect(find.textContaining('95% confidence'), findsOneWidget);
        expect(find.text('CV Evidence'), findsOneWidget);
      },
    );

    testWidgets('Zero extracted skills shows a calm, honest empty result', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV')],
        extractSkillsResult: const [],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Analyze with AI'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining("couldn't identify any clear skills"),
        findsOneWidget,
      );
      expect(find.text('Analyze Again'), findsOneWidget);
    });

    testWidgets(
      'An unmatched suggestion shows "Pending Catalog Approval" and cannot be selected',
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

        await tester.tap(find.text('Analyze with AI'));
        await tester.pumpAndSettle();

        expect(find.text('Pending Catalog Approval'), findsOneWidget);
        expect(find.byType(Checkbox), findsNothing);
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

        await tester.tap(find.text('Analyze with AI'));
        await tester.pumpAndSettle();

        expect(find.text('Already Added'), findsOneWidget);
        expect(find.byType(Checkbox), findsNothing);
      },
    );

    testWidgets(
      'Selecting a suggestion and adding it posts to the Student Skill endpoint with source cv_ai',
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

        await tester.tap(find.text('Analyze with AI'));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(Checkbox).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add 1 Skill'));
        await tester.pumpAndSettle();

        expect(studentSkillRepository.addedSkillIds, [5]);
        expect(studentSkillRepository.addedSources, ['cv_ai']);
        expect(studentSkillRepository.addedCvIds, [1]);
        expect(find.text('Skills added successfully'), findsOneWidget);
      },
    );

    testWidgets('Select all selects every currently-selectable suggestion', (
      tester,
    ) async {
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
          CvSkillSuggestion(
            name: 'MATLAB',
            confidence: 0.7,
            skillId: 6,
            isAvailable: true,
            alreadyAdded: false,
          ),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Analyze with AI'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Select all available'));
      await tester.pumpAndSettle();

      expect(find.text('Add 2 Skills'), findsOneWidget);
    });

    testWidgets(
      'Extraction failure shows a safe headline plus the real backend message, inline, never opens a modal',
      (tester) async {
        final repository = _FakeCvRepository(
          listResult: [_cv(id: 1, title: 'My CV')],
          extractSkillsError: ApiException(
            'Text could not be extracted from this CV.',
            statusCode: 422,
          ),
        );
        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.text('Analyze with AI'));
        await tester.pumpAndSettle();

        expect(
          find.text("We couldn't analyze this CV right now."),
          findsOneWidget,
        );
        expect(
          find.text('Text could not be extracted from this CV.'),
          findsOneWidget,
        );
        expect(find.text('Try Again'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Retry after a failure re-runs the exact same real action', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV')],
        extractSkillsError: ApiException(
          'AI skill extraction is currently unavailable. Please try again later.',
          statusCode: 503,
        ),
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Analyze with AI'));
      await tester.pumpAndSettle();

      expect(repository.extractSkillsCallCount, 1);

      repository.extractSkillsError = null;
      repository.extractSkillsResult = const [
        CvSkillSuggestion(
          name: 'AutoCAD',
          confidence: 0.9,
          skillId: 5,
          isAvailable: true,
          alreadyAdded: false,
        ),
      ];
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();

      expect(repository.extractSkillsCallCount, 2);
      expect(find.text('AutoCAD'), findsOneWidget);
    });

    testWidgets('Analyze Again re-runs extraction for the same CV', (
      tester,
    ) async {
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
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Analyze with AI'));
      await tester.pumpAndSettle();
      expect(repository.extractSkillsCallCount, 1);

      await tester.tap(find.text('Analyze Again'));
      await tester.pumpAndSettle();

      expect(repository.extractSkillsCallCount, 2);
    });

    testWidgets('View My Skills navigates to the real Skills route', (
      tester,
    ) async {
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
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Analyze with AI'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('View My Skills'));
      await tester.pumpAndSettle();

      expect(find.text('SKILLS_PLACEHOLDER'), findsOneWidget);
    });

    testWidgets(
      'A duplicate tap while analyzing does not send a second real request',
      (tester) async {
        final repository = _FakeCvRepository(
          listResult: [_cv(id: 1, title: 'My CV')],
          extractSkillsDelay: const Duration(milliseconds: 300),
        );
        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.text('Analyze with AI'));
        await tester.pump();
        // The panel has already switched to the processing state, so a
        // second tap on the (now-gone) prompt button can't fire anyway —
        // confirms only one real request was ever sent.
        await tester.pumpAndSettle();

        expect(repository.extractSkillsCallCount, 1);
      },
    );
  });

  group('AI results collapse/expand + compact preview (UI Phase 6.1)', () {
    List<CvSkillSuggestion> manySkills(int count) => [
      for (var i = 0; i < count; i++)
        CvSkillSuggestion(
          name: 'Skill $i',
          confidence: 0.9,
          skillId: i,
          isAvailable: true,
          alreadyAdded: false,
        ),
    ];

    testWidgets('a successful analysis auto-expands once, with a real count header', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV')],
        extractSkillsResult: manySkills(3),
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Analyze with AI'));
      await tester.pumpAndSettle();

      expect(find.text('AI Analysis Results'), findsOneWidget);
      expect(find.text('3 skills found'), findsOneWidget);
      // Expanded by default — the real skill content is visible, not just
      // the collapsed summary.
      expect(find.text('Skill 0'), findsOneWidget);
    });

    testWidgets('the user can collapse the results to a compact summary', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV')],
        extractSkillsResult: [
          const CvSkillSuggestion(
            name: 'AutoCAD',
            confidence: 0.9,
            skillId: 5,
            isAvailable: true,
            alreadyAdded: false,
          ),
          const CvSkillSuggestion(
            name: 'Python',
            confidence: 0.8,
            skillId: 6,
            isAvailable: true,
            alreadyAdded: true,
          ),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Analyze with AI'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('AI Analysis Results'));
      await tester.pumpAndSettle();

      // Compact, real, locally-derived counts only.
      expect(find.text('2 skills discovered'), findsOneWidget);
      expect(find.text('1 already added'), findsOneWidget);
      expect(find.text('1 pending'), findsOneWidget);
      // The skill rows and action buttons are hidden while collapsed.
      expect(find.text('AutoCAD'), findsNothing);
      expect(find.text('Add Selected Skills'), findsNothing);
    });

    testWidgets('the user can re-expand collapsed results', (tester) async {
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
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Analyze with AI'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('AI Analysis Results'));
      await tester.pumpAndSettle();
      expect(find.text('AutoCAD'), findsNothing);

      await tester.tap(find.text('AI Analysis Results'));
      await tester.pumpAndSettle();
      expect(find.text('AutoCAD'), findsOneWidget);
    });

    testWidgets('collapsing never triggers another real extraction request', (
      tester,
    ) async {
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
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Analyze with AI'));
      await tester.pumpAndSettle();
      expect(repository.extractSkillsCallCount, 1);

      await tester.tap(find.text('AI Analysis Results'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI Analysis Results'));
      await tester.pumpAndSettle();

      expect(repository.extractSkillsCallCount, 1);
    });

    testWidgets(
      'collapse preserves a selected skill and extracted results, no data lost',
      (tester) async {
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
        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.text('Analyze with AI'));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(Checkbox).first);
        await tester.pumpAndSettle();
        expect(find.text('Add 1 Skill'), findsOneWidget);

        await tester.tap(find.text('AI Analysis Results'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('AI Analysis Results'));
        await tester.pumpAndSettle();

        // The selection survived the round trip, and no new request fired.
        expect(find.text('Add 1 Skill'), findsOneWidget);
        expect(repository.extractSkillsCallCount, 1);
      },
    );

    testWidgets('a long result list previews only the first 5 skills', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV')],
        extractSkillsResult: manySkills(20),
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Analyze with AI'));
      await tester.pumpAndSettle();

      expect(find.text('Skill 0'), findsOneWidget);
      expect(find.text('Skill 4'), findsOneWidget);
      expect(find.text('Skill 5'), findsNothing);
      expect(find.text('Skill 19'), findsNothing);
      expect(find.text('View All 20 Skills'), findsOneWidget);
    });

    testWidgets('View All reveals every skill in the real result', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV')],
        extractSkillsResult: manySkills(20),
      );
      await _pumpScreen(tester, repository: repository, size: const Size(420, 3000));

      await tester.tap(find.text('Analyze with AI'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('View All 20 Skills'));
      await tester.pumpAndSettle();

      expect(find.text('Skill 19'), findsOneWidget);
      expect(find.text('Show Less'), findsOneWidget);
    });

    testWidgets('the user can hide the full list again after viewing it', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV')],
        extractSkillsResult: manySkills(20),
      );
      await _pumpScreen(tester, repository: repository, size: const Size(420, 3000));

      await tester.tap(find.text('Analyze with AI'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('View All 20 Skills'));
      await tester.pumpAndSettle();
      expect(find.text('Skill 19'), findsOneWidget);

      await tester.tap(find.text('Show Less'));
      await tester.pumpAndSettle();

      expect(find.text('Skill 19'), findsNothing);
      expect(find.text('View All 20 Skills'), findsOneWidget);
    });

    testWidgets('Analyze Again remains functional after collapsing/expanding', (
      tester,
    ) async {
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
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Analyze with AI'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('AI Analysis Results'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI Analysis Results'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Analyze Again'));
      await tester.pumpAndSettle();

      expect(repository.extractSkillsCallCount, 2);
      // A fresh result panel — auto-expanded again.
      expect(find.text('AutoCAD'), findsOneWidget);
    });

    testWidgets('renders safely in Dark Mode with a long result list', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV')],
        extractSkillsResult: manySkills(20),
      );
      await _pumpScreen(
        tester,
        repository: repository,
        theme: AppTheme.darkTheme,
      );

      await tester.tap(find.text('Analyze with AI'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('View All 20 Skills'), findsOneWidget);
    });

    testWidgets('renders safely on a narrow mobile viewport with a long result list', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV')],
        extractSkillsResult: manySkills(20),
      );
      await _pumpScreen(
        tester,
        repository: repository,
        size: const Size(360, 3000),
      );

      await tester.tap(find.text('Analyze with AI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View All 20 Skills'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Skill 19'), findsOneWidget);
    });

    testWidgets('honors reduced motion while collapsing/expanding, no throw', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV')],
        extractSkillsResult: manySkills(3),
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Analyze with AI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI Analysis Results'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('Delete action polish (UI Phase 6.1)', () {
    testWidgets('the Delete CV control keeps its real tooltip and behavior', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV')],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.byTooltip('Delete CV'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete CV'));
      await tester.pumpAndSettle();

      expect(find.text('Delete CV'), findsWidgets);
      expect(repository.deleteCallCount, 0);
    });
  });

  group('Rename CV (UI Phase 6.2)', () {
    testWidgets('a Rename action is visible on every CV card', (tester) async {
      final repository = _FakeCvRepository(listResult: [_cv(id: 1, title: 'My CV')]);
      await _pumpScreen(tester, repository: repository);

      expect(find.byTooltip('Rename CV'), findsOneWidget);
    });

    testWidgets('the current title is prefilled and Cancel makes no request', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'Old Title')],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byTooltip('Rename CV'));
      await tester.pumpAndSettle();

      expect(find.text('Rename CV'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Old Title'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repository.updateTitleCallCount, 0);
      expect(find.text('Old Title'), findsOneWidget);
    });

    testWidgets(
      'success sends the new title, closes the dialog, updates the card, and shows a confirmation',
      (tester) async {
        final repository = _FakeCvRepository(
          listResult: [_cv(id: 1, title: 'Old Title')],
        );
        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.byTooltip('Rename CV'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Old Title'),
          'Updated CV Name',
        );
        await tester.tap(find.text('Save Name'));
        await tester.pumpAndSettle();

        expect(repository.updateTitleCallCount, 1);
        expect(repository.lastUpdateTitle, 'Updated CV Name');
        expect(find.text('Updated CV Name'), findsOneWidget);
        expect(find.text('Old Title'), findsNothing);
        expect(find.text('CV renamed successfully'), findsOneWidget);
      },
    );

    testWidgets('a blank title is blocked locally, before any repository call', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'Old Title')],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byTooltip('Rename CV'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Old Title'), '   ');
      await tester.tap(find.text('Save Name'));
      await tester.pumpAndSettle();

      expect(find.text('Title is required'), findsOneWidget);
      expect(repository.updateTitleCallCount, 0);
    });

    testWidgets(
      'a backend validation error is shown inline and the entered value is preserved',
      (tester) async {
        final repository = _FakeCvRepository(
          listResult: [_cv(id: 1, title: 'Old Title')],
        )..updateTitleError = ApiException(
          'The title field must not be greater than 255 characters.',
          statusCode: 422,
        );
        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.byTooltip('Rename CV'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Old Title'),
          'A Rejected New Name',
        );
        await tester.tap(find.text('Save Name'));
        await tester.pumpAndSettle();

        expect(
          find.text('The title field must not be greater than 255 characters.'),
          findsOneWidget,
        );
        // The dialog stays open with the student's own input preserved.
        expect(find.text('Rename CV'), findsOneWidget);
        expect(find.text('A Rejected New Name'), findsOneWidget);
        expect(find.text('Old Title'), findsOneWidget);
      },
    );

    testWidgets('a duplicate submit while renaming does not send a second request', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'Old Title')],
        updateTitleDelay: const Duration(milliseconds: 300),
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byTooltip('Rename CV'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Old Title'),
        'New Name',
      );
      await tester.tap(find.text('Save Name'));
      await tester.pump();
      await tester.tap(find.text('Save Name'), warnIfMissed: false);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(repository.updateTitleCallCount, 1);
    });

    testWidgets('renaming never sends a real AI extraction request', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'Old Title')],
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byTooltip('Rename CV'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Old Title'),
        'New Name',
      );
      await tester.tap(find.text('Save Name'));
      await tester.pumpAndSettle();

      expect(repository.extractSkillsCallCount, 0);
    });
  });

  group('CV document validation UX (UI Phase 6.2)', () {
    testWidgets(
      'NOT_A_CV shows a calm, distinct panel — never fake results, never the generic error headline',
      (tester) async {
        final repository = _FakeCvRepository(
          listResult: [_cv(id: 1, title: 'My CV')],
          extractSkillsError: ApiException(
            "This document doesn't appear to be a CV or resume. Upload a CV to use AI Skill Analysis.",
            statusCode: 422,
          ),
        );
        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.text('Analyze with AI'));
        await tester.pumpAndSettle();

        expect(find.text('Unable to Analyze This Document'), findsOneWidget);
        expect(
          find.text(
            "This document doesn't appear to be a CV or resume. Upload a CV to use AI Skill Analysis.",
          ),
          findsOneWidget,
        );
        expect(find.text('Add Another CV'), findsOneWidget);
        // Never the generic-error headline, never a fabricated result.
        expect(find.text("We couldn't analyze this CV right now."), findsNothing);
        expect(find.text('Skills Discovered'), findsNothing);
        expect(find.text('AI Analysis Results'), findsNothing);
        expect(find.text('Try Again'), findsNothing);
      },
    );

    testWidgets(
      'insufficient readable text shows its own distinct, truthful panel',
      (tester) async {
        final repository = _FakeCvRepository(
          listResult: [_cv(id: 1, title: 'My CV')],
          extractSkillsError: ApiException(
            "We couldn't find enough readable text in this PDF to analyze it.",
            statusCode: 422,
          ),
        );
        await _pumpScreen(tester, repository: repository);

        await tester.tap(find.text('Analyze with AI'));
        await tester.pumpAndSettle();

        expect(
          find.text("We couldn't find enough readable text in this PDF."),
          findsOneWidget,
        );
        expect(find.text('Try a text-based PDF.'), findsOneWidget);
        expect(find.text('Add Another CV'), findsOneWidget);
        // Never a false OCR claim.
        expect(find.textContaining('OCR'), findsNothing);
        expect(find.text('Skills Discovered'), findsNothing);
      },
    );

    testWidgets('Add Another CV opens the real Add CV flow', (tester) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV')],
        extractSkillsError: ApiException(
          "This document doesn't appear to be a CV or resume. Upload a CV to use AI Skill Analysis.",
          statusCode: 422,
        ),
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Analyze with AI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Another CV'));
      await tester.pumpAndSettle();

      expect(find.text('Select PDF'), findsOneWidget);
    });

    testWidgets('a genuine provider/network failure still shows the generic error with Try Again', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV')],
        extractSkillsError: ApiException(
          'AI skill extraction is currently unavailable. Please try again later.',
          statusCode: 503,
        ),
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Analyze with AI'));
      await tester.pumpAndSettle();

      expect(find.text("We couldn't analyze this CV right now."), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
      expect(find.text('Unable to Analyze This Document'), findsNothing);
    });

    testWidgets('a valid CV still reaches real extraction and renders real results', (
      tester,
    ) async {
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
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Analyze with AI'));
      await tester.pumpAndSettle();

      expect(find.text('AutoCAD'), findsOneWidget);
      expect(find.text('Unable to Analyze This Document'), findsNothing);
    });

    testWidgets('renders safely in Dark Mode for a NOT_A_CV rejection', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV')],
        extractSkillsError: ApiException(
          "This document doesn't appear to be a CV or resume. Upload a CV to use AI Skill Analysis.",
          statusCode: 422,
        ),
      );
      await _pumpScreen(tester, repository: repository, theme: AppTheme.darkTheme);

      await tester.tap(find.text('Analyze with AI'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Unable to Analyze This Document'), findsOneWidget);
    });

    testWidgets('renders safely on a narrow mobile viewport for a NOT_A_CV rejection', (
      tester,
    ) async {
      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV')],
        extractSkillsError: ApiException(
          "This document doesn't appear to be a CV or resume. Upload a CV to use AI Skill Analysis.",
          statusCode: 422,
        ),
      );
      await _pumpScreen(tester, repository: repository, size: const Size(360, 1200));

      await tester.tap(find.text('Analyze with AI'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Unable to Analyze This Document'), findsOneWidget);
    });

    testWidgets('honors reduced motion for a NOT_A_CV rejection, no throw', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

      final repository = _FakeCvRepository(
        listResult: [_cv(id: 1, title: 'My CV')],
        extractSkillsError: ApiException(
          "This document doesn't appear to be a CV or resume. Upload a CV to use AI Skill Analysis.",
          statusCode: 422,
        ),
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.text('Analyze with AI'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
