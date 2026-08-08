// Direct unit tests for SkillModel, focused on the additive
// createdAt/updatedAt extension added for Phase 5A-4 (Admin Skill
// Management) — see admin_skills_repository_test.dart for the
// repository-boundary validation that sits in front of this model.

import 'package:flutter_test/flutter_test.dart';

import 'package:opportunityhub_flutter/models/skill_model.dart';

void main() {
  group('fromJson', () {
    test('valid JSON parses every field', () {
      final json = {
        'id': 1,
        'name': 'Flutter',
        'category': 'Mobile',
        'created_at': '2026-07-01T10:00:00.000000Z',
        'updated_at': '2026-07-02T10:00:00.000000Z',
      };

      final model = SkillModel.fromJson(json);

      expect(model.id, 1);
      expect(model.name, 'Flutter');
      expect(model.category, 'Mobile');
      expect(model.createdAt, DateTime.parse('2026-07-01T10:00:00.000000Z'));
      expect(model.updatedAt, DateTime.parse('2026-07-02T10:00:00.000000Z'));
    });

    test('old existing JSON (no timestamps) still parses', () {
      final json = {'id': 1, 'name': 'Flutter', 'category': null};

      final model = SkillModel.fromJson(json);

      expect(model.id, 1);
      expect(model.name, 'Flutter');
      expect(model.category, isNull);
      expect(model.createdAt, isNull);
      expect(model.updatedAt, isNull);
    });

    test('a malformed id throws instead of silently defaulting', () {
      final json = {'id': 'not-an-int', 'name': 'Flutter'};

      expect(() => SkillModel.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('a missing id throws instead of silently defaulting', () {
      final json = {'name': 'Flutter'};

      expect(() => SkillModel.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('a malformed name throws instead of silently defaulting', () {
      final json = {'id': 1, 'name': 42};

      expect(() => SkillModel.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('a missing name throws instead of silently defaulting', () {
      final json = {'id': 1};

      expect(() => SkillModel.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('extra unknown fields are ignored', () {
      final json = {
        'id': 1,
        'name': 'Flutter',
        'unexpected_field': 'should be ignored',
      };

      final model = SkillModel.fromJson(json);

      expect(model.id, 1);
      expect(model.name, 'Flutter');
    });

    test('a malformed created_at/updated_at becomes null, not a crash', () {
      final json = {
        'id': 1,
        'name': 'Flutter',
        'created_at': 'not-a-date',
        'updated_at': 12345,
      };

      final model = SkillModel.fromJson(json);

      expect(model.createdAt, isNull);
      expect(model.updatedAt, isNull);
    });
  });

  group('constructor', () {
    test('remains backward-compatible without the timestamp arguments', () {
      const model = SkillModel(id: 1, name: 'Flutter');

      expect(model.createdAt, isNull);
      expect(model.updatedAt, isNull);
    });
  });
}
