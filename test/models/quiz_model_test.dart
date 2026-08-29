// Direct unit tests for QuizModel.fromJson.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/models/quiz_model.dart';

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

Map<String, dynamic> _quizJson({
  int id = 1,
  int assessmentId = 1,
  String title = 'Backend Fundamentals',
  dynamic instructions = 'Choose the best answer.',
  dynamic timeLimitMinutes = 30,
  int passingScore = 70,
  String status = 'draft',
  dynamic questions = const [],
  dynamic createdAt = '2026-08-01T09:00:00.000000Z',
  dynamic updatedAt = '2026-08-01T09:00:00.000000Z',
  dynamic assessment,
}) {
  return {
    'id': id,
    'assessment_id': assessmentId,
    'title': title,
    'instructions': instructions,
    'time_limit_minutes': timeLimitMinutes,
    'passing_score': passingScore,
    'status': status,
    'questions': questions,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'assessment': ?assessment,
  };
}

void main() {
  test('parses a full quiz response with no questions', () {
    final model = QuizModel.fromJson(_quizJson());

    expect(model.id, 1);
    expect(model.assessmentId, 1);
    expect(model.title, 'Backend Fundamentals');
    expect(model.instructions, 'Choose the best answer.');
    expect(model.timeLimitMinutes, 30);
    expect(model.passingScore, 70);
    expect(model.status, 'draft');
    expect(model.questions, isEmpty);
    expect(model.createdAt, DateTime.parse('2026-08-01T09:00:00.000000Z'));
    expect(model.updatedAt, DateTime.parse('2026-08-01T09:00:00.000000Z'));
    expect(model.assessmentStatus, isNull);
  });

  test('parses nested questions', () {
    final model = QuizModel.fromJson(
      _quizJson(
        questions: [
          _questionJson(id: 1, position: 0),
          _questionJson(id: 2, position: 1, type: 'true_false', options: null),
        ],
      ),
    );

    expect(model.questions, hasLength(2));
    expect(model.questions[0].id, 1);
    expect(model.questions[1].id, 2);
    expect(model.questions[1].type, 'true_false');
    expect(model.questions[1].options, isNull);
  });

  test('questions absent from the response defaults to an empty list', () {
    final json = _quizJson()..remove('questions');

    final model = QuizModel.fromJson(json);

    expect(model.questions, isEmpty);
  });

  test('questions null in the response defaults to an empty list', () {
    final model = QuizModel.fromJson(_quizJson(questions: null));

    expect(model.questions, isEmpty);
  });

  test('a malformed questions value (not a list) throws, never becomes []', () {
    final json = _quizJson(questions: 'not-a-list');

    expect(() => QuizModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('a malformed item inside questions throws, never becomes []', () {
    final json = _quizJson(
      questions: [
        {'id': 'not-an-int'},
      ],
    );

    expect(() => QuizModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('instructions and time_limit_minutes are nullable', () {
    final model = QuizModel.fromJson(
      _quizJson(instructions: null, timeLimitMinutes: null),
    );

    expect(model.instructions, isNull);
    expect(model.timeLimitMinutes, isNull);
  });

  test('a malformed required id throws rather than silently defaulting', () {
    final json = _quizJson();
    json['id'] = 'not-an-int';

    expect(() => QuizModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test(
    'a null assessment_id parses safely (Phase 10A.4B shared template shape)',
    () {
      final json = _quizJson();
      json['assessment_id'] = null;
      json['opportunity_id'] = 7;

      final quiz = QuizModel.fromJson(json);

      expect(quiz.assessmentId, isNull);
      expect(quiz.opportunityId, 7);
    },
  );

  test('a legacy quiz parses with opportunityId null', () {
    final json = _quizJson();

    final quiz = QuizModel.fromJson(json);

    expect(quiz.assessmentId, isNotNull);
    expect(quiz.opportunityId, isNull);
  });

  test('a malformed required title throws', () {
    final json = _quizJson();
    json['title'] = null;

    expect(() => QuizModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('a malformed required passing_score throws', () {
    final json = _quizJson();
    json['passing_score'] = 'not-an-int';

    expect(() => QuizModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('createdAt/updatedAt are optional and parse safely when absent', () {
    final model = QuizModel.fromJson(
      _quizJson(createdAt: null, updatedAt: null),
    );

    expect(model.createdAt, isNull);
    expect(model.updatedAt, isNull);
  });

  test('an unknown status value is preserved as-is, not rejected', () {
    final model = QuizModel.fromJson(_quizJson(status: 'some_future_status'));

    expect(model.status, 'some_future_status');
  });

  test(
    'assessmentStatus parses from a nested assessment object (the publish response shape)',
    () {
      final model = QuizModel.fromJson(
        _quizJson(
          status: 'published',
          assessment: {
            'id': 1,
            'application_id': 5,
            'type': 'quiz',
            'status': 'scheduled',
            'result': null,
          },
        ),
      );

      expect(model.status, 'published');
      expect(model.assessmentStatus, 'scheduled');
    },
  );

  test(
    'assessmentStatus is null when assessment is absent (every other Quiz response)',
    () {
      final model = QuizModel.fromJson(_quizJson());

      expect(model.assessmentStatus, isNull);
    },
  );

  test('a wrong-type nested assessment is treated as absent, not a crash', () {
    final model = QuizModel.fromJson(_quizJson(assessment: 'not-an-object'));

    expect(model.assessmentStatus, isNull);
  });

  group('Phase 10A.4B addendum — availability policy and window', () {
    test('parses the shared availability policy on a template quiz', () {
      final json = _quizJson()
        ..['availability_delay_days'] = 2
        ..['availability_time'] = '10:00'
        ..['submission_window_hours'] = 48;

      final model = QuizModel.fromJson(json);

      expect(model.availabilityDelayDays, 2);
      expect(model.availabilityTime, '10:00');
      expect(model.submissionWindowHours, 48);
    });

    test('policy fields default to null when absent (legacy quiz)', () {
      final model = QuizModel.fromJson(_quizJson());

      expect(model.availabilityDelayDays, isNull);
      expect(model.availabilityTime, isNull);
      expect(model.submissionWindowHours, isNull);
    });

    test(
      'parses a candidate-specific available_at/due_at (Student quiz response)',
      () {
        final json = _quizJson()
          ..['available_at'] = '2026-08-28T10:00:00.000000Z'
          ..['due_at'] = '2026-08-30T10:00:00.000000Z';

        final model = QuizModel.fromJson(json);

        expect(
          model.availableAt,
          DateTime.parse('2026-08-28T10:00:00.000000Z'),
        );
        expect(model.dueAt, DateTime.parse('2026-08-30T10:00:00.000000Z'));
      },
    );

    test(
      'available_at/due_at default to null when absent (no gating / legacy)',
      () {
        final model = QuizModel.fromJson(_quizJson());

        expect(model.availableAt, isNull);
        expect(model.dueAt, isNull);
      },
    );
  });
}
