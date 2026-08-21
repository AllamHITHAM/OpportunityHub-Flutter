import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/models/opportunity_model.dart';

Map<String, dynamic> _json({dynamic eligibleMajors = const []}) {
  return {
    'id': 1,
    'title': 'Backend Developer',
    'description': 'Great role.',
    'opportunity_type': 'job',
    'employment_type': 'full_time',
    'work_mode': 'remote',
    'experience_level': 'junior',
    'education_level': null,
    'field_of_study': 'Computer Science',
    'location': null,
    'salary_min': null,
    'salary_max': null,
    'application_deadline': null,
    'positions_available': 1,
    'status': 'open',
    'created_at': '2026-07-01T10:00:00.000000Z',
    'updated_at': '2026-07-01T10:00:00.000000Z',
    'eligible_majors': eligibleMajors,
  };
}

void main() {
  group('OpportunityModel.fromJson', () {
    test('parses the eligible_majors list', () {
      final opportunity = OpportunityModel.fromJson(
        _json(
          eligibleMajors: [
            'Computer Engineering',
            'Computer Science',
            'Software Engineering',
          ],
        ),
      );

      expect(opportunity.eligibleMajors, [
        'Computer Engineering',
        'Computer Science',
        'Software Engineering',
      ]);
    });

    test('an empty eligible_majors list parses to an empty list', () {
      final opportunity = OpportunityModel.fromJson(_json(eligibleMajors: []));

      expect(opportunity.eligibleMajors, isEmpty);
    });

    test('a missing eligible_majors key (legacy response) defaults to empty', () {
      final json = _json()..remove('eligible_majors');

      final opportunity = OpportunityModel.fromJson(json);

      expect(opportunity.eligibleMajors, isEmpty);
    });

    test('field_of_study is preserved alongside eligible_majors', () {
      final opportunity = OpportunityModel.fromJson(
        _json(eligibleMajors: ['Computer Science']),
      );

      expect(opportunity.fieldOfStudy, 'Computer Science');
      expect(opportunity.eligibleMajors, ['Computer Science']);
    });
  });
}
