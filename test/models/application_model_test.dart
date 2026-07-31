// Direct unit tests for ApplicationModel.fromJson, covering both the
// student-facing shape (no `student_profile`, always an `opportunity`) and
// the organization-facing shape (`student_profile`/`student_profile.user`
// present, `opportunity` sometimes absent — see the applicants-list
// endpoint, which the backend doesn't eager-load it on).

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/models/application_model.dart';

Map<String, dynamic> _opportunityJson({int id = 5}) {
  return {
    'id': id,
    'title': 'Backend Developer',
    'description': 'Great role.',
    'opportunity_type': 'job',
    'employment_type': 'full_time',
    'work_mode': 'remote',
    'experience_level': 'junior',
    'education_level': null,
    'field_of_study': null,
    'location': null,
    'salary_min': null,
    'salary_max': null,
    'application_deadline': null,
    'positions_available': 1,
    'status': 'open',
    'created_at': '2026-07-01T10:00:00.000000Z',
    'updated_at': '2026-07-01T10:00:00.000000Z',
  };
}

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

Map<String, dynamic> _baseApplicationJson({
  int id = 1,
  int opportunityId = 5,
  int cvId = 2,
  String status = 'pending',
  dynamic matchScore,
  Map<String, dynamic>? opportunity,
  Map<String, dynamic>? studentProfile,
}) {
  return {
    'id': id,
    'student_id': 1,
    'opportunity_id': opportunityId,
    'cv_id': cvId,
    'status': status,
    'match_score': matchScore,
    'cover_letter': null,
    'applied_at': '2026-07-20T09:00:00.000000Z',
    'reviewed_at': null,
    'created_at': '2026-07-20T09:00:00.000000Z',
    'updated_at': '2026-07-20T09:00:00.000000Z',
    'cv': _cvJson(id: cvId),
    'opportunity': ?opportunity,
    'student_profile': ?studentProfile,
  };
}

void main() {
  group('opportunity', () {
    test(
      'is parsed when present (student-facing / organization-details shapes)',
      () {
        final model = ApplicationModel.fromJson(
          _baseApplicationJson(opportunity: _opportunityJson(id: 5)),
        );

        expect(model.opportunity, isNotNull);
        expect(model.opportunity!.id, 5);
        expect(model.opportunity!.title, 'Backend Developer');
      },
    );

    test('is null when absent (the applicants-list shape, which omits it)', () {
      final model = ApplicationModel.fromJson(_baseApplicationJson());

      expect(model.opportunity, isNull);
      // opportunityId (the raw foreign key) is always present regardless.
      expect(model.opportunityId, 5);
    });
  });

  group('applicant (student_profile / student_profile.user)', () {
    test('is null when student_profile is absent (student-facing shape)', () {
      final model = ApplicationModel.fromJson(_baseApplicationJson());

      expect(model.applicant, isNull);
    });

    test('is populated with name/email from the nested user when present', () {
      final model = ApplicationModel.fromJson(
        _baseApplicationJson(
          studentProfile: {
            'id': 1,
            'user_id': 10,
            'phone': '0599111111',
            'university': 'An-Najah National University',
            'major': 'Software Engineering',
            'graduation_year': 2027,
            'bio': 'Backend Laravel Developer',
            'profile_image': null,
            'user': {
              'id': 10,
              'name': 'Jane Student',
              'email': 'jane@example.com',
            },
          },
        ),
      );

      expect(model.applicant, isNotNull);
      expect(model.applicant!.id, 1);
      expect(model.applicant!.userId, 10);
      expect(model.applicant!.name, 'Jane Student');
      expect(model.applicant!.email, 'jane@example.com');
      expect(model.applicant!.phone, '0599111111');
      expect(model.applicant!.university, 'An-Najah National University');
      expect(model.applicant!.major, 'Software Engineering');
      expect(model.applicant!.graduationYear, 2027);
      expect(model.applicant!.bio, 'Backend Laravel Developer');
    });

    test('name/email are null when student_profile has no nested user', () {
      final model = ApplicationModel.fromJson(
        _baseApplicationJson(
          studentProfile: {
            'id': 1,
            'user_id': 10,
            'phone': null,
            'university': 'State University',
            'major': null,
            'graduation_year': null,
            'bio': null,
            'profile_image': null,
          },
        ),
      );

      expect(model.applicant, isNotNull);
      expect(model.applicant!.name, isNull);
      expect(model.applicant!.email, isNull);
      expect(model.applicant!.university, 'State University');
    });

    test('every student_profile field is independently nullable', () {
      final model = ApplicationModel.fromJson(
        _baseApplicationJson(
          studentProfile: {
            'id': 1,
            'user_id': null,
            'phone': null,
            'university': null,
            'major': null,
            'graduation_year': null,
            'bio': null,
            'profile_image': null,
            'user': {'id': 10, 'name': null, 'email': null},
          },
        ),
      );

      final applicant = model.applicant!;
      expect(applicant.userId, isNull);
      expect(applicant.phone, isNull);
      expect(applicant.university, isNull);
      expect(applicant.major, isNull);
      expect(applicant.graduationYear, isNull);
      expect(applicant.bio, isNull);
      expect(applicant.profileImage, isNull);
      expect(applicant.name, isNull);
      expect(applicant.email, isNull);
    });
  });

  group('match_score', () {
    test('parses a decimal serialized as a string', () {
      final model = ApplicationModel.fromJson(
        _baseApplicationJson(matchScore: '68.75'),
      );

      expect(model.matchScore, 68.75);
      expect(model.matchScore, isA<double>());
    });

    test('parses a raw number', () {
      final model = ApplicationModel.fromJson(
        _baseApplicationJson(matchScore: 68.75),
      );

      expect(model.matchScore, 68.75);
    });

    test('is null when absent', () {
      final model = ApplicationModel.fromJson(_baseApplicationJson());

      expect(model.matchScore, isNull);
    });
  });

  test('cv is always required and parsed', () {
    final model = ApplicationModel.fromJson(_baseApplicationJson());

    expect(model.cv.id, 2);
    expect(model.cv.title, 'Main CV');
  });

  test('cover_letter and reviewed_at are nullable', () {
    final model = ApplicationModel.fromJson(_baseApplicationJson());

    expect(model.coverLetter, isNull);
    expect(model.reviewedAt, isNull);
  });
}
