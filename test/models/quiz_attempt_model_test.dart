// Direct unit tests for QuizAttemptModel.fromJson.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/models/quiz_attempt_model.dart';

Map<String, dynamic> _attemptJson({
  int id = 1,
  int quizId = 5,
  int applicationId = 9,
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

void main() {
  test('parses a freshly-started (unsubmitted) attempt', () {
    final model = QuizAttemptModel.fromJson(_attemptJson());

    expect(model.id, 1);
    expect(model.quizId, 5);
    expect(model.applicationId, 9);
    expect(model.answers, isEmpty);
    expect(model.score, isNull);
    expect(model.startedAt, DateTime.parse('2026-08-01T09:00:00.000000Z'));
    expect(model.submittedAt, isNull);
    expect(model.isSubmitted, isFalse);
  });

  test('parses a submitted (graded) attempt', () {
    final model = QuizAttemptModel.fromJson(
      _attemptJson(
        answers: [
          {'question_id': 10, 'answer': 'Option A'},
          {'question_id': 11, 'answer': 'True'},
        ],
        score: 75,
        submittedAt: '2026-08-01T09:20:00.000000Z',
      ),
    );

    expect(model.answers, {10: 'Option A', 11: 'True'});
    expect(model.score, 75);
    expect(model.submittedAt, DateTime.parse('2026-08-01T09:20:00.000000Z'));
    expect(model.isSubmitted, isTrue);
  });

  test('a null answers value (unsubmitted attempt) parses to an empty map', () {
    final model = QuizAttemptModel.fromJson(_attemptJson(answers: null));

    expect(model.answers, isEmpty);
  });

  test('a numeric score parses correctly', () {
    final model = QuizAttemptModel.fromJson(_attemptJson(score: 40));

    expect(model.score, 40);
  });

  test('score absent parses to null, not a crash', () {
    final json = _attemptJson()..remove('score');

    final model = QuizAttemptModel.fromJson(json);

    expect(model.score, isNull);
  });

  test('a malformed required id throws rather than silently defaulting', () {
    final json = _attemptJson();
    json['id'] = 'not-an-int';

    expect(() => QuizAttemptModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('a malformed required quiz_id throws', () {
    final json = _attemptJson();
    json['quiz_id'] = null;

    expect(() => QuizAttemptModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('a malformed required application_id throws', () {
    final json = _attemptJson();
    json['application_id'] = null;

    expect(() => QuizAttemptModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('a malformed (non-list) answers value throws', () {
    final json = _attemptJson(answers: 'not-a-list');

    expect(() => QuizAttemptModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('a malformed item within the answers list is skipped, not thrown', () {
    final model = QuizAttemptModel.fromJson(
      _attemptJson(
        answers: [
          {'question_id': 10, 'answer': 'Option A'},
          'not-a-map',
          {'question_id': 'not-an-int', 'answer': 'True'},
        ],
      ),
    );

    expect(model.answers, {10: 'Option A'});
  });

  test('startedAt/submittedAt are optional and parse safely when absent', () {
    final model = QuizAttemptModel.fromJson(
      _attemptJson(startedAt: null, submittedAt: null),
    );

    expect(model.startedAt, isNull);
    expect(model.submittedAt, isNull);
  });

  test('a malformed started_at string parses to null, not a crash', () {
    final model = QuizAttemptModel.fromJson(
      _attemptJson(startedAt: 'not-a-real-date'),
    );

    expect(model.startedAt, isNull);
  });
}
