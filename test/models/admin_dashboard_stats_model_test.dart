// Direct unit tests for AdminDashboardStatsModel.fromJson.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/models/admin_dashboard_stats_model.dart';

Map<String, dynamic> _validJson() {
  return {
    'total_users': 42,
    'total_students': 30,
    'total_organizations': 10,
    'pending_organizations': 3,
    'approved_organizations': 6,
    'rejected_organizations': 1,
    'total_opportunities': 20,
    'open_opportunities': 15,
    'closed_opportunities': 5,
    'total_applications': 100,
    'total_interviews': 8,
  };
}

void main() {
  group('AdminDashboardStatsModel.fromJson', () {
    test('parses a full valid JSON response', () {
      final stats = AdminDashboardStatsModel.fromJson(_validJson());

      expect(stats.totalUsers, 42);
      expect(stats.totalStudents, 30);
      expect(stats.totalOrganizations, 10);
      expect(stats.pendingOrganizations, 3);
      expect(stats.approvedOrganizations, 6);
      expect(stats.rejectedOrganizations, 1);
      expect(stats.totalOpportunities, 20);
      expect(stats.openOpportunities, 15);
      expect(stats.closedOpportunities, 5);
      expect(stats.totalApplications, 100);
      expect(stats.totalInterviews, 8);
    });

    test('accepts real JSON integers', () {
      final json = _validJson();
      json['total_users'] = 7;

      final stats = AdminDashboardStatsModel.fromJson(json);

      expect(stats.totalUsers, 7);
    });

    test('accepts numeric strings', () {
      final json = _validJson();
      json['total_users'] = '7';
      json['total_students'] = '5';

      final stats = AdminDashboardStatsModel.fromJson(json);

      expect(stats.totalUsers, 7);
      expect(stats.totalStudents, 5);
    });

    test('accepts a double-typed count and truncates it to an int', () {
      final json = _validJson();
      json['total_users'] = 7.0;

      final stats = AdminDashboardStatsModel.fromJson(json);

      expect(stats.totalUsers, 7);
    });

    test('a malformed (non-numeric string) field throws', () {
      final json = _validJson();
      json['total_users'] = 'not-a-number';

      expect(
        () => AdminDashboardStatsModel.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('a malformed (bool) field throws', () {
      final json = _validJson();
      json['total_students'] = true;

      expect(
        () => AdminDashboardStatsModel.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('a null required field throws instead of silently becoming 0', () {
      final json = _validJson();
      json['total_organizations'] = null;

      expect(
        () => AdminDashboardStatsModel.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('a missing required field throws instead of silently becoming 0', () {
      final json = _validJson()..remove('total_interviews');

      expect(
        () => AdminDashboardStatsModel.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('every one of the 11 required fields is individually enforced', () {
      const fields = [
        'total_users',
        'total_students',
        'total_organizations',
        'pending_organizations',
        'approved_organizations',
        'rejected_organizations',
        'total_opportunities',
        'open_opportunities',
        'closed_opportunities',
        'total_applications',
        'total_interviews',
      ];

      for (final field in fields) {
        final json = _validJson()..remove(field);
        expect(
          () => AdminDashboardStatsModel.fromJson(json),
          throwsA(isA<FormatException>()),
          reason: 'Expected missing "$field" to throw',
        );
      }
    });

    test('unknown extra fields are ignored', () {
      final json = _validJson();
      json['unexpected_future_field'] = 'some value';
      json['another_unknown_field'] = 123;

      final stats = AdminDashboardStatsModel.fromJson(json);

      expect(stats.totalUsers, 42);
      expect(stats.totalInterviews, 8);
    });
  });
}
