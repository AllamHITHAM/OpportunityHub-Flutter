// Direct unit tests for InterviewModel.fromJson. InterviewModel is
// deliberately endpoint-agnostic (see the model's own doc comment) so these
// tests exercise its parsing purely against raw JSON shapes, never against
// "legacy" vs. "generic" framing.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/models/interview_model.dart';

Map<String, dynamic> _interviewJson({
  int id = 1,
  int assessmentId = 1,
  String interviewType = 'online',
  dynamic scheduledAt = '2026-08-10T10:00:00.000000Z',
  dynamic durationMinutes = 60,
  String? meetingLink = 'https://meet.example.com/room',
  String? location,
  String? contactPhone,
  String? interviewerName = 'Jane Recruiter',
  String? interviewerEmail = 'jane@example.com',
  String? notes = 'Bring a laptop.',
  String status = 'scheduled',
  String decision = 'pending',
  dynamic rating,
  String? companyFeedback,
  dynamic completedAt,
}) {
  return {
    'id': id,
    'assessment_id': assessmentId,
    'interview_type': interviewType,
    'scheduled_at': scheduledAt,
    'duration_minutes': durationMinutes,
    'meeting_link': meetingLink,
    'location': location,
    'contact_phone': contactPhone,
    'interviewer_name': interviewerName,
    'interviewer_email': interviewerEmail,
    'notes': notes,
    'status': status,
    'decision': decision,
    'rating': rating,
    'company_feedback': companyFeedback,
    'completed_at': completedAt,
  };
}

void main() {
  test('parses a full online interview response', () {
    final interview = InterviewModel.fromJson(_interviewJson());

    expect(interview.id, 1);
    expect(interview.assessmentId, 1);
    expect(interview.interviewType, 'online');
    expect(
      interview.scheduledAt,
      DateTime.parse('2026-08-10T10:00:00.000000Z'),
    );
    expect(interview.durationMinutes, 60);
    expect(interview.meetingLink, 'https://meet.example.com/room');
    expect(interview.location, isNull);
    expect(interview.interviewerName, 'Jane Recruiter');
    expect(interview.interviewerEmail, 'jane@example.com');
    expect(interview.notes, 'Bring a laptop.');
    expect(interview.status, 'scheduled');
    expect(interview.decision, 'pending');
  });

  test('parses an onsite interview response', () {
    final interview = InterviewModel.fromJson(
      _interviewJson(
        interviewType: 'onsite',
        meetingLink: null,
        location: '221B Baker Street',
      ),
    );

    expect(interview.interviewType, 'onsite');
    expect(interview.meetingLink, isNull);
    expect(interview.location, '221B Baker Street');
  });

  test('parses a phone interview response', () {
    final interview = InterviewModel.fromJson(
      _interviewJson(
        interviewType: 'phone',
        meetingLink: null,
        location: null,
        contactPhone: '+1 555-0100',
      ),
    );

    expect(interview.interviewType, 'phone');
    expect(interview.meetingLink, isNull);
    expect(interview.location, isNull);
    expect(interview.contactPhone, '+1 555-0100');
  });

  test(
    'a missing contact_phone key (legacy response, Phase Final-QA-1) parses to null, not a crash',
    () {
      final json = _interviewJson(interviewType: 'phone')
        ..remove('contact_phone');

      final interview = InterviewModel.fromJson(json);

      expect(interview.contactPhone, isNull);
    },
  );

  test('all optional fields null parse safely', () {
    final interview = InterviewModel.fromJson(
      _interviewJson(
        scheduledAt: null,
        durationMinutes: null,
        meetingLink: null,
        location: null,
        contactPhone: null,
        interviewerName: null,
        interviewerEmail: null,
        notes: null,
        rating: null,
        companyFeedback: null,
        completedAt: null,
      ),
    );

    expect(interview.scheduledAt, isNull);
    expect(interview.durationMinutes, isNull);
    expect(interview.meetingLink, isNull);
    expect(interview.location, isNull);
    expect(interview.contactPhone, isNull);
    expect(interview.interviewerName, isNull);
    expect(interview.interviewerEmail, isNull);
    expect(interview.notes, isNull);
    expect(interview.rating, isNull);
    expect(interview.companyFeedback, isNull);
    expect(interview.completedAt, isNull);
  });

  test('duration and rating parse from a real int', () {
    final interview = InterviewModel.fromJson(
      _interviewJson(durationMinutes: 45, rating: 5),
    );

    expect(interview.durationMinutes, 45);
    expect(interview.rating, 5);
  });

  test('duration and rating parse from a numeric string', () {
    final interview = InterviewModel.fromJson(
      _interviewJson(durationMinutes: '45', rating: '5'),
    );

    expect(interview.durationMinutes, 45);
    expect(interview.rating, 5);
  });

  test('a non-numeric duration/rating string parses to null, not a crash', () {
    final interview = InterviewModel.fromJson(
      _interviewJson(durationMinutes: 'not-a-number', rating: 'nope'),
    );

    expect(interview.durationMinutes, isNull);
    expect(interview.rating, isNull);
  });

  test('malformed scheduled_at/completed_at parse to null, not a crash', () {
    final interview = InterviewModel.fromJson(
      _interviewJson(
        scheduledAt: 'not-a-real-date',
        completedAt: 'also-not-a-date',
      ),
    );

    expect(interview.scheduledAt, isNull);
    expect(interview.completedAt, isNull);
  });

  test('completed_at parses when the interview has finished', () {
    final interview = InterviewModel.fromJson(
      _interviewJson(
        status: 'completed',
        decision: 'passed',
        companyFeedback: 'Great candidate.',
        rating: 5,
        completedAt: '2026-08-10T11:00:00.000000Z',
      ),
    );

    expect(interview.status, 'completed');
    expect(interview.decision, 'passed');
    expect(interview.companyFeedback, 'Great candidate.');
    expect(
      interview.completedAt,
      DateTime.parse('2026-08-10T11:00:00.000000Z'),
    );
  });

  test(
    'ignores an unknown nested application key (the legacy backward-compat shape)',
    () {
      final json = _interviewJson();
      json['application'] = {'id': 5, 'status': 'interview_scheduled'};

      final interview = InterviewModel.fromJson(json);

      expect(interview.id, 1);
      expect(interview.assessmentId, 1);
    },
  );

  test('an unknown status value is preserved as-is, not rejected', () {
    final interview = InterviewModel.fromJson(
      _interviewJson(status: 'some_future_status'),
    );

    expect(interview.status, 'some_future_status');
  });

  test('an unknown decision value is preserved as-is, not rejected', () {
    final interview = InterviewModel.fromJson(
      _interviewJson(decision: 'some_future_decision'),
    );

    expect(interview.decision, 'some_future_decision');
  });

  test('a missing decision key (the Student-facing response shape) parses to '
      'null, not a crash', () {
    final json = _interviewJson()..remove('decision');

    final interview = InterviewModel.fromJson(json);

    expect(interview.decision, isNull);
  });

  test('a malformed required id throws rather than silently defaulting', () {
    final json = _interviewJson();
    json['id'] = 'not-an-int';

    expect(() => InterviewModel.fromJson(json), throwsA(isA<TypeError>()));
  });
}
