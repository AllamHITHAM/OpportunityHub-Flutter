// Direct unit tests for OfferModel.fromJson.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/models/offer_model.dart';

Map<String, dynamic> _offerJson({
  dynamic id = 1,
  dynamic applicationId = 5,
  dynamic title = 'Backend Engineer',
  dynamic salaryAmount = '90000.00',
  dynamic salaryCurrency = 'USD',
  dynamic salaryPeriod = 'yearly',
  dynamic startDate = '2026-09-01T00:00:00.000000Z',
  dynamic message = 'We would love to have you join the team.',
  dynamic status = 'sent',
  dynamic sentAt = '2026-08-10T09:00:00.000000Z',
  dynamic respondedAt,
  dynamic createdAt = '2026-08-10T09:00:00.000000Z',
  dynamic updatedAt = '2026-08-10T09:00:00.000000Z',
}) {
  return {
    'id': id,
    'application_id': applicationId,
    'title': title,
    'salary_amount': salaryAmount,
    'salary_currency': salaryCurrency,
    'salary_period': salaryPeriod,
    'start_date': startDate,
    'message': message,
    'status': status,
    'sent_at': sentAt,
    'responded_at': respondedAt,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}

void main() {
  test('parses a full Offer response', () {
    final model = OfferModel.fromJson(_offerJson());

    expect(model.id, 1);
    expect(model.applicationId, 5);
    expect(model.title, 'Backend Engineer');
    expect(model.salaryAmount, '90000.00');
    expect(model.salaryCurrency, 'USD');
    expect(model.salaryPeriod, 'yearly');
    expect(model.startDate, DateTime.parse('2026-09-01T00:00:00.000000Z'));
    expect(model.message, 'We would love to have you join the team.');
    expect(model.status, 'sent');
    expect(model.sentAt, DateTime.parse('2026-08-10T09:00:00.000000Z'));
    expect(model.respondedAt, isNull);
    expect(model.createdAt, DateTime.parse('2026-08-10T09:00:00.000000Z'));
    expect(model.updatedAt, DateTime.parse('2026-08-10T09:00:00.000000Z'));
  });

  test('parses a minimal Offer response with only required fields', () {
    final json = {
      'id': 1,
      'application_id': 5,
      'title': null,
      'salary_amount': null,
      'salary_currency': null,
      'salary_period': null,
      'start_date': null,
      'message': null,
      'status': 'sent',
      'sent_at': null,
      'responded_at': null,
      'created_at': null,
      'updated_at': null,
    };

    final model = OfferModel.fromJson(json);

    expect(model.id, 1);
    expect(model.applicationId, 5);
    expect(model.status, 'sent');
    expect(model.title, isNull);
    expect(model.salaryAmount, isNull);
    expect(model.salaryCurrency, isNull);
    expect(model.salaryPeriod, isNull);
    expect(model.startDate, isNull);
    expect(model.message, isNull);
    expect(model.sentAt, isNull);
    expect(model.respondedAt, isNull);
    expect(model.createdAt, isNull);
    expect(model.updatedAt, isNull);
  });

  test('title, salary fields, start date, and message are all nullable', () {
    final model = OfferModel.fromJson(
      _offerJson(
        title: null,
        salaryAmount: null,
        salaryCurrency: null,
        salaryPeriod: null,
        startDate: null,
        message: null,
      ),
    );

    expect(model.title, isNull);
    expect(model.salaryAmount, isNull);
    expect(model.salaryCurrency, isNull);
    expect(model.salaryPeriod, isNull);
    expect(model.startDate, isNull);
    expect(model.message, isNull);
  });

  test('salaryAmount is preserved as a raw decimal string, not parsed', () {
    final model = OfferModel.fromJson(_offerJson(salaryAmount: '1500.50'));

    expect(model.salaryAmount, isA<String>());
    expect(model.salaryAmount, '1500.50');
  });

  test('salaryAmount preserves trailing zero decimal precision', () {
    final model = OfferModel.fromJson(_offerJson(salaryAmount: '90000.00'));

    expect(model.salaryAmount, '90000.00');
  });

  test('respondedAt parses when present', () {
    final model = OfferModel.fromJson(
      _offerJson(
        status: 'accepted',
        respondedAt: '2026-08-12T10:00:00.000000Z',
      ),
    );

    expect(model.respondedAt, DateTime.parse('2026-08-12T10:00:00.000000Z'));
  });

  test('a malformed required id throws rather than silently defaulting', () {
    final json = _offerJson(id: 'not-an-int');

    expect(() => OfferModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('a missing required id throws', () {
    final json = _offerJson(id: null);

    expect(() => OfferModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('a malformed required application_id throws', () {
    final json = _offerJson(applicationId: null);

    expect(() => OfferModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('a malformed required status throws', () {
    final json = _offerJson(status: null);

    expect(() => OfferModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('a non-string status throws', () {
    final json = _offerJson(status: 42);

    expect(() => OfferModel.fromJson(json), throwsA(isA<TypeError>()));
  });

  test('an invalid start_date string parses to null, not a crash', () {
    final model = OfferModel.fromJson(_offerJson(startDate: 'not-a-real-date'));

    expect(model.startDate, isNull);
  });

  test('an invalid sent_at string parses to null, not a crash', () {
    final model = OfferModel.fromJson(_offerJson(sentAt: 'not-a-real-date'));

    expect(model.sentAt, isNull);
  });

  test('extra unrecognized fields in the response are ignored', () {
    final json = _offerJson();
    json['some_future_field'] = 'unexpected value';

    final model = OfferModel.fromJson(json);

    expect(model.id, 1);
    expect(model.status, 'sent');
  });

  test('an unknown status value is preserved as-is, not rejected', () {
    final model = OfferModel.fromJson(_offerJson(status: 'some_future_status'));

    expect(model.status, 'some_future_status');
  });
}
