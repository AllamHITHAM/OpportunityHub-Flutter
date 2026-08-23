import 'package:flutter_test/flutter_test.dart';
import 'package:opportunityhub_flutter/models/student_skill_model.dart';

void main() {
  group('StudentSkillModel.fromJson', () {
    test('parses a manual skill, including a real category', () {
      final skill = StudentSkillModel.fromJson({
        'id': 1,
        'level': 'advanced',
        'years_of_experience': '3.5',
        'source': 'manual',
        'skill': {'id': 10, 'name': 'AutoCAD', 'category': 'Civil Engineering'},
      });

      expect(skill.id, 1);
      expect(skill.skillId, 10);
      expect(skill.skillName, 'AutoCAD');
      expect(skill.category, 'Civil Engineering');
      expect(skill.level, 'advanced');
      expect(skill.yearsOfExperience, 3.5);
      expect(skill.source, 'manual');
      expect(skill.isCvSupported, isFalse);
      expect(skill.evidenceLabel, 'Self-declared');
    });

    test('parses a cv_ai skill and never invents a "Verified" label', () {
      final skill = StudentSkillModel.fromJson({
        'id': 2,
        'level': 'intermediate',
        'years_of_experience': null,
        'source': 'cv_ai',
        'skill': {'id': 11, 'name': 'Python', 'category': 'Computer Science'},
      });

      expect(skill.isCvSupported, isTrue);
      expect(skill.evidenceLabel, 'CV-supported');
      expect(skill.evidenceLabel, isNot(contains('Verified')));
      expect(skill.yearsOfExperience, isNull);
    });

    test('a null category is preserved as null, never fabricated', () {
      final skill = StudentSkillModel.fromJson({
        'id': 3,
        'level': 'beginner',
        'source': 'manual',
        'skill': {'id': 12, 'name': 'Custom Skill', 'category': null},
      });

      expect(skill.category, isNull);
    });

    test('a missing source defaults to manual', () {
      final skill = StudentSkillModel.fromJson({
        'id': 4,
        'level': 'expert',
        'skill': {'id': 13, 'name': 'Legacy Skill'},
      });

      expect(skill.source, 'manual');
      expect(skill.isCvSupported, isFalse);
    });
  });
}
