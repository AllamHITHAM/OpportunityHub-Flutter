import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/core/utils/major_eligibility.dart';
import 'package:opportunityhub_flutter/models/candidate_model.dart';
import 'package:opportunityhub_flutter/models/opportunity_model.dart';

CandidateModel _candidate({String? major}) {
  return CandidateModel(
    id: 1,
    name: 'Jane Student',
    university: 'State University',
    major: major,
    graduationYear: 2026,
    educationVerificationStatus: 'not_submitted',
    skills: const [],
  );
}

OpportunityModel _opportunity({
  List<String> eligibleMajors = const [],
  String? fieldOfStudy,
}) {
  return OpportunityModel(
    id: 1,
    title: 'Backend Developer',
    description: 'Great role.',
    opportunityType: 'job',
    employmentType: 'full_time',
    workMode: 'remote',
    experienceLevel: 'junior',
    positionsAvailable: 1,
    status: 'open',
    fieldOfStudy: fieldOfStudy,
    eligibleMajors: eligibleMajors,
  );
}

void main() {
  group('normalizeMajor', () {
    test('trims, lowercases, and collapses whitespace', () {
      expect(normalizeMajor('  Civil   Engineering  '), 'civil engineering');
      expect(normalizeMajor('civil engineering'), 'civil engineering');
    });
  });

  group('isCandidateEligibleForOpportunity', () {
    test('accepts an exact eligible major', () {
      final candidate = _candidate(major: 'Computer Science');
      final opportunity = _opportunity(
        eligibleMajors: ['Computer Engineering', 'Computer Science'],
      );

      expect(isCandidateEligibleForOpportunity(candidate, opportunity), isTrue);
    });

    test('rejects a major not in the eligible list', () {
      final candidate = _candidate(major: 'Fine Arts');
      final opportunity = _opportunity(eligibleMajors: ['Computer Science']);

      expect(isCandidateEligibleForOpportunity(candidate, opportunity), isFalse);
    });

    test('matches case/whitespace-insensitively', () {
      final candidate = _candidate(major: '  civil   engineering ');
      final opportunity = _opportunity(eligibleMajors: ['Civil Engineering']);

      expect(isCandidateEligibleForOpportunity(candidate, opportunity), isTrue);
    });

    test('falls back to fieldOfStudy when there are no eligible majors', () {
      final candidate = _candidate(major: 'Civil Engineering');
      final opportunity = _opportunity(fieldOfStudy: 'civil engineering');

      expect(isCandidateEligibleForOpportunity(candidate, opportunity), isTrue);
    });

    test('rejects a fieldOfStudy mismatch', () {
      final candidate = _candidate(major: 'Fine Arts');
      final opportunity = _opportunity(fieldOfStudy: 'Civil Engineering');

      expect(isCandidateEligibleForOpportunity(candidate, opportunity), isFalse);
    });

    test('is unrestricted with neither eligible majors nor fieldOfStudy', () {
      final candidate = _candidate(major: 'Anything');
      final opportunity = _opportunity();

      expect(isCandidateEligibleForOpportunity(candidate, opportunity), isTrue);
    });

    test('an unrestricted opportunity accepts a null candidate major', () {
      final candidate = _candidate(major: null);
      final opportunity = _opportunity();

      expect(isCandidateEligibleForOpportunity(candidate, opportunity), isTrue);
    });

    test('a null candidate major is rejected by explicit eligible majors', () {
      final candidate = _candidate(major: null);
      final opportunity = _opportunity(eligibleMajors: ['Computer Science']);

      expect(isCandidateEligibleForOpportunity(candidate, opportunity), isFalse);
    });
  });
}
