// Direct unit tests for InterviewCreateInput.toJson.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/features/assessments/data/interview_create_input.dart';

void main() {
  test('produces the correct backend field names', () {
    final input = InterviewCreateInput(
      interviewType: 'online',
      scheduledAt: DateTime(2026, 8, 10, 10),
      durationMinutes: 60,
      meetingLink: 'https://meet.example.com/room',
      interviewerName: 'Jane Recruiter',
      interviewerEmail: 'jane@example.com',
      notes: 'Bring a laptop.',
    );

    final json = input.toJson();

    expect(
      json.keys,
      containsAll(<String>[
        'interview_type',
        'scheduled_at',
        'duration_minutes',
        'meeting_link',
        'interviewer_name',
        'interviewer_email',
        'notes',
      ]),
    );
    expect(json['interview_type'], 'online');
    expect(json['duration_minutes'], 60);
    expect(json['meeting_link'], 'https://meet.example.com/room');
    expect(json['interviewer_name'], 'Jane Recruiter');
    expect(json['interviewer_email'], 'jane@example.com');
    expect(json['notes'], 'Bring a laptop.');
  });

  test('formats scheduled_at as exactly YYYY-MM-DD HH:mm:ss', () {
    final input = InterviewCreateInput(
      interviewType: 'phone',
      scheduledAt: DateTime(2026, 8, 5, 9, 5, 3),
    );

    expect(input.toJson()['scheduled_at'], '2026-08-05 09:05:03');
  });

  test('zero-pads every component of scheduled_at', () {
    final input = InterviewCreateInput(
      interviewType: 'phone',
      scheduledAt: DateTime(2026, 1, 2, 3, 4, 5),
    );

    expect(input.toJson()['scheduled_at'], '2026-01-02 03:04:05');
  });

  test('never uses raw DateTime.toString() (no microseconds suffix)', () {
    final input = InterviewCreateInput(
      interviewType: 'phone',
      scheduledAt: DateTime(2026, 8, 10, 10),
    );

    final formatted = input.toJson()['scheduled_at'] as String;
    expect(formatted, isNot(contains('.')));
    expect(formatted.length, 19); // "YYYY-MM-DD HH:mm:ss"
  });

  test('omits null optional fields entirely', () {
    final input = InterviewCreateInput(
      interviewType: 'phone',
      scheduledAt: DateTime(2026, 8, 10, 10),
    );

    final json = input.toJson();

    expect(json.containsKey('duration_minutes'), isFalse);
    expect(json.containsKey('meeting_link'), isFalse);
    expect(json.containsKey('location'), isFalse);
    expect(json.containsKey('interviewer_name'), isFalse);
    expect(json.containsKey('interviewer_email'), isFalse);
    expect(json.containsKey('notes'), isFalse);
    // Required fields are always present.
    expect(json.containsKey('interview_type'), isTrue);
    expect(json.containsKey('scheduled_at'), isTrue);
  });

  test('omits blank/whitespace-only optional strings entirely', () {
    final input = InterviewCreateInput(
      interviewType: 'onsite',
      scheduledAt: DateTime(2026, 8, 10, 10),
      location: '   ',
      interviewerName: '',
      interviewerEmail: '\t',
      notes: '  \n  ',
    );

    final json = input.toJson();

    expect(json.containsKey('location'), isFalse);
    expect(json.containsKey('interviewer_name'), isFalse);
    expect(json.containsKey('interviewer_email'), isFalse);
    expect(json.containsKey('notes'), isFalse);
  });

  test('trims optional text values before sending', () {
    final input = InterviewCreateInput(
      interviewType: 'onsite',
      scheduledAt: DateTime(2026, 8, 10, 10),
      location: '  221B Baker Street  ',
      interviewerName: '  Jane Recruiter  ',
      interviewerEmail: '  jane@example.com  ',
      notes: '  Bring a laptop.  ',
    );

    final json = input.toJson();

    expect(json['location'], '221B Baker Street');
    expect(json['interviewer_name'], 'Jane Recruiter');
    expect(json['interviewer_email'], 'jane@example.com');
    expect(json['notes'], 'Bring a laptop.');
  });

  test('an onsite input never leaks a meeting_link key', () {
    final input = InterviewCreateInput(
      interviewType: 'onsite',
      scheduledAt: DateTime(2026, 8, 10, 10),
      location: '221B Baker Street',
      meetingLink: null,
    );

    expect(input.toJson().containsKey('meeting_link'), isFalse);
  });

  test('an online input never leaks a location key', () {
    final input = InterviewCreateInput(
      interviewType: 'online',
      scheduledAt: DateTime(2026, 8, 10, 10),
      meetingLink: 'https://meet.example.com/room',
      location: null,
    );

    expect(input.toJson().containsKey('location'), isFalse);
  });

  test('a phone input carries neither meeting_link nor location', () {
    final input = InterviewCreateInput(
      interviewType: 'phone',
      scheduledAt: DateTime(2026, 8, 10, 10),
      meetingLink: null,
      location: null,
    );

    final json = input.toJson();
    expect(json.containsKey('meeting_link'), isFalse);
    expect(json.containsKey('location'), isFalse);
  });
}
