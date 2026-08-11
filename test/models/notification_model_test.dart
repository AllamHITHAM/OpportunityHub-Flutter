// Direct unit tests for NotificationModel.fromJson.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/models/notification_model.dart';

Map<String, dynamic> _notificationJson({
  dynamic id = 1,
  dynamic userId = 7,
  dynamic title = 'Application shortlisted',
  dynamic message = 'Your application has been shortlisted.',
  dynamic priority = 'normal',
  dynamic type = 'application',
  dynamic actionUrl = '/student/applications/42',
  dynamic isRead = false,
  dynamic readAt,
  dynamic sentAt = '2026-08-10T09:00:00.000000Z',
  dynamic createdAt = '2026-08-10T09:00:00.000000Z',
  dynamic updatedAt = '2026-08-10T09:00:00.000000Z',
}) {
  return {
    'id': id,
    'user_id': userId,
    'title': title,
    'message': message,
    'priority': priority,
    'type': type,
    'action_url': actionUrl,
    'is_read': isRead,
    'read_at': readAt,
    'sent_at': sentAt,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}

void main() {
  test('parses a full unread notification response', () {
    final model = NotificationModel.fromJson(_notificationJson());

    expect(model.id, 1);
    expect(model.userId, 7);
    expect(model.title, 'Application shortlisted');
    expect(model.message, 'Your application has been shortlisted.');
    expect(model.priority, 'normal');
    expect(model.type, 'application');
    expect(model.actionUrl, '/student/applications/42');
    expect(model.isRead, isFalse);
    expect(model.readAt, isNull);
    expect(model.sentAt, DateTime.parse('2026-08-10T09:00:00.000000Z'));
    expect(model.createdAt, DateTime.parse('2026-08-10T09:00:00.000000Z'));
    expect(model.updatedAt, DateTime.parse('2026-08-10T09:00:00.000000Z'));
  });

  test('parses a read notification with read_at present', () {
    final model = NotificationModel.fromJson(
      _notificationJson(isRead: true, readAt: '2026-08-11T09:00:00.000000Z'),
    );

    expect(model.isRead, isTrue);
    expect(model.readAt, DateTime.parse('2026-08-11T09:00:00.000000Z'));
  });

  test('parses a minimal response with nullable fields all absent', () {
    final json = {
      'id': 1,
      'user_id': 7,
      'title': 'System notice',
      'message': 'Something happened.',
      'priority': 'low',
      'type': 'system',
      'action_url': null,
      'is_read': false,
      'read_at': null,
      'sent_at': null,
      'created_at': null,
      'updated_at': null,
    };

    final model = NotificationModel.fromJson(json);

    expect(model.id, 1);
    expect(model.actionUrl, isNull);
    expect(model.readAt, isNull);
    expect(model.sentAt, isNull);
    expect(model.createdAt, isNull);
    expect(model.updatedAt, isNull);
  });

  test('a malformed required id throws rather than silently defaulting', () {
    final json = _notificationJson(id: 'not-an-int');

    expect(() => NotificationModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('a missing required id throws', () {
    final json = _notificationJson(id: null);

    expect(() => NotificationModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('a missing required user_id throws', () {
    final json = _notificationJson(userId: null);

    expect(() => NotificationModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('a missing required title throws', () {
    final json = _notificationJson(title: null);

    expect(() => NotificationModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('a missing required message throws', () {
    final json = _notificationJson(message: null);

    expect(() => NotificationModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('a missing required priority throws', () {
    final json = _notificationJson(priority: null);

    expect(() => NotificationModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('a missing required type throws', () {
    final json = _notificationJson(type: null);

    expect(() => NotificationModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('a missing required is_read throws', () {
    final json = _notificationJson(isRead: null);

    expect(() => NotificationModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('a non-bool is_read throws', () {
    final json = _notificationJson(isRead: 'yes');

    expect(() => NotificationModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('an unrecognized type value is preserved as-is, not rejected', () {
    final model = NotificationModel.fromJson(
      _notificationJson(type: 'some_future_type'),
    );

    expect(model.type, 'some_future_type');
  });

  test('an unrecognized priority value is preserved as-is, not rejected', () {
    final model = NotificationModel.fromJson(
      _notificationJson(priority: 'urgent'),
    );

    expect(model.priority, 'urgent');
  });

  test('an invalid sent_at string parses to null, not a crash', () {
    final model = NotificationModel.fromJson(
      _notificationJson(sentAt: 'not-a-real-date'),
    );

    expect(model.sentAt, isNull);
  });

  test('an invalid read_at string parses to null, not a crash', () {
    final model = NotificationModel.fromJson(
      _notificationJson(readAt: 'not-a-real-date'),
    );

    expect(model.readAt, isNull);
  });

  test('extra unrecognized fields in the response are ignored', () {
    final json = _notificationJson();
    json['some_future_field'] = 'unexpected value';

    final model = NotificationModel.fromJson(json);

    expect(model.id, 1);
    expect(model.title, 'Application shortlisted');
  });

  test('copyWithRead marks the notification read and sets readAt, leaving '
      'everything else unchanged', () {
    final original = NotificationModel.fromJson(_notificationJson());
    final readAt = DateTime.parse('2026-08-12T10:00:00.000000Z');

    final updated = original.copyWithRead(readAt: readAt);

    expect(updated.isRead, isTrue);
    expect(updated.readAt, readAt);
    expect(updated.id, original.id);
    expect(updated.userId, original.userId);
    expect(updated.title, original.title);
    expect(updated.message, original.message);
    expect(updated.priority, original.priority);
    expect(updated.type, original.type);
    expect(updated.actionUrl, original.actionUrl);
    expect(updated.sentAt, original.sentAt);
    expect(updated.createdAt, original.createdAt);
    expect(updated.updatedAt, original.updatedAt);
  });
}
