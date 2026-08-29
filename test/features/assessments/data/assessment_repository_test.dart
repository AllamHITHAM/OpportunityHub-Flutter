// Direct unit tests for AssessmentRepository.
//
// These exercise the real Dio/ApiClient pipeline against a fake HTTP
// transport, exactly like the other repository test files in this project
// — nothing about ApiClient's architecture is duplicated or bypassed.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/api/api_client.dart';
import 'package:opportunityhub_flutter/core/storage/token_storage_service.dart';
import 'package:opportunityhub_flutter/features/assessments/data/assessment_repository.dart';
import 'package:opportunityhub_flutter/features/assessments/data/interview_create_input.dart';
import 'package:opportunityhub_flutter/features/assessments/data/question_input.dart';
import 'package:opportunityhub_flutter/features/assessments/data/quiz_create_input.dart';
import 'package:opportunityhub_flutter/models/quiz_attempt_model.dart';

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

AssessmentRepository _repositoryWithAdapter(_FakeHttpClientAdapter adapter) {
  final apiClient = ApiClient(tokenStorageService: TokenStorageService())
    ..dio.httpClientAdapter = adapter;
  return AssessmentRepository(apiClient: apiClient);
}

Map<String, dynamic> _applicationJson({int id = 5}) {
  return {
    'id': id,
    'student_id': 1,
    'opportunity_id': 5,
    'cv_id': 2,
    'status': 'interview_scheduled',
    'match_score': null,
    'cover_letter': null,
    'applied_at': '2026-07-20T09:00:00.000000Z',
    'reviewed_at': '2026-08-01T09:00:00.000000Z',
    'created_at': '2026-07-20T09:00:00.000000Z',
    'updated_at': '2026-08-01T09:00:00.000000Z',
    'cv': {
      'id': 2,
      'student_id': 1,
      'title': 'Main CV',
      'file_path': 'uploads/cv.pdf',
      'version': 1,
      'is_default': false,
      'created_by_ai': false,
      'created_at': '2026-07-01T10:00:00.000000Z',
      'updated_at': '2026-07-01T10:00:00.000000Z',
    },
  };
}

Map<String, dynamic> _interviewJson({int id = 1, int assessmentId = 1}) {
  return {
    'id': id,
    'assessment_id': assessmentId,
    'interview_type': 'online',
    'scheduled_at': '2026-08-10T10:00:00.000000Z',
    'duration_minutes': 60,
    'meeting_link': 'https://meet.example.com/room',
    'location': null,
    'interviewer_name': 'Jane Recruiter',
    'interviewer_email': 'jane@example.com',
    'notes': null,
    'status': 'scheduled',
    'decision': 'pending',
    'rating': null,
    'company_feedback': null,
    'completed_at': null,
  };
}

Map<String, dynamic> _completedInterviewJson({
  int id = 1,
  int assessmentId = 1,
  String? decision = 'passed',
  int? rating = 4,
  String? companyFeedback = 'Strong technical answers.',
}) {
  return {
    'id': id,
    'assessment_id': assessmentId,
    'interview_type': 'online',
    'scheduled_at': '2026-08-10T10:00:00.000000Z',
    'duration_minutes': 60,
    'meeting_link': 'https://meet.example.com/room',
    'location': null,
    'interviewer_name': 'Jane Recruiter',
    'interviewer_email': 'jane@example.com',
    'notes': null,
    'status': 'completed',
    'decision': decision,
    'rating': rating,
    'company_feedback': companyFeedback,
    'completed_at': '2026-08-15T11:00:00.000000Z',
    'application': {'id': 5, 'status': 'in_assessment'},
    'assessment': {
      'id': assessmentId,
      'application_id': 5,
      'type': 'interview',
      'status': 'completed',
      'result': decision,
      'completed_at': '2026-08-15T11:00:00.000000Z',
      'application': {'id': 5, 'status': 'in_assessment'},
    },
  };
}

Map<String, dynamic> _assessmentJson({
  int id = 1,
  int applicationId = 5,
  String type = 'interview',
  String status = 'scheduled',
  dynamic result,
  bool includeApplication = true,
  bool includeInterview = true,
}) {
  return {
    'id': id,
    'application_id': applicationId,
    'type': type,
    'status': status,
    'result': result,
    'completed_at': null,
    'created_at': '2026-08-01T09:00:00.000000Z',
    'updated_at': '2026-08-01T09:00:00.000000Z',
    if (includeApplication) 'application': _applicationJson(id: applicationId),
    if (includeInterview) 'interview': _interviewJson(assessmentId: id),
  };
}

/// The real Student-facing Interview shape — `interviewer_email`,
/// `company_feedback`, `rating`, and `decision` are omitted entirely (the
/// backend privacy hotfix), unlike [_interviewJson]'s organization shape.
Map<String, dynamic> _studentInterviewJson({int id = 1, int assessmentId = 1}) {
  return {
    'id': id,
    'assessment_id': assessmentId,
    'interview_type': 'online',
    'scheduled_at': '2026-08-10T10:00:00.000000Z',
    'duration_minutes': 60,
    'meeting_link': 'https://meet.example.com/room',
    'location': null,
    'interviewer_name': 'Jane Recruiter',
    'notes': null,
    'status': 'scheduled',
    'completed_at': null,
  };
}

Map<String, dynamic> _studentAssessmentJson({
  int id = 1,
  int applicationId = 5,
  String type = 'interview',
  String status = 'scheduled',
  dynamic result,
  bool includeInterview = true,
}) {
  return {
    'id': id,
    'application_id': applicationId,
    'type': type,
    'status': status,
    'result': result,
    'completed_at': null,
    'created_at': '2026-08-01T09:00:00.000000Z',
    'updated_at': '2026-08-01T09:00:00.000000Z',
    'application': _applicationJson(id: applicationId),
    if (includeInterview) 'interview': _studentInterviewJson(assessmentId: id),
  };
}

InterviewCreateInput _validInput() {
  return InterviewCreateInput(
    interviewType: 'online',
    scheduledAt: DateTime(2026, 8, 10, 10),
    durationMinutes: 60,
    meetingLink: 'https://meet.example.com/room',
  );
}

QuizCreateInput _validQuizInput() {
  return const QuizCreateInput(
    title: 'Backend Fundamentals',
    instructions: 'Choose the best answer.',
    timeLimitMinutes: 30,
    passingScore: 70,
  );
}

Map<String, dynamic> _questionJson({
  int id = 1,
  int quizId = 1,
  String prompt = 'What is the capital of France?',
  String type = 'multiple_choice',
  dynamic options = const ['Paris', 'London', 'Berlin'],
  String correctAnswer = 'Paris',
  int points = 1,
  int position = 0,
}) {
  return {
    'id': id,
    'quiz_id': quizId,
    'prompt': prompt,
    'type': type,
    'options': options,
    'correct_answer': correctAnswer,
    'points': points,
    'position': position,
    'created_at': '2026-08-01T09:00:00.000000Z',
    'updated_at': '2026-08-01T09:00:00.000000Z',
  };
}

/// The real Student-facing Question shape — `correct_answer` is omitted
/// entirely (the backend's `HidesInternalQuestionFields` trait), unlike
/// [_questionJson]'s organization shape.
Map<String, dynamic> _studentQuestionJson({
  int id = 1,
  int quizId = 1,
  String prompt = 'What is the capital of France?',
  String type = 'multiple_choice',
  dynamic options = const ['Paris', 'London', 'Berlin'],
  int points = 1,
  int position = 0,
}) {
  return {
    'id': id,
    'quiz_id': quizId,
    'prompt': prompt,
    'type': type,
    'options': options,
    'points': points,
    'position': position,
    'created_at': '2026-08-01T09:00:00.000000Z',
    'updated_at': '2026-08-01T09:00:00.000000Z',
  };
}

Map<String, dynamic> _quizAttemptJson({
  int id = 1,
  int quizId = 3,
  int applicationId = 5,
  dynamic answers,
  dynamic score,
  dynamic startedAt = '2026-08-01T09:00:00.000000Z',
  dynamic submittedAt,
}) {
  return {
    'id': id,
    'quiz_id': quizId,
    'application_id': applicationId,
    'answers': answers,
    'score': score,
    'started_at': startedAt,
    'submitted_at': submittedAt,
  };
}

Map<String, dynamic> _quizJson({
  int id = 1,
  int assessmentId = 1,
  String status = 'draft',
  dynamic questions = const [],
  dynamic assessment,
}) {
  return {
    'id': id,
    'assessment_id': assessmentId,
    'title': 'Backend Fundamentals',
    'instructions': 'Choose the best answer.',
    'time_limit_minutes': 30,
    'passing_score': 70,
    'status': status,
    'questions': questions,
    'created_at': '2026-08-01T09:00:00.000000Z',
    'updated_at': '2026-08-01T09:00:00.000000Z',
    'assessment': ?assessment,
  };
}

Map<String, dynamic> _quizAssessmentJson({
  int id = 1,
  int applicationId = 5,
  String status = 'pending',
}) {
  return {
    'id': id,
    'application_id': applicationId,
    'type': 'quiz',
    'status': status,
    'result': null,
    'completed_at': null,
    'created_at': '2026-08-01T09:00:00.000000Z',
    'updated_at': '2026-08-01T09:00:00.000000Z',
    'application': _applicationJson(id: applicationId),
    'quiz': _quizJson(assessmentId: id),
  };
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

  group('createAssessment', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _assessmentJson()}, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.createAssessment(
        applicationId: 5,
        type: 'interview',
        interviewInput: _validInput(),
      );

      expect(adapter.lastRequest?.method, 'POST');
      expect(
        adapter.lastRequest?.path,
        '/organization/applications/5/assessments',
      );
    });

    test('sends the exact nested request body', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _assessmentJson()}, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.createAssessment(
        applicationId: 5,
        type: 'interview',
        interviewInput: _validInput(),
      );

      final body = adapter.lastRequest?.data as Map<String, dynamic>;
      expect(body['type'], 'interview');
      expect(body['interview'], isA<Map<String, dynamic>>());
      final interview = body['interview'] as Map<String, dynamic>;
      expect(interview['interview_type'], 'online');
      expect(interview['scheduled_at'], '2026-08-10 10:00:00');
      expect(interview['duration_minutes'], 60);
      expect(interview['meeting_link'], 'https://meet.example.com/room');
    });

    test('parses the created assessment, including nested interview', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _assessmentJson()}, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.createAssessment(
        applicationId: 5,
        type: 'interview',
        interviewInput: _validInput(),
      );

      expect(result.id, 1);
      expect(result.applicationId, 5);
      expect(result.type, 'interview');
      expect(result.status, 'scheduled');
      expect(result.application?.id, 5);
      expect(result.interview?.interviewType, 'online');
    });

    test(
      'unsupported local type (interview without interviewInput) fails safely before sending',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          fail('No request should have been sent.');
        });
        final repository = _repositoryWithAdapter(adapter);

        expect(
          () =>
              repository.createAssessment(applicationId: 5, type: 'interview'),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test(
      'unsupported local type (quiz without quizInput) fails safely before sending',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          fail('No request should have been sent.');
        });
        final repository = _repositoryWithAdapter(adapter);

        expect(
          () => repository.createAssessment(applicationId: 5, type: 'quiz'),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test(
      'sends the exact nested quiz request body, no interview key',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({'data': _quizAssessmentJson()}, 201);
        });
        final repository = _repositoryWithAdapter(adapter);

        await repository.createQuizAssessment(
          applicationId: 5,
          quizInput: _validQuizInput(),
        );

        expect(adapter.lastRequest?.method, 'POST');
        expect(
          adapter.lastRequest?.path,
          '/organization/applications/5/assessments',
        );
        final body = adapter.lastRequest?.data as Map<String, dynamic>;
        expect(body['type'], 'quiz');
        expect(body.containsKey('interview'), isFalse);
        final quiz = body['quiz'] as Map<String, dynamic>;
        expect(quiz['title'], 'Backend Fundamentals');
        expect(quiz['passing_score'], 70);
      },
    );

    test('parses the created quiz assessment, including nested quiz', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _quizAssessmentJson()}, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.createQuizAssessment(
        applicationId: 5,
        quizInput: _validQuizInput(),
      );

      expect(result.type, 'quiz');
      expect(result.status, 'pending');
      expect(result.quiz, isNotNull);
      expect(result.quiz!.title, 'Backend Fundamentals');
      expect(result.quiz!.status, 'draft');
    });

    test(
      'sends type only (interview and quiz keys both absent) for an unrecognized type',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'success': false,
            'message': 'The given data was invalid.',
            'errors': {
              'type': ['The selected type is invalid.'],
            },
          }, 422);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.createAssessment(
            applicationId: 5,
            type: 'not-a-real-type',
          ),
          throwsA(isA<ApiException>()),
        );

        final body = adapter.lastRequest?.data as Map<String, dynamic>;
        expect(body['type'], 'not-a-real-type');
        expect(body.containsKey('interview'), isFalse);
        expect(body.containsKey('quiz'), isFalse);
      },
    );

    test('throws ApiException on a 401', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Unauthenticated',
          'data': null,
        }, 401);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.createAssessment(
          applicationId: 5,
          type: 'interview',
          interviewInput: _validInput(),
        ),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('throws ApiException on a 403', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'This action is unauthorized for your account type',
          'data': null,
        }, 403);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.createAssessment(
          applicationId: 5,
          type: 'interview',
          interviewInput: _validInput(),
        ),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });

    test(
      'throws ApiException on a 404 (application not found/not owned)',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'success': false,
            'message': 'Application not found',
            'data': null,
          }, 404);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.createAssessment(
            applicationId: 5,
            type: 'interview',
            interviewInput: _validInput(),
          ),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 404)
                .having((e) => e.message, 'message', 'Application not found'),
          ),
        );
      },
    );

    test(
      'throws with the exact 409 message on a duplicate assessment',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'success': false,
            'message': 'An assessment already exists for this application',
            'data': null,
          }, 409);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.createAssessment(
            applicationId: 5,
            type: 'interview',
            interviewInput: _validInput(),
          ),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 409)
                .having(
                  (e) => e.message,
                  'message',
                  'An assessment already exists for this application',
                ),
          ),
        );
      },
    );

    test(
      'throws with the exact 422 message for an invalid source status',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'success': false,
            'message':
                'An assessment can only be created for shortlisted applications',
            'data': null,
          }, 422);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.createAssessment(
            applicationId: 5,
            type: 'interview',
            interviewInput: _validInput(),
          ),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 422)
                .having(
                  (e) => e.message,
                  'message',
                  'An assessment can only be created for shortlisted applications',
                ),
          ),
        );
      },
    );

    test('preserves nested field validation errors', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'message': 'The given data was invalid.',
          'errors': {
            'interview.meeting_link': [
              'The interview.meeting link field is required when interview.interview type is online.',
            ],
            'interview.scheduled_at': [
              'The interview.scheduled at field is required.',
            ],
          },
        }, 422);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.createAssessment(
          applicationId: 5,
          type: 'interview',
          interviewInput: _validInput(),
        ),
        throwsA(
          isA<ApiException>()
              .having(
                (e) => e.errors?['interview.meeting_link'],
                'errors[interview.meeting_link]',
                isNotNull,
              )
              .having(
                (e) => e.errors?['interview.scheduled_at'],
                'errors[interview.scheduled_at]',
                isNotNull,
              ),
        ),
      );
    });

    test('malformed success response is never silently swallowed', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {'id': 'not-an-int'},
        }, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.createAssessment(
          applicationId: 5,
          type: 'interview',
          interviewInput: _validInput(),
        ),
        throwsA(anything),
      );
    });
  });

  group('getAssessmentsForApplication', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': <dynamic>[]}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.getAssessmentsForApplication(5);

      expect(adapter.lastRequest?.method, 'GET');
      expect(
        adapter.lastRequest?.path,
        '/organization/applications/5/assessment',
      );
    });

    test('parses the full assessment history, in the order returned', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': [_assessmentJson(), _assessmentJson(id: 2)],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getAssessmentsForApplication(5);

      expect(result, hasLength(2));
      expect(result[0].id, 1);
      expect(result[0].interview?.interviewType, 'online');
      expect(result[1].id, 2);
    });

    test('returns an empty list when data is empty (no assessment yet)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': <dynamic>[]}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getAssessmentsForApplication(5);

      expect(result, isEmpty);
    });

    test('a non-list response never silently becomes an empty list', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _assessmentJson()}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getAssessmentsForApplication(5),
        throwsA(isA<TypeError>()),
      );
    });

    test('a malformed element never silently disappears from the list', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': ['not an object'],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getAssessmentsForApplication(5),
        throwsA(isA<TypeError>()),
      );
    });

    test('throws ApiException on a 401', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Unauthenticated',
          'data': null,
        }, 401);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getAssessmentsForApplication(5),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('throws ApiException on a 403', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'This action is unauthorized for your account type',
          'data': null,
        }, 403);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getAssessmentsForApplication(5),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });

    test('throws ApiException on a 404', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Application not found',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getAssessmentsForApplication(5),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.message, 'message', 'Application not found'),
        ),
      );
    });
  });

  group('completeInterview', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _completedInterviewJson()}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.completeInterview(interviewId: 1);

      expect(adapter.lastRequest?.method, 'PUT');
      expect(
        adapter.lastRequest?.path,
        '/organization/interviews/1/complete',
      );
    });

    test('an empty payload sends no keys at all', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _completedInterviewJson()}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.completeInterview(interviewId: 1);

      final body = adapter.lastRequest?.data as Map<String, dynamic>;
      expect(body, isEmpty);
    });

    test('sends only the decision when only decision is given', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _completedInterviewJson()}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.completeInterview(interviewId: 1, decision: 'passed');

      final body = adapter.lastRequest?.data as Map<String, dynamic>;
      expect(body, {'decision': 'passed'});
    });

    test('sends rating and company_feedback when given', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _completedInterviewJson()}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.completeInterview(
        interviewId: 1,
        rating: 5,
        companyFeedback: 'Great candidate.',
      );

      final body = adapter.lastRequest?.data as Map<String, dynamic>;
      expect(body, {'rating': 5, 'company_feedback': 'Great candidate.'});
    });

    test(
      'a blank/whitespace-only decision or feedback is omitted, not sent as an empty string',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({'data': _completedInterviewJson()}, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await repository.completeInterview(
          interviewId: 1,
          decision: '   ',
          companyFeedback: '   ',
        );

        final body = adapter.lastRequest?.data as Map<String, dynamic>;
        expect(body, isEmpty);
      },
    );

    test('parses the updated (completed) interview', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _completedInterviewJson(decision: 'passed', rating: 4),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.completeInterview(
        interviewId: 1,
        decision: 'passed',
        rating: 4,
      );

      expect(result.status, 'completed');
      expect(result.decision, 'passed');
      expect(result.rating, 4);
      expect(result.completedAt, isNotNull);
    });

    test('throws ApiException on a 401', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Unauthenticated',
          'data': null,
        }, 401);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.completeInterview(interviewId: 1),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('throws ApiException on a 404 (interview not owned/missing)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Interview not found',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.completeInterview(interviewId: 1),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.message, 'message', 'Interview not found'),
        ),
      );
    });

    test('preserves field validation errors', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'message': 'The given data was invalid.',
          'errors': {
            'rating': ['The rating must be at least 1.'],
          },
        }, 422);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.completeInterview(interviewId: 1, rating: 0),
        throwsA(
          isA<ApiException>().having(
            (e) => e.errors?['rating'],
            'errors[rating]',
            isNotNull,
          ),
        ),
      );
    });

    test('malformed success response is never silently swallowed', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {'id': 'not-an-int'},
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.completeInterview(interviewId: 1),
        throwsA(anything),
      );
    });
  });

  group('getStudentAssessments', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': []}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.getStudentAssessments();

      expect(adapter.lastRequest?.method, 'GET');
      expect(adapter.lastRequest?.path, '/student/assessments');
    });

    test('parses a valid list, including nested interview', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': [
            _studentAssessmentJson(id: 1, applicationId: 5),
            _studentAssessmentJson(id: 2, applicationId: 9),
          ],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getStudentAssessments();

      expect(result, hasLength(2));
      expect(result[0].applicationId, 5);
      expect(result[1].applicationId, 9);
      expect(result[0].interview?.interviewType, 'online');
      expect(result[0].interview?.meetingLink, 'https://meet.example.com/room');
    });

    test('the nested interview never carries the fields the backend omits '
        '(defense-in-depth: proves the real response shape parses safely '
        'even without them present at all)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': [_studentAssessmentJson()],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getStudentAssessments();

      final interview = result.single.interview!;
      expect(interview.interviewerEmail, isNull);
      expect(interview.companyFeedback, isNull);
      expect(interview.rating, isNull);
      expect(interview.decision, isNull);
    });

    test('an empty list is represented correctly, not as an error', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': []}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getStudentAssessments();

      expect(result, isEmpty);
    });

    test(
      'a malformed response (data is not a list) never becomes an empty list',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'data': {'not': 'a list'},
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.getStudentAssessments(),
          throwsA(isA<TypeError>()),
        );
      },
    );

    test('a malformed list item never becomes an empty list', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': [
            {'id': 'not-an-int'},
          ],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getStudentAssessments(),
        throwsA(isA<TypeError>()),
      );
    });

    test('throws ApiException on a 401', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Unauthenticated',
          'data': null,
        }, 401);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getStudentAssessments(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('throws ApiException on a 403', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'This action is unauthorized for your account type',
          'data': null,
        }, 403);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getStudentAssessments(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });
  });

  group('getStudentAssessment', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _studentAssessmentJson(id: 7)}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.getStudentAssessment(7);

      expect(adapter.lastRequest?.method, 'GET');
      expect(adapter.lastRequest?.path, '/student/assessments/7');
    });

    test('parses a valid response', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _studentAssessmentJson(id: 7, applicationId: 5),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getStudentAssessment(7);

      expect(result.id, 7);
      expect(result.applicationId, 5);
      expect(result.interview?.interviewType, 'online');
    });

    test('throws ApiException on a 404', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Assessment not found',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getStudentAssessment(999),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.message, 'message', 'Assessment not found'),
        ),
      );
    });

    test(
      'a malformed successful response never becomes a fake assessment',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'data': {'id': 'not-an-int'},
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.getStudentAssessment(7),
          throwsA(isA<TypeError>()),
        );
      },
    );
  });

  group('getStudentAssessmentsForApplication', () {
    test('finds every assessment matching applicationId, in order', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': [
            _studentAssessmentJson(id: 1, applicationId: 5),
            _studentAssessmentJson(id: 2, applicationId: 9),
            _studentAssessmentJson(id: 3, applicationId: 9),
          ],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getStudentAssessmentsForApplication(9);

      expect(result, hasLength(2));
      expect(result[0].id, 2);
      expect(result[1].id, 3);
      expect(result.every((a) => a.applicationId == 9), isTrue);
    });

    test('multiple assessments across different applications each resolve to '
        'their own application only', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': [
            _studentAssessmentJson(id: 1, applicationId: 5),
            _studentAssessmentJson(id: 2, applicationId: 9),
            _studentAssessmentJson(id: 3, applicationId: 12),
          ],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      expect(
        (await repository.getStudentAssessmentsForApplication(5))
            .map((a) => a.id),
        [1],
      );
      expect(
        (await repository.getStudentAssessmentsForApplication(12))
            .map((a) => a.id),
        [3],
      );
    });

    test('returns an empty list when no assessment matches the applicationId', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': [_studentAssessmentJson(id: 1, applicationId: 5)],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getStudentAssessmentsForApplication(
        999,
      );

      expect(result, isEmpty);
    });

    test('a malformed list propagates safely, never becomes an empty list', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {'not': 'a list'},
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getStudentAssessmentsForApplication(5),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('getOrganizationQuiz', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': null}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.getOrganizationQuiz(7);

      expect(adapter.lastRequest?.method, 'GET');
      expect(adapter.lastRequest?.path, '/organization/assessments/7/quiz');
    });

    test('parses an existing quiz, including nested questions', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _quizJson(questions: [_questionJson()]),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getOrganizationQuiz(7);

      expect(result, isNotNull);
      expect(result!.title, 'Backend Fundamentals');
      expect(result.questions, hasLength(1));
      expect(result.questions.first.correctAnswer, 'Paris');
    });

    test('returns null when data is null (no quiz yet)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': null}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getOrganizationQuiz(7);

      expect(result, isNull);
    });

    test('a non-null malformed response never silently becomes null', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': ['not', 'an', 'object'],
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getOrganizationQuiz(7),
        throwsA(isA<TypeError>()),
      );
    });

    test('throws ApiException on a 404', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Assessment not found',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getOrganizationQuiz(7),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.message, 'message', 'Assessment not found'),
        ),
      );
    });
  });

  group('createQuizQuestion', () {
    QuestionInput input() {
      return const QuestionInput(
        prompt: 'What is the capital of France?',
        type: 'multiple_choice',
        options: ['Paris', 'London', 'Berlin'],
        correctAnswer: 'Paris',
        points: 1,
        position: 0,
      );
    }

    test('uses the exact documented method, path, and body', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _questionJson()}, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.createQuizQuestion(quizId: 3, input: input());

      expect(adapter.lastRequest?.method, 'POST');
      expect(adapter.lastRequest?.path, '/organization/quizzes/3/questions');
      final body = adapter.lastRequest?.data as Map<String, dynamic>;
      expect(body['prompt'], 'What is the capital of France?');
      expect(body['options'], ['Paris', 'London', 'Berlin']);
    });

    test('parses the created question', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _questionJson()}, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.createQuizQuestion(
        quizId: 3,
        input: input(),
      );

      expect(result.correctAnswer, 'Paris');
      expect(result.type, 'multiple_choice');
    });

    test('throws with the exact 422 message for a published quiz', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Published quizzes cannot be modified',
          'data': null,
        }, 422);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.createQuizQuestion(quizId: 3, input: input()),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Published quizzes cannot be modified',
          ),
        ),
      );
    });

    test('throws ApiException on a 404', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Quiz not found',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.createQuizQuestion(quizId: 3, input: input()),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });

    test('preserves field validation errors', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'message': 'The given data was invalid.',
          'errors': {
            'correct_answer': ['The correct answer must be True or False.'],
          },
        }, 422);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.createQuizQuestion(quizId: 3, input: input()),
        throwsA(
          isA<ApiException>().having(
            (e) => e.errors?['correct_answer'],
            'errors[correct_answer]',
            isNotNull,
          ),
        ),
      );
    });

    test('malformed success response is never silently swallowed', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {'id': 'not-an-int'},
        }, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.createQuizQuestion(quizId: 3, input: input()),
        throwsA(anything),
      );
    });
  });

  group('updateQuizQuestion', () {
    QuestionInput input() {
      return const QuestionInput(
        prompt: 'What is the capital of Germany?',
        type: 'multiple_choice',
        options: ['Berlin', 'Munich'],
        correctAnswer: 'Berlin',
        points: 1,
        position: 0,
      );
    }

    test('uses the exact documented method, path, and body', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _questionJson(prompt: 'What is the capital of Germany?'),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.updateQuizQuestion(
        quizId: 3,
        questionId: 9,
        input: input(),
      );

      expect(adapter.lastRequest?.method, 'PUT');
      expect(adapter.lastRequest?.path, '/organization/quizzes/3/questions/9');
      final body = adapter.lastRequest?.data as Map<String, dynamic>;
      expect(body['prompt'], 'What is the capital of Germany?');
    });

    test('parses the updated question', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _questionJson(prompt: 'What is the capital of Germany?'),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.updateQuizQuestion(
        quizId: 3,
        questionId: 9,
        input: input(),
      );

      expect(result.prompt, 'What is the capital of Germany?');
    });

    test('throws ApiException on a 404 (question not on this quiz)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Question not found',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.updateQuizQuestion(quizId: 3, questionId: 9, input: input()),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.message, 'message', 'Question not found'),
        ),
      );
    });
  });

  group('deleteQuizQuestion', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': true,
          'message': 'Question deleted successfully',
          'data': null,
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.deleteQuizQuestion(quizId: 3, questionId: 9);

      expect(adapter.lastRequest?.method, 'DELETE');
      expect(adapter.lastRequest?.path, '/organization/quizzes/3/questions/9');
    });

    test('throws with the exact 422 message for a published quiz', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Published quizzes cannot be modified',
          'data': null,
        }, 422);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.deleteQuizQuestion(quizId: 3, questionId: 9),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('publishQuiz', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _quizJson(status: 'published')}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.publishQuiz(3);

      expect(adapter.lastRequest?.method, 'PUT');
      expect(adapter.lastRequest?.path, '/organization/quizzes/3/publish');
    });

    test(
      'parses the published quiz, including the nested assessment status',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'data': _quizJson(
              status: 'published',
              assessment: {
                'id': 1,
                'application_id': 5,
                'type': 'quiz',
                'status': 'scheduled',
                'result': null,
              },
            ),
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        final result = await repository.publishQuiz(3);

        expect(result.status, 'published');
        expect(result.assessmentStatus, 'scheduled');
      },
    );

    test('throws with the exact 422 message for zero questions', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message':
              'A quiz must have at least one question before it can be published',
          'data': null,
        }, 422);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.publishQuiz(3),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'A quiz must have at least one question before it can be published',
          ),
        ),
      );
    });

    test('throws with the exact 422 message when already published', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Only draft quizzes can be published',
          'data': null,
        }, 422);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.publishQuiz(3),
        throwsA(isA<ApiException>()),
      );
    });

    test('throws ApiException on a 401', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Unauthenticated',
          'data': null,
        }, 401);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.publishQuiz(3),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });
  });

  group('getStudentQuiz', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _quizJson(status: 'published')}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.getStudentQuiz(7);

      expect(adapter.lastRequest?.method, 'GET');
      expect(adapter.lastRequest?.path, '/student/assessments/7/quiz');
    });

    test(
      'parses a published quiz, including nested student-safe questions',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'data': _quizJson(
              status: 'published',
              questions: [_studentQuestionJson()],
            ),
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        final result = await repository.getStudentQuiz(7);

        expect(result.title, 'Backend Fundamentals');
        expect(result.status, 'published');
        expect(result.questions, hasLength(1));
        expect(result.questions.first.prompt, isNotEmpty);
      },
    );

    test('the nested question never carries correct_answer, even though '
        'QuestionModel has the field for the Organization side', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _quizJson(
            status: 'published',
            questions: [_studentQuestionJson()],
          ),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getStudentQuiz(7);

      expect(result.questions.single.correctAnswer, isNull);
    });

    test('throws ApiException on a 404 (also covers "not a quiz assessment", '
        '"no quiz yet", and "quiz still draft" — the backend returns the same '
        '404 for all of these)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Quiz not found',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getStudentQuiz(7),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.message, 'message', 'Quiz not found'),
        ),
      );
    });

    test('throws ApiException on a 401', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Unauthenticated',
          'data': null,
        }, 401);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.getStudentQuiz(7),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('malformed success response is never silently swallowed', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {'id': 'not-an-int'},
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(repository.getStudentQuiz(7), throwsA(anything));
    });
  });

  group('startStudentQuiz', () {
    test('uses the exact documented method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _quizAttemptJson()}, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.startStudentQuiz(3);

      expect(adapter.lastRequest?.method, 'POST');
      expect(adapter.lastRequest?.path, '/student/quizzes/3/start');
    });

    test('parses a freshly-created attempt', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _quizAttemptJson()}, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.startStudentQuiz(3);

      expect(result, isA<QuizAttemptModel>());
      expect(result.quizId, 3);
      expect(result.isSubmitted, isFalse);
    });

    test(
      'parses a resumed (existing, unsubmitted) attempt the same way',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'success': true,
            'message': 'Quiz attempt resumed',
            'data': _quizAttemptJson(id: 9),
          }, 200);
        });
        final repository = _repositoryWithAdapter(adapter);

        final result = await repository.startStudentQuiz(3);

        expect(result.id, 9);
        expect(result.isSubmitted, isFalse);
      },
    );

    test('throws with the exact 409 message when already submitted', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Quiz has already been submitted',
          'data': null,
        }, 409);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.startStudentQuiz(3),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having(
                (e) => e.message,
                'message',
                'Quiz has already been submitted',
              ),
        ),
      );
    });

    test(
      'throws ApiException on a 404 (quiz not owned/missing/unpublished)',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'success': false,
            'message': 'Quiz not found',
            'data': null,
          }, 404);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.startStudentQuiz(3),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
          ),
        );
      },
    );

    test('malformed success response is never silently swallowed', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {'id': 'not-an-int'},
        }, 201);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(repository.startStudentQuiz(3), throwsA(anything));
    });
  });

  group('submitStudentQuiz', () {
    test('uses the exact documented method, path, and body shape', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _quizAttemptJson(
            submittedAt: '2026-08-01T09:20:00.000000Z',
            score: 100,
          ),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.submitStudentQuiz(
        quizId: 3,
        answers: {10: 'Option A', 11: 'True'},
      );

      expect(adapter.lastRequest?.method, 'POST');
      expect(adapter.lastRequest?.path, '/student/quizzes/3/submit');
      final body = adapter.lastRequest?.data as Map<String, dynamic>;
      final answers = body['answers'] as List<dynamic>;
      expect(answers, hasLength(2));
      expect(
        answers,
        containsAll([
          {'question_id': 10, 'answer': 'Option A'},
          {'question_id': 11, 'answer': 'True'},
        ]),
      );
    });

    test('parses the graded attempt', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': _quizAttemptJson(
            submittedAt: '2026-08-01T09:20:00.000000Z',
            score: 75,
          ),
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.submitStudentQuiz(
        quizId: 3,
        answers: {10: 'Option A'},
      );

      expect(result.score, 75);
      expect(result.isSubmitted, isTrue);
    });

    test('throws with the exact 409 message when already submitted', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Quiz has already been submitted',
          'data': null,
        }, 409);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.submitStudentQuiz(quizId: 3, answers: {10: 'Option A'}),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 409),
        ),
      );
    });

    test(
      'throws with the exact 422 message when the time limit has expired',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'success': false,
            'message': 'The time limit for this quiz has expired',
            'data': null,
          }, 422);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.submitStudentQuiz(quizId: 3, answers: {10: 'Option A'}),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 422)
                .having(
                  (e) => e.message,
                  'message',
                  'The time limit for this quiz has expired',
                ),
          ),
        );
      },
    );

    test('preserves field validation errors', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'message': 'The given data was invalid.',
          'errors': {
            'answers': ['Every quiz question must be answered.'],
          },
        }, 422);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.submitStudentQuiz(quizId: 3, answers: {10: 'Option A'}),
        throwsA(
          isA<ApiException>().having(
            (e) => e.errors?['answers'],
            'errors[answers]',
            isNotNull,
          ),
        ),
      );
    });

    test('throws ApiException on a 404', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'success': false,
          'message': 'Quiz not found',
          'data': null,
        }, 404);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.submitStudentQuiz(quizId: 3, answers: {10: 'Option A'}),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });

    test('malformed success response is never silently swallowed', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({
          'data': {'id': 'not-an-int'},
        }, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await expectLater(
        repository.submitStudentQuiz(quizId: 3, answers: {10: 'Option A'}),
        throwsA(anything),
      );
    });
  });
}
