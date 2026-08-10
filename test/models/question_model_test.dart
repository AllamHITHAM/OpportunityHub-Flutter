// Direct unit tests for QuestionModel.fromJson.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/models/question_model.dart';

Map<String, dynamic> _questionJson({
  int id = 1,
  int quizId = 1,
  String prompt = 'What is the capital of France?',
  String type = 'multiple_choice',
  dynamic options = const ['Paris', 'London', 'Berlin'],
  String? correctAnswer = 'Paris',
  int points = 1,
  int position = 0,
  dynamic createdAt = '2026-08-01T09:00:00.000000Z',
  dynamic updatedAt = '2026-08-01T09:00:00.000000Z',
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
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}

void main() {
  test('parses a full multiple_choice question', () {
    final model = QuestionModel.fromJson(_questionJson());

    expect(model.id, 1);
    expect(model.quizId, 1);
    expect(model.prompt, 'What is the capital of France?');
    expect(model.type, 'multiple_choice');
    expect(model.options, ['Paris', 'London', 'Berlin']);
    expect(model.correctAnswer, 'Paris');
    expect(model.points, 1);
    expect(model.position, 0);
    expect(model.createdAt, DateTime.parse('2026-08-01T09:00:00.000000Z'));
    expect(model.updatedAt, DateTime.parse('2026-08-01T09:00:00.000000Z'));
  });

  test('parses a true_false question with null options', () {
    final model = QuestionModel.fromJson(
      _questionJson(type: 'true_false', options: null, correctAnswer: 'True'),
    );

    expect(model.type, 'true_false');
    expect(model.options, isNull);
    expect(model.correctAnswer, 'True');
  });

  test('options absent from the response parses to null, not a crash', () {
    final json = _questionJson()..remove('options');

    final model = QuestionModel.fromJson(json);

    expect(model.options, isNull);
  });

  test('a malformed options value (not a list) throws', () {
    final json = _questionJson(options: 'not-a-list');

    expect(() => QuestionModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('an options list containing a non-string element throws', () {
    final json = _questionJson(options: ['Paris', 42, 'Berlin']);

    expect(() => QuestionModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('a malformed required id throws rather than silently defaulting', () {
    final json = _questionJson();
    json['id'] = 'not-an-int';

    expect(() => QuestionModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('a malformed required quiz_id throws', () {
    final json = _questionJson();
    json['quiz_id'] = null;

    expect(() => QuestionModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('a malformed required prompt throws', () {
    final json = _questionJson();
    json['prompt'] = null;

    expect(() => QuestionModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test(
    'an Organization-shaped response with correct_answer present parses it',
    () {
      final model = QuestionModel.fromJson(
        _questionJson(correctAnswer: 'Paris'),
      );

      expect(model.correctAnswer, 'Paris');
    },
  );

  test('a Student-shaped response with correct_answer explicitly null parses '
      'to null, not a crash — the backend strips this key entirely rather '
      'than sending an explicit null, but either shape must be safe', () {
    final json = _questionJson()..['correct_answer'] = null;

    final model = QuestionModel.fromJson(json);

    expect(model.correctAnswer, isNull);
  });

  test('a Student-shaped response with correct_answer entirely absent parses '
      'to null, not a crash', () {
    final json = _questionJson()..remove('correct_answer');

    final model = QuestionModel.fromJson(json);

    expect(model.correctAnswer, isNull);
  });

  test('a malformed required points throws', () {
    final json = _questionJson();
    json['points'] = 'not-an-int';

    expect(() => QuestionModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('a malformed required position throws', () {
    final json = _questionJson();
    json['position'] = null;

    expect(() => QuestionModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('createdAt/updatedAt are optional and parse safely when absent', () {
    final model = QuestionModel.fromJson(
      _questionJson(createdAt: null, updatedAt: null),
    );

    expect(model.createdAt, isNull);
    expect(model.updatedAt, isNull);
  });

  test('a malformed created_at string parses to null, not a crash', () {
    final model = QuestionModel.fromJson(
      _questionJson(createdAt: 'not-a-real-date'),
    );

    expect(model.createdAt, isNull);
  });

  test('an unknown type value is preserved as-is, not rejected', () {
    final model = QuestionModel.fromJson(
      _questionJson(type: 'some_future_type'),
    );

    expect(model.type, 'some_future_type');
  });
}
