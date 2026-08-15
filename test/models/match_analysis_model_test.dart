// Direct unit tests for MatchAnalysisModel.fromJson.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/models/match_analysis_model.dart';

Map<String, dynamic> _analysisJson({
  dynamic overallMatchScore = 87,
  dynamic skillsMatchScore = 90,
  dynamic fieldMatchScore = 100,
  dynamic experienceMatchScore = 66.67,
  dynamic strengths = const ['Matches required skill: Laravel'],
  dynamic weaknesses = const ['Missing preferred skill: Docker'],
  dynamic recommendation = 'Strong candidate, recommended for interview.',
}) {
  return {
    'overall_match_score': overallMatchScore,
    'skills_match_score': skillsMatchScore,
    'field_match_score': fieldMatchScore,
    'experience_match_score': experienceMatchScore,
    'strengths': strengths,
    'weaknesses': weaknesses,
    'recommendation': recommendation,
  };
}

void main() {
  test('parses a full valid analysis response', () {
    final model = MatchAnalysisModel.fromJson(_analysisJson());

    expect(model.overallMatchScore, 87.0);
    expect(model.skillsMatchScore, 90.0);
    expect(model.fieldMatchScore, 100.0);
    expect(model.experienceMatchScore, 66.67);
    expect(model.strengths, ['Matches required skill: Laravel']);
    expect(model.weaknesses, ['Missing preferred skill: Docker']);
    expect(
      model.recommendation,
      'Strong candidate, recommended for interview.',
    );
  });

  test('a whole-number overall score parses correctly (PHP emits it as an '
      'int, not a float, when there is no fractional part)', () {
    final model = MatchAnalysisModel.fromJson(
      _analysisJson(overallMatchScore: 60),
    );

    expect(model.overallMatchScore, isA<double>());
    expect(model.overallMatchScore, 60.0);
  });

  test('each factor score is independently nullable (unavailable factor)', () {
    final model = MatchAnalysisModel.fromJson(
      _analysisJson(
        skillsMatchScore: null,
        fieldMatchScore: null,
        experienceMatchScore: 50,
      ),
    );

    expect(model.skillsMatchScore, isNull);
    expect(model.fieldMatchScore, isNull);
    expect(model.experienceMatchScore, 50.0);
  });

  test('all three factor scores can be simultaneously unavailable', () {
    final model = MatchAnalysisModel.fromJson(
      _analysisJson(
        skillsMatchScore: null,
        fieldMatchScore: null,
        experienceMatchScore: null,
      ),
    );

    expect(model.skillsMatchScore, isNull);
    expect(model.fieldMatchScore, isNull);
    expect(model.experienceMatchScore, isNull);
    // The overall score is still a real, calculated value even when every
    // factor is unavailable -- see MatchAnalysisModel's own doc comment.
    expect(model.overallMatchScore, isA<double>());
  });

  test('a 0 overall score is preserved, not treated as missing', () {
    final model = MatchAnalysisModel.fromJson(
      _analysisJson(overallMatchScore: 0),
    );

    expect(model.overallMatchScore, 0.0);
  });

  test('a 0 factor score is preserved, not treated as unavailable', () {
    final model = MatchAnalysisModel.fromJson(
      _analysisJson(skillsMatchScore: 0),
    );

    expect(model.skillsMatchScore, 0.0);
  });

  test('a 100 score parses correctly for both overall and factor scores', () {
    final model = MatchAnalysisModel.fromJson(
      _analysisJson(
        overallMatchScore: 100,
        skillsMatchScore: 100,
        fieldMatchScore: 100,
        experienceMatchScore: 100,
      ),
    );

    expect(model.overallMatchScore, 100.0);
    expect(model.skillsMatchScore, 100.0);
    expect(model.fieldMatchScore, 100.0);
    expect(model.experienceMatchScore, 100.0);
  });

  test('strengths and weaknesses default to an empty list when missing', () {
    final json = _analysisJson();
    json.remove('strengths');
    json.remove('weaknesses');

    final model = MatchAnalysisModel.fromJson(json);

    expect(model.strengths, isEmpty);
    expect(model.weaknesses, isEmpty);
  });

  test('strengths/weaknesses can genuinely be empty lists', () {
    final model = MatchAnalysisModel.fromJson(
      _analysisJson(strengths: [], weaknesses: []),
    );

    expect(model.strengths, isEmpty);
    expect(model.weaknesses, isEmpty);
  });

  test(
    'a malformed strengths value (not a list) degrades to empty, no crash',
    () {
      final model = MatchAnalysisModel.fromJson(
        _analysisJson(strengths: 'not a list'),
      );

      expect(model.strengths, isEmpty);
    },
  );

  test(
    'a malformed weaknesses value (not a list) degrades to empty, no crash',
    () {
      final model = MatchAnalysisModel.fromJson(_analysisJson(weaknesses: 42));

      expect(model.weaknesses, isEmpty);
    },
  );

  test(
    'non-string entries inside strengths/weaknesses are filtered out safely',
    () {
      final model = MatchAnalysisModel.fromJson(
        _analysisJson(
          strengths: ['Matches required skill: Laravel', 42, null],
          weaknesses: [null, 'Missing preferred skill: Docker'],
        ),
      );

      expect(model.strengths, ['Matches required skill: Laravel']);
      expect(model.weaknesses, ['Missing preferred skill: Docker']);
    },
  );

  test('recommendation is nullable', () {
    final model = MatchAnalysisModel.fromJson(
      _analysisJson(recommendation: null),
    );

    expect(model.recommendation, isNull);
  });

  test('a missing required overall_match_score throws', () {
    final json = _analysisJson();
    json.remove('overall_match_score');

    expect(() => MatchAnalysisModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('a malformed (non-numeric) overall_match_score throws', () {
    final json = _analysisJson(overallMatchScore: 'not-a-number');

    expect(() => MatchAnalysisModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('a null overall_match_score throws rather than silently defaulting', () {
    final json = _analysisJson(overallMatchScore: null);

    expect(() => MatchAnalysisModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('a malformed (non-numeric) skills_match_score throws', () {
    final json = _analysisJson(skillsMatchScore: 'not-a-number');

    expect(() => MatchAnalysisModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('extra unrecognized fields in the response are ignored', () {
    final json = _analysisJson();
    json['some_future_field'] = 'unexpected value';

    final model = MatchAnalysisModel.fromJson(json);

    expect(model.overallMatchScore, 87.0);
  });

  test('there is no education field parsed or exposed by this model', () {
    // Structural guard: the backend v1.1 formula (Phase 8A-2) has no
    // education factor at all -- this model must never grow one back in,
    // even if a stray `education_match_score` key appeared in a response.
    final json = _analysisJson();
    json['education_match_score'] = 50;

    final model = MatchAnalysisModel.fromJson(json);

    expect(model.overallMatchScore, 87.0);
    // No `educationMatchScore` field/getter exists on this model at all --
    // this test would fail to compile if one were ever added.
  });
}
