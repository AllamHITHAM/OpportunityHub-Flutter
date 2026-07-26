// Widget tests for StudentCvScreen, in isolation with a small GoRouter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/features/cv/data/cv_repository.dart';
import 'package:opportunityhub_flutter/features/cv/presentation/student_cv_screen.dart';
import 'package:opportunityhub_flutter/models/cv_model.dart';
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
  String filePath = 'cvs/my-cv.pdf',
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

class _FakeCvRepository extends CvRepository {
  _FakeCvRepository({
    this.listResult = const [],
    this.listError,
    this.listDelay = Duration.zero,
    this.createResult,
    this.createError,
    this.deleteError,
    this.setDefaultResult,
  }) : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  List<CvModel> listResult;
  ApiException? listError;
  Duration listDelay;
  int getStudentCvsCallCount = 0;

  CvModel? createResult;
  ApiException? createError;
  Map<String, String>? lastCreatePayload;

  ApiException? deleteError;
  int deleteCallCount = 0;

  CvModel? setDefaultResult;
  int setDefaultCallCount = 0;

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
    required String filePath,
  }) async {
    lastCreatePayload = {'title': title, 'file_path': filePath};
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
}

Future<StudentCvProvider> _pumpScreen(
  WidgetTester tester, {
  required _FakeCvRepository repository,
  Size size = const Size(420, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final provider = StudentCvProvider(
    repository: repository,
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
  await tester.pumpAndSettle();

  return provider;
}

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
    'Populated list renders title, file path, version, and default badge',
    (tester) async {
      final repository = _FakeCvRepository(
        listResult: [
          _cv(
            id: 1,
            title: 'Software Engineer CV',
            filePath: 'cvs/software-engineer.pdf',
            version: 2,
            isDefault: true,
          ),
        ],
      );
      await _pumpScreen(tester, repository: repository);

      expect(find.text('Software Engineer CV'), findsOneWidget);
      expect(find.text('cvs/software-engineer.pdf'), findsOneWidget);
      expect(find.text('Version 2'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);
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
      await tester.enterText(
        find.widgetWithText(TextFormField, 'File Path'),
        'cvs/new-cv.pdf',
      );
      await tester.tap(find.text('Add CV').last);
      await tester.pumpAndSettle();

      expect(
        find.text('Title must be 255 characters or fewer'),
        findsOneWidget,
      );
      expect(repository.lastCreatePayload, isNull);
    },
  );

  testWidgets(
    'A file path over 2048 characters is blocked locally, before any repository call',
    (tester) async {
      final repository = _FakeCvRepository();
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'New CV',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'File Path'),
        'a' * 2049,
      );
      await tester.tap(find.text('Add CV').last);
      await tester.pumpAndSettle();

      expect(
        find.text('File path must be 2048 characters or fewer'),
        findsOneWidget,
      );
      expect(repository.lastCreatePayload, isNull);
    },
  );

  testWidgets(
    'A title/file path exactly at the limit is accepted (boundary check)',
    (tester) async {
      final repository = _FakeCvRepository(
        createResult: _cv(id: 5, title: 'A' * 255),
      );
      await _pumpScreen(tester, repository: repository);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'A' * 255,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'File Path'),
        'a' * 2048,
      );
      await tester.tap(find.text('Add CV').last);
      await tester.pumpAndSettle();

      expect(repository.lastCreatePayload, isNotNull);
    },
  );

  testWidgets('Add CV validation blocks submission when fields are blank', (
    tester,
  ) async {
    await _pumpScreen(tester, repository: _FakeCvRepository());

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add CV').last);
    await tester.pumpAndSettle();

    expect(find.text('Title is required'), findsOneWidget);
    expect(find.text('File path is required'), findsOneWidget);
  });

  testWidgets(
    'Add CV success closes the sheet, refreshes the list, and shows a success message',
    (tester) async {
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
      await tester.enterText(
        find.widgetWithText(TextFormField, 'File Path'),
        'cvs/new-cv.pdf',
      );
      await tester.tap(find.text('Add CV').last);
      await tester.pumpAndSettle();

      expect(repository.lastCreatePayload, {
        'title': 'New CV',
        'file_path': 'cvs/new-cv.pdf',
      });
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
      await tester.enterText(
        find.widgetWithText(TextFormField, 'File Path'),
        'cvs/new-cv.pdf',
      );
      await tester.tap(find.text('Add CV').last);
      await tester.pumpAndSettle();

      // The field-specific message is shown in preference to the generic
      // top-level one.
      expect(find.text('The title field is required.'), findsOneWidget);
      expect(find.text('The given data was invalid.'), findsNothing);
      expect(find.text('Add CV'), findsWidgets);
    },
  );

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
}
