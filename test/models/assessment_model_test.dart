// Direct unit tests for AssessmentModel.fromJson.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/models/assessment_model.dart';

Map<String, dynamic> _cvJson({int id = 2}) {
  return {
    'id': id,
    'student_id': 1,
    'title': 'Main CV',
    'file_path': 'uploads/cv.pdf',
    'version': 1,
    'is_default': false,
    'created_by_ai': false,
    'created_at': '2026-07-01T10:00:00.000000Z',
    'updated_at': '2026-07-01T10:00:00.000000Z',
  };
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
    'cv': _cvJson(),
  };
}

Map<String, dynamic> _quizJson({int id = 1, int assessmentId = 1}) {
  return {
    'id': id,
    'assessment_id': assessmentId,
    'title': 'Backend Fundamentals',
    'instructions': 'Choose the best answer.',
    'time_limit_minutes': 30,
    'passing_score': 70,
    'status': 'draft',
    'questions': [],
    'created_at': '2026-08-01T09:00:00.000000Z',
    'updated_at': '2026-08-01T09:00:00.000000Z',
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
  dynamic completedAt,
  dynamic createdAt = '2026-08-01T09:00:00.000000Z',
  dynamic updatedAt = '2026-08-01T09:00:00.000000Z',
  Map<String, dynamic>? application,
  Map<String, dynamic>? interview,
  Map<String, dynamic>? quiz,
}) {
  return {
    'id': id,
    'application_id': applicationId,
    'type': type,
    'status': status,
    'result': result,
    'completed_at': completedAt,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'application': ?application,
    'interview': ?interview,
    'quiz': ?quiz,
  };
}

void main() {
  test('parses a full interview assessment response', () {
    final model = AssessmentModel.fromJson(
      _assessmentJson(
        application: _applicationJson(),
        interview: _interviewJson(),
      ),
    );

    expect(model.id, 1);
    expect(model.applicationId, 5);
    expect(model.type, 'interview');
    expect(model.status, 'scheduled');
    expect(model.result, isNull);
    expect(model.completedAt, isNull);
    expect(model.createdAt, DateTime.parse('2026-08-01T09:00:00.000000Z'));
    expect(model.updatedAt, DateTime.parse('2026-08-01T09:00:00.000000Z'));
    expect(model.application, isNotNull);
    expect(model.application!.id, 5);
    expect(model.interview, isNotNull);
    expect(model.interview!.id, 1);
    expect(model.interview!.interviewType, 'online');
  });

  test('result and completedAt are nullable', () {
    final model = AssessmentModel.fromJson(_assessmentJson());

    expect(model.result, isNull);
    expect(model.completedAt, isNull);
  });

  test('result and completedAt parse when the assessment is completed', () {
    final model = AssessmentModel.fromJson(
      _assessmentJson(
        status: 'completed',
        result: 'passed',
        completedAt: '2026-08-11T10:00:00.000000Z',
      ),
    );

    expect(model.status, 'completed');
    expect(model.result, 'passed');
    expect(model.completedAt, DateTime.parse('2026-08-11T10:00:00.000000Z'));
  });

  test('application is null when absent from the response', () {
    final model = AssessmentModel.fromJson(
      _assessmentJson(interview: _interviewJson()),
    );

    expect(model.application, isNull);
    expect(model.interview, isNotNull);
  });

  test('interview is null when absent from the response', () {
    final model = AssessmentModel.fromJson(
      _assessmentJson(application: _applicationJson()),
    );

    expect(model.interview, isNull);
    expect(model.application, isNotNull);
  });

  test('both application and interview absent parses safely', () {
    final model = AssessmentModel.fromJson(_assessmentJson());

    expect(model.application, isNull);
    expect(model.interview, isNull);
  });

  test('a wrong-type nested application is treated as absent, not a crash', () {
    final json = _assessmentJson();
    json['application'] = 'not-an-object';

    final model = AssessmentModel.fromJson(json);

    expect(model.application, isNull);
  });

  test('a wrong-type nested interview is treated as absent, not a crash', () {
    final json = _assessmentJson();
    json['interview'] = ['not', 'an', 'object'];

    final model = AssessmentModel.fromJson(json);

    expect(model.interview, isNull);
  });

  test('a malformed required id throws rather than silently defaulting', () {
    final json = _assessmentJson();
    json['id'] = 'not-an-int';

    expect(() => AssessmentModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('a malformed required application_id throws', () {
    final json = _assessmentJson();
    json['application_id'] = null;

    expect(() => AssessmentModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('an invalid completed_at string parses to null, not a crash', () {
    final model = AssessmentModel.fromJson(
      _assessmentJson(completedAt: 'not-a-real-date'),
    );

    expect(model.completedAt, isNull);
  });

  test('an unknown type value is preserved as-is, not rejected', () {
    final model = AssessmentModel.fromJson(_assessmentJson(type: 'quiz'));

    expect(model.type, 'quiz');
  });

  test('an unknown status value is preserved as-is, not rejected', () {
    final model = AssessmentModel.fromJson(
      _assessmentJson(status: 'some_future_status'),
    );

    expect(model.status, 'some_future_status');
  });

  test('parses a full quiz assessment response', () {
    final model = AssessmentModel.fromJson(
      _assessmentJson(
        type: 'quiz',
        status: 'pending',
        application: _applicationJson(),
        quiz: _quizJson(),
      ),
    );

    expect(model.type, 'quiz');
    expect(model.status, 'pending');
    expect(model.application, isNotNull);
    expect(model.quiz, isNotNull);
    expect(model.quiz!.title, 'Backend Fundamentals');
    expect(model.quiz!.passingScore, 70);
    expect(model.quiz!.status, 'draft');
    expect(model.interview, isNull);
  });

  test('interview parsing is unaffected by the new quiz field', () {
    final model = AssessmentModel.fromJson(
      _assessmentJson(type: 'interview', interview: _interviewJson()),
    );

    expect(model.interview, isNotNull);
    expect(model.interview!.interviewType, 'online');
    expect(model.quiz, isNull);
  });

  test('quiz is null when absent from the response', () {
    final model = AssessmentModel.fromJson(
      _assessmentJson(type: 'interview', interview: _interviewJson()),
    );

    expect(model.quiz, isNull);
  });

  test('a wrong-type nested quiz is treated as absent, not a crash', () {
    final json = _assessmentJson(type: 'quiz');
    json['quiz'] = 'not-an-object';

    final model = AssessmentModel.fromJson(json);

    expect(model.quiz, isNull);
  });

  test('both interview and quiz absent parses safely', () {
    final model = AssessmentModel.fromJson(_assessmentJson());

    expect(model.interview, isNull);
    expect(model.quiz, isNull);
  });
}
