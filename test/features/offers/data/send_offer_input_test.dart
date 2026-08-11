// Direct unit tests for SendOfferInput.toJson.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/features/offers/data/send_offer_input.dart';

void main() {
  test('produces the correct backend field names when every field is set', () {
    final input = SendOfferInput(
      title: 'Backend Engineer',
      salaryAmount: 1500.5,
      salaryCurrency: 'USD',
      salaryPeriod: 'monthly',
      startDate: DateTime(2026, 9, 1),
      message: 'Excited to have you join.',
    );

    final json = input.toJson();

    expect(
      json.keys,
      containsAll(<String>[
        'title',
        'salary_amount',
        'salary_currency',
        'salary_period',
        'start_date',
        'message',
      ]),
    );
    expect(json['title'], 'Backend Engineer');
    expect(json['salary_amount'], 1500.5);
    expect(json['salary_currency'], 'USD');
    expect(json['salary_period'], 'monthly');
    expect(json['start_date'], '2026-09-01');
    expect(json['message'], 'Excited to have you join.');
  });

  test('an entirely empty input produces an empty body', () {
    final input = SendOfferInput();

    expect(input.toJson(), isEmpty);
  });

  test('trims title and message before sending', () {
    final input = SendOfferInput(
      title: '  Backend Engineer  ',
      message: '  Excited to have you join.  ',
    );

    final json = input.toJson();

    expect(json['title'], 'Backend Engineer');
    expect(json['message'], 'Excited to have you join.');
  });

  test('omits blank/whitespace-only optional strings entirely', () {
    final input = SendOfferInput(title: '   ', message: '\t\n ');

    final json = input.toJson();

    expect(json.containsKey('title'), isFalse);
    expect(json.containsKey('message'), isFalse);
  });

  test('omits null optional fields entirely', () {
    final input = SendOfferInput();

    final json = input.toJson();

    expect(json.containsKey('title'), isFalse);
    expect(json.containsKey('salary_amount'), isFalse);
    expect(json.containsKey('salary_currency'), isFalse);
    expect(json.containsKey('salary_period'), isFalse);
    expect(json.containsKey('start_date'), isFalse);
    expect(json.containsKey('message'), isFalse);
  });

  test('formats start_date as exactly YYYY-MM-DD', () {
    final input = SendOfferInput(startDate: DateTime(2026, 1, 2, 3, 4, 5));

    expect(input.toJson()['start_date'], '2026-01-02');
  });

  test(
    'salary_currency and salary_period are omitted when salary_amount is null, '
    'even if the caller set them',
    () {
      final input = SendOfferInput(
        salaryAmount: null,
        salaryCurrency: 'USD',
        salaryPeriod: 'monthly',
      );

      final json = input.toJson();

      expect(json.containsKey('salary_amount'), isFalse);
      expect(json.containsKey('salary_currency'), isFalse);
      expect(json.containsKey('salary_period'), isFalse);
    },
  );

  test(
    'salary_currency and salary_period are included alongside a set salary_amount',
    () {
      final input = SendOfferInput(
        salaryAmount: 90000,
        salaryCurrency: 'USD',
        salaryPeriod: 'yearly',
      );

      final json = input.toJson();

      expect(json['salary_amount'], 90000);
      expect(json['salary_currency'], 'USD');
      expect(json['salary_period'], 'yearly');
    },
  );

  test(
    'a set salary_amount with a blank currency omits salary_currency only',
    () {
      final input = SendOfferInput(
        salaryAmount: 90000,
        salaryCurrency: '   ',
        salaryPeriod: 'yearly',
      );

      final json = input.toJson();

      expect(json['salary_amount'], 90000);
      expect(json.containsKey('salary_currency'), isFalse);
      expect(json['salary_period'], 'yearly');
    },
  );

  test('never includes server-controlled fields', () {
    final input = SendOfferInput(
      title: 'Backend Engineer',
      salaryAmount: 90000,
      salaryCurrency: 'USD',
      salaryPeriod: 'yearly',
      startDate: DateTime(2026, 9, 1),
      message: 'Welcome aboard.',
    );

    final json = input.toJson();

    expect(json.containsKey('status'), isFalse);
    expect(json.containsKey('sent_at'), isFalse);
    expect(json.containsKey('responded_at'), isFalse);
    expect(json.containsKey('application_id'), isFalse);
    expect(json.containsKey('id'), isFalse);
  });
}
