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

InterviewCreateInput _validInput() {
  return InterviewCreateInput(
    interviewType: 'online',
    scheduledAt: DateTime(2026, 8, 10, 10),
    durationMinutes: 60,
    meetingLink: 'https://meet.example.com/room',
  );
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
      'sends type only (no interview key) for a non-interview type',
      () async {
        final adapter = _FakeHttpClientAdapter((options) {
          return _jsonResponse({
            'success': false,
            'message': 'Quiz assessments are not available yet.',
            'data': null,
          }, 422);
        });
        final repository = _repositoryWithAdapter(adapter);

        await expectLater(
          repository.createAssessment(applicationId: 5, type: 'quiz'),
          throwsA(isA<ApiException>()),
        );

        final body = adapter.lastRequest?.data as Map<String, dynamic>;
        expect(body['type'], 'quiz');
        expect(body.containsKey('interview'), isFalse);
      },
    );

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

  group('getAssessmentForApplication', () {
    test('uses the exact documented singular method and path', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': null}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      await repository.getAssessmentForApplication(5);

      expect(adapter.lastRequest?.method, 'GET');
      expect(
        adapter.lastRequest?.path,
        '/organization/applications/5/assessment',
      );
    });

    test('parses an existing assessment', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': _assessmentJson()}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getAssessmentForApplication(5);

      expect(result, isNotNull);
      expect(result!.id, 1);
      expect(result.interview?.interviewType, 'online');
    });

    test('returns null when data is null (no assessment yet)', () async {
      final adapter = _FakeHttpClientAdapter((options) {
        return _jsonResponse({'data': null}, 200);
      });
      final repository = _repositoryWithAdapter(adapter);

      final result = await repository.getAssessmentForApplication(5);

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
        repository.getAssessmentForApplication(5),
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
        repository.getAssessmentForApplication(5),
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
        repository.getAssessmentForApplication(5),
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
        repository.getAssessmentForApplication(5),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.message, 'message', 'Application not found'),
        ),
      );
    });
  });
}
