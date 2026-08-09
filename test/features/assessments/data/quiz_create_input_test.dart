// Direct unit tests for QuizCreateInput.toJson.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/features/assessments/data/quiz_create_input.dart';

void main() {
  test('builds the exact snake_case request body', () {
    final input = QuizCreateInput(
      title: 'Backend Fundamentals',
      instructions: 'Choose the best answer.',
      timeLimitMinutes: 30,
      passingScore: 70,
    );

    final json = input.toJson();

    expect(json, {
      'title': 'Backend Fundamentals',
      'passing_score': 70,
      'time_limit_minutes': 30,
      'instructions': 'Choose the best answer.',
    });
  });

  test('trims title and instructions', () {
    final input = QuizCreateInput(
      title: '  Backend Fundamentals  ',
      instructions: '  Choose the best answer.  ',
      passingScore: 70,
    );

    final json = input.toJson();

    expect(json['title'], 'Backend Fundamentals');
    expect(json['instructions'], 'Choose the best answer.');
  });

  test('omits instructions when null', () {
    final input = QuizCreateInput(
      title: 'Backend Fundamentals',
      passingScore: 70,
    );

    final json = input.toJson();

    expect(json.containsKey('instructions'), isFalse);
  });

  test('omits instructions when empty/whitespace-only', () {
    final input = QuizCreateInput(
      title: 'Backend Fundamentals',
      instructions: '   ',
      passingScore: 70,
    );

    final json = input.toJson();

    expect(json.containsKey('instructions'), isFalse);
  });

  test('omits time_limit_minutes when null', () {
    final input = QuizCreateInput(
      title: 'Backend Fundamentals',
      passingScore: 70,
    );

    final json = input.toJson();

    expect(json.containsKey('time_limit_minutes'), isFalse);
  });

  test('passing_score of 0 is sent as a real 0, not omitted', () {
    final input = QuizCreateInput(
      title: 'Backend Fundamentals',
      passingScore: 0,
    );

    final json = input.toJson();

    expect(json['passing_score'], 0);
  });
}
