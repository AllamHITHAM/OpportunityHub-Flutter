// Widget tests for ScheduleInterviewScreen, in isolation with a small
// GoRouter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/core/theme/app_theme.dart';
import 'package:opportunityhub_flutter/features/applications/data/application_repository.dart';
import 'package:opportunityhub_flutter/features/assessments/data/assessment_repository.dart';
import 'package:opportunityhub_flutter/features/assessments/data/interview_create_input.dart';
import 'package:opportunityhub_flutter/features/assessments/data/quiz_create_input.dart';
import 'package:opportunityhub_flutter/features/assessments/presentation/schedule_interview_screen.dart';
import 'package:opportunityhub_flutter/features/auth/data/auth_repository.dart';
import 'package:opportunityhub_flutter/models/application_model.dart';
import 'package:opportunityhub_flutter/models/assessment_model.dart';
import 'package:opportunityhub_flutter/models/cv_model.dart';
import 'package:opportunityhub_flutter/models/interview_model.dart';
import 'package:opportunityhub_flutter/providers/auth_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_applications_provider.dart';
import 'package:opportunityhub_flutter/providers/organization_assessment_provider.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(
        apiClient: ApiClient(tokenStorageService: TokenStorageService()),
        tokenStorageService: TokenStorageService(),
      );

  @override
  Future<String?> getSavedToken() async => null;
}

const _cv = CvModel(
  id: 2,
  studentId: 1,
  title: 'Main CV',
  filePath: 'uploads/cv.pdf',
  version: 1,
  isDefault: false,
  createdByAi: false,
);

ApplicationModel _application({
  int id = 5,
  String status = 'interview_scheduled',
}) {
  return ApplicationModel(
    id: id,
    studentId: 1,
    opportunityId: 1,
    cvId: 2,
    status: status,
    cv: _cv,
  );
}

AssessmentModel _assessment({
  int id = 1,
  int applicationId = 5,
  ApplicationModel? application,
}) {
  return AssessmentModel(
    id: id,
    applicationId: applicationId,
    type: 'interview',
    status: 'scheduled',
    application: application ?? _application(id: applicationId),
    interview: InterviewModel(
      id: 1,
      assessmentId: id,
      interviewType: 'online',
      status: 'scheduled',
      decision: 'pending',
    ),
  );
}

class _FakeAssessmentRepository extends AssessmentRepository {
  _FakeAssessmentRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  AssessmentModel? createResult;
  ApiException? createError;
  Duration createDelay = Duration.zero;
  int createCallCount = 0;
  InterviewCreateInput? lastInterviewInput;

  @override
  Future<AssessmentModel?> getAssessmentForApplication(
    int applicationId,
  ) async {
    return null;
  }

  @override
  Future<AssessmentModel> createAssessment({
    required int applicationId,
    required String type,
    InterviewCreateInput? interviewInput,
    QuizCreateInput? quizInput,
  }) async {
    createCallCount++;
    lastInterviewInput = interviewInput;
    if (createDelay > Duration.zero) {
      await Future<void>.delayed(createDelay);
    }
    if (createError != null) throw createError!;
    return createResult!;
  }
}

class _FakeApplicationRepository extends ApplicationRepository {
  _FakeApplicationRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  ApplicationModel? detailsResult;
  int getOrganizationApplicationCallCount = 0;

  @override
  Future<ApplicationModel> getOrganizationApplication(int applicationId) async {
    getOrganizationApplicationCallCount++;
    return detailsResult ?? _application(id: applicationId);
  }
}

class _Providers {
  _Providers({required this.assessment, required this.applications});

  final OrganizationAssessmentProvider assessment;
  final OrganizationApplicationsProvider applications;
}

Future<_Providers> _pumpScreen(
  WidgetTester tester, {
  required AssessmentRepository assessmentRepository,
  int applicationId = 5,
}) async {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final authProvider = AuthProvider(authRepository: _FakeAuthRepository());
  final assessmentProvider = OrganizationAssessmentProvider(
    repository: assessmentRepository,
    authProvider: authProvider,
  );
  final applicationsProvider = OrganizationApplicationsProvider(
    repository: _FakeApplicationRepository(),
    authProvider: authProvider,
  );

  // A lone `initialLocation: '/schedule'` route leaves GoRouter with a
  // single-page stack: the screen's own `Navigator.pop()` on success would
  // pop the last page and crash the delegate. Pushing onto a host route
  // (matching ChooseAssessmentTypeSheet's test setup) gives it somewhere
  // real to pop back to.
  final router = GoRouter(
    initialLocation: '/host',
    routes: [
      GoRoute(
        path: '/host',
        builder: (_, _) => const Scaffold(body: Text('HOST')),
      ),
      GoRoute(
        path: '/schedule',
        builder: (_, _) =>
            ScheduleInterviewScreen(applicationId: applicationId),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<OrganizationAssessmentProvider>.value(
          value: assessmentProvider,
        ),
        ChangeNotifierProvider<OrganizationApplicationsProvider>.value(
          value: applicationsProvider,
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  router.push('/schedule');
  await tester.pumpAndSettle();

  return _Providers(
    assessment: assessmentProvider,
    applications: applicationsProvider,
  );
}

/// Picks today's date (accepting the picker's `initialDate` default via
/// OK) and a fixed, always-in-the-future time (23:59, via the time
/// picker's input entry mode) — reliable regardless of the wall-clock time
/// the test happens to run at.
Future<void> _pickValidDateAndTime(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('scheduledDateField')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('scheduledTimeField')));
  await tester.pumpAndSettle();
  // Scoped to the picker's Dialog: the form behind it stays mounted, so an
  // unscoped `find.byType(TextField)` also matches the form's own text
  // fields (Meeting Link, Notes, etc.) at lower indices than Hour/Minute.
  final timeFields = find.descendant(
    of: find.byType(Dialog),
    matching: find.byType(TextField),
  );
  await tester.enterText(timeFields.at(0), '11');
  await tester.enterText(timeFields.at(1), '59');
  await tester.pumpAndSettle();
  final pm = find.text('PM');
  if (pm.evaluate().isNotEmpty) {
    await tester.tap(pm.first);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('all fields render', (tester) async {
    await _pumpScreen(
      tester,
      assessmentRepository: _FakeAssessmentRepository(),
    );

    expect(find.text('Interview Type'), findsOneWidget);
    expect(find.text('Scheduled Date'), findsOneWidget);
    expect(find.text('Scheduled Time'), findsOneWidget);
    expect(find.text('Duration Minutes'), findsOneWidget);
    expect(find.text('Meeting Link'), findsOneWidget); // default type is online
    expect(find.text('Interviewer Name (optional)'), findsOneWidget);
    expect(find.text('Interviewer Email (optional)'), findsOneWidget);
    expect(find.text('Notes (optional)'), findsOneWidget);
  });

  testWidgets('duration minutes defaults to 60', (tester) async {
    await _pumpScreen(
      tester,
      assessmentRepository: _FakeAssessmentRepository(),
    );

    expect(find.text('60'), findsOneWidget);
  });

  testWidgets('online shows Meeting Link and hides Location', (tester) async {
    await _pumpScreen(
      tester,
      assessmentRepository: _FakeAssessmentRepository(),
    );

    expect(find.text('Meeting Link'), findsOneWidget);
    expect(find.text('Location'), findsNothing);
  });

  testWidgets('onsite shows Location and hides Meeting Link', (tester) async {
    await _pumpScreen(
      tester,
      assessmentRepository: _FakeAssessmentRepository(),
    );

    await tester.tap(find.text('Interview Type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Onsite').last);
    await tester.pumpAndSettle();

    expect(find.text('Location'), findsOneWidget);
    expect(find.text('Meeting Link'), findsNothing);
  });

  testWidgets('phone hides both Meeting Link and Location, shows Contact Phone Number', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      assessmentRepository: _FakeAssessmentRepository(),
    );

    await tester.tap(find.text('Interview Type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Phone').last);
    await tester.pumpAndSettle();

    expect(find.text('Meeting Link'), findsNothing);
    expect(find.text('Location'), findsNothing);
    expect(find.text('Contact Phone Number'), findsOneWidget);
  });

  testWidgets('online and onsite hide Contact Phone Number', (tester) async {
    await _pumpScreen(
      tester,
      assessmentRepository: _FakeAssessmentRepository(),
    );

    expect(find.text('Contact Phone Number'), findsNothing); // default: online

    await tester.tap(find.text('Interview Type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Onsite').last);
    await tester.pumpAndSettle();

    expect(find.text('Contact Phone Number'), findsNothing);
  });

  testWidgets(
    'switching from phone to online clears the entered contact phone from the submitted payload',
    (tester) async {
      final repository = _FakeAssessmentRepository()
        ..createResult = _assessment();
      await _pumpScreen(tester, assessmentRepository: repository);

      await tester.tap(find.text('Interview Type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Phone').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Contact Phone Number'),
        '+1 555-0100',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Interview Type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Online').last);
      await tester.pumpAndSettle();

      expect(find.text('Contact Phone Number'), findsNothing);

      await _pickValidDateAndTime(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Meeting Link'),
        'https://meet.example.com/room',
      );
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Schedule Interview'),
      );
      await tester.pumpAndSettle();

      final sentInput = repository.lastInterviewInput!;
      expect(sentInput.interviewType, 'online');
      expect(sentInput.meetingLink, 'https://meet.example.com/room');
      expect(sentInput.contactPhone, isNull);
    },
  );

  testWidgets('online without a meeting link is rejected', (tester) async {
    await _pumpScreen(
      tester,
      assessmentRepository: _FakeAssessmentRepository(),
    );

    await _pickValidDateAndTime(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Schedule Interview'));
    await tester.pumpAndSettle();

    expect(
      find.text('Meeting link is required for online interviews'),
      findsOneWidget,
    );
  });

  testWidgets('onsite without a location is rejected', (tester) async {
    await _pumpScreen(
      tester,
      assessmentRepository: _FakeAssessmentRepository(),
    );

    await tester.tap(find.text('Interview Type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Onsite').last);
    await tester.pumpAndSettle();

    await _pickValidDateAndTime(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Schedule Interview'));
    await tester.pumpAndSettle();

    expect(
      find.text('Location is required for onsite interviews'),
      findsOneWidget,
    );
  });

  testWidgets('phone without a contact phone number is rejected', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      assessmentRepository: _FakeAssessmentRepository(),
    );

    await tester.tap(find.text('Interview Type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Phone').last);
    await tester.pumpAndSettle();

    await _pickValidDateAndTime(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Schedule Interview'));
    await tester.pumpAndSettle();

    expect(
      find.text('Contact phone number is required for phone interviews'),
      findsOneWidget,
    );
  });

  testWidgets('a valid phone submission sends contact_phone and no meeting_link/location', (
    tester,
  ) async {
    final repository = _FakeAssessmentRepository()..createResult = _assessment();
    await _pumpScreen(tester, assessmentRepository: repository);

    await tester.tap(find.text('Interview Type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Phone').last);
    await tester.pumpAndSettle();

    await _pickValidDateAndTime(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Contact Phone Number'),
      '+1 555-0100',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Schedule Interview'));
    await tester.pumpAndSettle();

    final sentInput = repository.lastInterviewInput!;
    expect(sentInput.interviewType, 'phone');
    expect(sentInput.contactPhone, '+1 555-0100');
    expect(sentInput.meetingLink, isNull);
    expect(sentInput.location, isNull);
  });

  testWidgets('missing date is rejected', (tester) async {
    final repository = _FakeAssessmentRepository();
    await _pumpScreen(tester, assessmentRepository: repository);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Meeting Link'),
      'https://meet.example.com/room',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Schedule Interview'));
    await tester.pumpAndSettle();

    expect(find.text('Scheduled date is required'), findsOneWidget);
    expect(repository.createCallCount, 0);
  });

  testWidgets('missing time is rejected', (tester) async {
    final repository = _FakeAssessmentRepository();
    await _pumpScreen(tester, assessmentRepository: repository);

    await tester.tap(find.byKey(const Key('scheduledDateField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Meeting Link'),
      'https://meet.example.com/room',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Schedule Interview'));
    await tester.pumpAndSettle();

    expect(find.text('Scheduled time is required'), findsOneWidget);
    expect(repository.createCallCount, 0);
  });

  testWidgets('a past date/time is rejected client-side', (tester) async {
    final repository = _FakeAssessmentRepository();
    await _pumpScreen(tester, assessmentRepository: repository);

    // Today's date, but midnight (00:00 AM) -- almost certainly earlier
    // than "now" whenever this test actually runs.
    await tester.tap(find.byKey(const Key('scheduledDateField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('scheduledTimeField')));
    await tester.pumpAndSettle();
    final timeFields = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(timeFields.at(0), '12');
    await tester.enterText(timeFields.at(1), '00');
    await tester.pumpAndSettle();
    final am = find.text('AM');
    if (am.evaluate().isNotEmpty) {
      await tester.tap(am.first);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Meeting Link'),
      'https://meet.example.com/room',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Schedule Interview'));
    await tester.pumpAndSettle();

    expect(
      find.text('Scheduled date and time must be in the future'),
      findsOneWidget,
    );
    expect(repository.createCallCount, 0);
  });

  testWidgets('duration below the minimum is rejected', (tester) async {
    final repository = _FakeAssessmentRepository();
    await _pumpScreen(tester, assessmentRepository: repository);

    await _pickValidDateAndTime(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Duration Minutes'),
      '0',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Meeting Link'),
      'https://meet.example.com/room',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Schedule Interview'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a whole number of at least 1'), findsOneWidget);
    expect(repository.createCallCount, 0);
  });

  testWidgets('an invalid interviewer email is rejected', (tester) async {
    final repository = _FakeAssessmentRepository();
    await _pumpScreen(tester, assessmentRepository: repository);

    await _pickValidDateAndTime(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Meeting Link'),
      'https://meet.example.com/room',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Interviewer Email (optional)'),
      'not-an-email',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Schedule Interview'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(repository.createCallCount, 0);
  });

  testWidgets('max length is enforced on Meeting Link and Notes', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      assessmentRepository: _FakeAssessmentRepository(),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Meeting Link'),
      'a' * 2100,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Notes (optional)'),
      'b' * 2100,
    );
    await tester.pump();

    final meetingLinkText = tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Meeting Link'),
        matching: find.byType(EditableText),
      ),
    );
    expect(meetingLinkText.controller.text.length, lessThanOrEqualTo(2048));

    final notesText = tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Notes (optional)'),
        matching: find.byType(EditableText),
      ),
    );
    expect(notesText.controller.text.length, lessThanOrEqualTo(2000));
  });

  testWidgets('submit is loading and disabled while in flight', (tester) async {
    final repository = _FakeAssessmentRepository()
      ..createResult = _assessment()
      ..createDelay = const Duration(milliseconds: 200);
    await _pumpScreen(tester, assessmentRepository: repository);

    await _pickValidDateAndTime(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Meeting Link'),
      'https://meet.example.com/room',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Schedule Interview'));
    await tester.pump();

    final durationField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Duration Minutes'),
    );
    expect(durationField.enabled, isFalse);

    await tester.pumpAndSettle();
  });

  testWidgets('nested backend field errors surface inline', (tester) async {
    final repository = _FakeAssessmentRepository()
      ..createError = ApiException(
        'The given data was invalid.',
        statusCode: 422,
        errors: {
          'interview.meeting_link': [
            'The interview.meeting link field is required.',
          ],
        },
      );
    await _pumpScreen(tester, assessmentRepository: repository);

    await _pickValidDateAndTime(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Meeting Link'),
      'https://meet.example.com/room',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Schedule Interview'));
    await tester.pumpAndSettle();

    expect(
      find.text('The interview.meeting link field is required.'),
      findsOneWidget,
    );
  });

  testWidgets('a business error (duplicate) shows clearly in the form', (
    tester,
  ) async {
    final repository = _FakeAssessmentRepository()
      ..createError = ApiException(
        'An assessment already exists for this application',
        statusCode: 409,
      );
    await _pumpScreen(tester, assessmentRepository: repository);

    await _pickValidDateAndTime(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Meeting Link'),
      'https://meet.example.com/room',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Schedule Interview'));
    await tester.pumpAndSettle();

    expect(
      find.text('An assessment already exists for this application'),
      findsOneWidget,
    );
  });

  testWidgets('unexpected error shows the safe fallback message', (
    tester,
  ) async {
    // Simulate a malformed backend response by throwing a raw TypeError,
    // rather than an ApiException -- the provider's generic `catch (_)`
    // tier is what this test proves reaches the UI.
    final repository = _ThrowingAssessmentRepository();
    await _pumpScreen(tester, assessmentRepository: repository);

    await _pickValidDateAndTime(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Meeting Link'),
      'https://meet.example.com/room',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Schedule Interview'));
    await tester.pumpAndSettle();

    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
    expect(repository.createCallCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'success patches the application, pops, and shows a success SnackBar',
    (tester) async {
      final application = _application(id: 5, status: 'interview_scheduled');
      final repository = _FakeAssessmentRepository()
        ..createResult = _assessment(
          applicationId: 5,
          application: application,
        );

      final providers = await _pumpScreen(
        tester,
        assessmentRepository: repository,
      );

      await _pickValidDateAndTime(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Meeting Link'),
        'https://meet.example.com/room',
      );
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Schedule Interview'),
      );
      await tester.pumpAndSettle();

      // The screen popped -- its own fields are gone.
      expect(find.text('Schedule Interview'), findsNothing);
      expect(find.text('Assessment created successfully'), findsOneWidget);
      expect(
        providers.applications.applications,
        isEmpty,
      ); // never reloaded a list
    },
  );

  testWidgets('no duplicate submission from rapid double taps', (tester) async {
    final repository = _FakeAssessmentRepository()
      ..createResult = _assessment()
      ..createDelay = const Duration(milliseconds: 100);
    await _pumpScreen(tester, assessmentRepository: repository);

    await _pickValidDateAndTime(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Meeting Link'),
      'https://meet.example.com/room',
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Schedule Interview'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Schedule Interview'));
    await tester.pumpAndSettle();

    expect(repository.createCallCount, 1);
  });

  testWidgets('entered data is retained after a failed submission', (
    tester,
  ) async {
    final repository = _FakeAssessmentRepository()
      ..createError = ApiException('Server error.');
    await _pumpScreen(tester, assessmentRepository: repository);

    await _pickValidDateAndTime(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Meeting Link'),
      'https://meet.example.com/room',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Notes (optional)'),
      'Bring a laptop.',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Schedule Interview'));
    await tester.pumpAndSettle();

    expect(find.text('https://meet.example.com/room'), findsOneWidget);
    expect(find.text('Bring a laptop.'), findsOneWidget);
  });
}

class _ThrowingAssessmentRepository extends AssessmentRepository {
  _ThrowingAssessmentRepository()
    : super(apiClient: ApiClient(tokenStorageService: TokenStorageService()));

  int createCallCount = 0;

  @override
  Future<AssessmentModel?> getAssessmentForApplication(
    int applicationId,
  ) async {
    return null;
  }

  @override
  Future<AssessmentModel> createAssessment({
    required int applicationId,
    required String type,
    InterviewCreateInput? interviewInput,
    QuizCreateInput? quizInput,
  }) async {
    createCallCount++;
    throw TypeError();
  }
}
