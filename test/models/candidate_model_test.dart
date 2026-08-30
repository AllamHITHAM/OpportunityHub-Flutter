import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/models/candidate_model.dart';

Map<String, dynamic> _json({
  bool? alreadyApplied,
  bool? alreadyInvited,
  List<dynamic>? skills,
}) {
  return {
    'id': 1,
    'name': 'Omar Hassan',
    'university': 'State University',
    'major': 'Computer Science',
    'graduation_year': 2026,
    'education_verification_status': 'verified',
    'skills': skills ?? [],
    'already_applied': ?alreadyApplied,
    'already_invited': ?alreadyInvited,
  };
}

void main() {
  group('CandidateModel.fromJson', () {
    test('parses every safe field', () {
      final candidate = CandidateModel.fromJson(_json());

      expect(candidate.id, 1);
      expect(candidate.name, 'Omar Hassan');
      expect(candidate.university, 'State University');
      expect(candidate.major, 'Computer Science');
      expect(candidate.graduationYear, 2026);
      expect(candidate.educationVerificationStatus, 'verified');
    });

    test('nullable fields parse as null when missing', () {
      final json = _json()
        ..remove('university')
        ..remove('major')
        ..remove('graduation_year');

      final candidate = CandidateModel.fromJson(json);

      expect(candidate.university, isNull);
      expect(candidate.major, isNull);
      expect(candidate.graduationYear, isNull);
    });

    test(
      'parses profile_photo_url (Student Profile Photo phase), null when '
      'absent',
      () {
        final withPhoto = CandidateModel.fromJson({
          ..._json(),
          'profile_photo_url': 'https://cdn.example.com/photos/omar.png',
        });
        final withoutPhoto = CandidateModel.fromJson(_json());

        expect(
          withPhoto.photoUrl,
          'https://cdn.example.com/photos/omar.png',
        );
        expect(withoutPhoto.photoUrl, isNull);
      },
    );

    test(
      'education_verification_status defaults to not_submitted when missing',
      () {
        final json = _json()..remove('education_verification_status');

        final candidate = CandidateModel.fromJson(json);

        expect(candidate.educationVerificationStatus, 'not_submitted');
      },
    );

    test('parses skills', () {
      final candidate = CandidateModel.fromJson(
        _json(
          skills: [
            {'name': 'PHP', 'source': 'manual'},
            {'name': 'Laravel', 'source': 'cv_ai'},
          ],
        ),
      );

      expect(candidate.skills, hasLength(2));
      expect(candidate.skills[0].name, 'PHP');
      expect(candidate.skills[0].evidenceLabel, 'Self-declared');
      expect(candidate.skills[1].name, 'Laravel');
      expect(candidate.skills[1].evidenceLabel, 'CV-supported');
    });

    test('an empty skills list parses to an empty list', () {
      final candidate = CandidateModel.fromJson(_json(skills: []));

      expect(candidate.skills, isEmpty);
    });

    test(
      'already_applied/already_invited are null when the backend omits them',
      () {
        final candidate = CandidateModel.fromJson(_json());

        expect(candidate.alreadyApplied, isNull);
        expect(candidate.alreadyInvited, isNull);
      },
    );

    test('already_applied/already_invited parse when present', () {
      final candidate = CandidateModel.fromJson(
        _json(alreadyApplied: true, alreadyInvited: false),
      );

      expect(candidate.alreadyApplied, isTrue);
      expect(candidate.alreadyInvited, isFalse);
    });
  });
}
