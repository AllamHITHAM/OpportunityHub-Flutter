// Direct unit tests for UserModel.fromJson.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/models/user_model.dart';

void main() {
  group('UserModel.fromJson', () {
    test(
      'parses the classic auth/session shape (no created_at/updated_at)',
      () {
        final user = UserModel.fromJson({
          'id': 1,
          'name': 'Jane Admin',
          'email': 'jane@example.com',
          'role': 'admin',
          'status': 'active',
        });

        expect(user.id, 1);
        expect(user.name, 'Jane Admin');
        expect(user.email, 'jane@example.com');
        expect(user.role, 'admin');
        expect(user.status, 'active');
        expect(user.createdAt, isNull);
        expect(user.updatedAt, isNull);
      },
    );

    test('parses created_at when present', () {
      final user = UserModel.fromJson({
        'id': 1,
        'name': 'Jane Admin',
        'email': 'jane@example.com',
        'role': 'admin',
        'status': 'active',
        'created_at': '2026-07-01T10:00:00.000000Z',
      });

      expect(user.createdAt, DateTime.parse('2026-07-01T10:00:00.000000Z'));
    });

    test('parses updated_at when present', () {
      final user = UserModel.fromJson({
        'id': 1,
        'name': 'Jane Admin',
        'email': 'jane@example.com',
        'role': 'admin',
        'status': 'active',
        'updated_at': '2026-08-01T09:30:00.000000Z',
      });

      expect(user.updatedAt, DateTime.parse('2026-08-01T09:30:00.000000Z'));
    });

    test('a malformed created_at becomes null, not a crash', () {
      final user = UserModel.fromJson({
        'id': 1,
        'name': 'Jane Admin',
        'email': 'jane@example.com',
        'role': 'admin',
        'status': 'active',
        'created_at': 'not-a-date',
      });

      expect(user.createdAt, isNull);
    });

    test('a malformed updated_at becomes null, not a crash', () {
      final user = UserModel.fromJson({
        'id': 1,
        'name': 'Jane Admin',
        'email': 'jane@example.com',
        'role': 'admin',
        'status': 'active',
        'updated_at': 12345,
      });

      expect(user.updatedAt, isNull);
    });

    test('null created_at/updated_at fields stay null', () {
      final user = UserModel.fromJson({
        'id': 1,
        'name': 'Jane Admin',
        'email': 'jane@example.com',
        'role': 'admin',
        'status': 'active',
        'created_at': null,
        'updated_at': null,
      });

      expect(user.createdAt, isNull);
      expect(user.updatedAt, isNull);
    });

    test('missing required fields fall back to safe defaults, never crash', () {
      final user = UserModel.fromJson({});

      expect(user.id, 0);
      expect(user.name, '');
      expect(user.email, '');
      expect(user.role, '');
      expect(user.status, '');
      expect(user.createdAt, isNull);
      expect(user.emailVerified, isFalse);
    });

    test('parses email_verified true (Phase 8B-2)', () {
      final user = UserModel.fromJson({
        'id': 1,
        'name': 'Jane Admin',
        'email': 'jane@example.com',
        'role': 'admin',
        'status': 'active',
        'email_verified': true,
      });

      expect(user.emailVerified, isTrue);
    });

    test('parses email_verified false (Phase 8B-2)', () {
      final user = UserModel.fromJson({
        'id': 1,
        'name': 'Jane Admin',
        'email': 'jane@example.com',
        'role': 'admin',
        'status': 'active',
        'email_verified': false,
      });

      expect(user.emailVerified, isFalse);
    });

    test('a missing email_verified defaults to false', () {
      final user = UserModel.fromJson({
        'id': 1,
        'name': 'Jane Admin',
        'email': 'jane@example.com',
        'role': 'admin',
        'status': 'active',
      });

      expect(user.emailVerified, isFalse);
    });
  });

  group('UserModel constructor', () {
    test(
      'remains valid without createdAt/updatedAt (backward compatibility)',
      () {
        const user = UserModel(
          id: 1,
          name: 'Jane Admin',
          email: 'jane@example.com',
          role: 'admin',
          status: 'active',
        );

        expect(user.createdAt, isNull);
        expect(user.updatedAt, isNull);
      },
    );

    test('accepts createdAt/updatedAt when provided', () {
      final createdAt = DateTime(2026, 7, 1);
      final updatedAt = DateTime(2026, 8, 1);
      final user = UserModel(
        id: 1,
        name: 'Jane Admin',
        email: 'jane@example.com',
        role: 'admin',
        status: 'active',
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      expect(user.createdAt, createdAt);
      expect(user.updatedAt, updatedAt);
    });
  });

  group('UserModel.toJson', () {
    test('round-trips id/name/email/role/status', () {
      const user = UserModel(
        id: 5,
        name: 'Jane Admin',
        email: 'jane@example.com',
        role: 'admin',
        status: 'active',
      );

      final json = user.toJson();

      expect(json['id'], 5);
      expect(json['name'], 'Jane Admin');
      expect(json['email'], 'jane@example.com');
      expect(json['role'], 'admin');
      expect(json['status'], 'active');
      expect(json['email_verified'], false);
    });
  });
}
