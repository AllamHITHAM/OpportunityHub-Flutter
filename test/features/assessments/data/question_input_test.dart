// Direct unit tests for QuestionInput.toJson.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/features/assessments/data/question_input.dart';

void main() {
  test('builds the exact multiple_choice request body', () {
    final input = QuestionInput(
      prompt: 'What is the capital of France?',
      type: 'multiple_choice',
      options: ['Paris', 'London', 'Berlin'],
      correctAnswer: 'Paris',
      points: 2,
      position: 1,
    );

    final json = input.toJson();

    expect(json, {
      'prompt': 'What is the capital of France?',
      'type': 'multiple_choice',
      'correct_answer': 'Paris',
      'points': 2,
      'position': 1,
      'options': ['Paris', 'London', 'Berlin'],
    });
  });

  test('builds the exact true_false request body, omitting options', () {
    final input = QuestionInput(
      prompt: 'The sky is blue.',
      type: 'true_false',
      correctAnswer: 'True',
      points: 1,
      position: 0,
    );

    final json = input.toJson();

    expect(json, {
      'prompt': 'The sky is blue.',
      'type': 'true_false',
      'correct_answer': 'True',
      'points': 1,
      'position': 0,
    });
    expect(json.containsKey('options'), isFalse);
  });

  test('true_false omits options even if options were provided', () {
    final input = QuestionInput(
      prompt: 'The sky is blue.',
      type: 'true_false',
      options: ['should', 'be ignored'],
      correctAnswer: 'True',
      points: 1,
      position: 0,
    );

    final json = input.toJson();

    expect(json.containsKey('options'), isFalse);
  });

  test('trims prompt, correct_answer, and each option', () {
    final input = QuestionInput(
      prompt: '  What is the capital of France?  ',
      type: 'multiple_choice',
      options: ['  Paris  ', ' London', 'Berlin '],
      correctAnswer: '  Paris  ',
      points: 1,
      position: 0,
    );

    final json = input.toJson();

    expect(json['prompt'], 'What is the capital of France?');
    expect(json['correct_answer'], 'Paris');
    expect(json['options'], ['Paris', 'London', 'Berlin']);
  });

  test('multiple_choice with null options sends an empty options list', () {
    final input = QuestionInput(
      prompt: 'What is the capital of France?',
      type: 'multiple_choice',
      correctAnswer: 'Paris',
      points: 1,
      position: 0,
    );

    final json = input.toJson();

    expect(json['options'], isEmpty);
  });
}
