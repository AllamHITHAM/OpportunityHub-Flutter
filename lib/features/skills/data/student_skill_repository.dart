import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../models/skill_model.dart';
import '../../../models/student_skill_model.dart';

/// Talks to the Laravel student-skill endpoints: listing the student's own
/// skills, browsing the real Skill catalog (Phase 8A-6.3), adding one
/// (manually or an accepted AI CV suggestion), and removing one from the
/// student's own profile (Phase 8A-6.1's My Skills delete action).
class StudentSkillRepository {
  StudentSkillRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Fetches the authenticated student's own skills with
  /// `GET /api/student/skills`, each carrying its evidence `source`.
  ///
  /// Errors: 401, 403, 404 ("You must create a student profile first").
  Future<List<StudentSkillModel>> getStudentSkills() async {
    try {
      final response = await apiClient.dio.get('/student/skills');
      final data = apiClient.parseData(response) as List;
      return data
          .map(
            (json) => StudentSkillModel.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Fetches the real, full Skill catalog with
  /// `GET /api/student/skills/catalog` (Phase 8A-6.3) -- every entry is
  /// Admin-owned/approved by construction, ordered by name by the backend.
  /// Powers the real Manual Add Skill picker; never a partial,
  /// opportunity-derived, or hardcoded list.
  ///
  /// Errors: 401, 403.
  Future<List<SkillModel>> getSkillCatalog() async {
    try {
      final response = await apiClient.dio.get('/student/skills/catalog');
      final data = apiClient.parseData(response) as List;
      return data
          .map((json) => SkillModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Adds a skill to the authenticated student's profile with
  /// `POST /api/student/skills`, returning the real, backend-persisted
  /// `StudentSkill` row (including the source the backend actually
  /// assigned). [level] defaults to `intermediate` -- the AI extraction
  /// endpoint only ever produces a confidence score, never a proficiency
  /// level, so this is a reasonable starting value for an accepted AI
  /// suggestion; the real Manual Add Skill flow always passes the
  /// student's own explicit choice instead.
  ///
  /// [source] defaults to `manual` -- the ordinary Add Skill flow. Pass
  /// `source: 'cv_ai'` with the [cvId] the AI extraction ran against only
  /// when accepting an AI CV suggestion; the backend independently
  /// verifies that claim against real extraction evidence before ever
  /// storing it (Phase 8A-6.1) -- this call cannot spoof `cv_ai` on its
  /// own.
  ///
  /// Errors: 401, 403, 404, 409 (already added), 422 (invalid skill_id,
  /// invalid level, or a `cv_ai` claim that fails backend evidence
  /// verification).
  Future<StudentSkillModel> addSkill({
    required int skillId,
    String level = 'intermediate',
    String source = 'manual',
    int? cvId,
  }) async {
    try {
      final response = await apiClient.dio.post(
        '/student/skills',
        data: {
          'skill_id': skillId,
          'level': level,
          'source': source,
          'cv_id': cvId,
        },
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return StudentSkillModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Removes a skill from the authenticated student's own profile with
  /// `DELETE /api/student/skills/{studentSkillId}`. [studentSkillId] is the
  /// `StudentSkill` row's own id (`StudentSkillModel.id`), not the catalog
  /// `Skill` id -- this only ever deletes the student's relationship row;
  /// the global `Skill` catalog entry is never touched.
  ///
  /// Errors: 401, 403, 404 (not found / not yours).
  Future<void> deleteSkill(int studentSkillId) async {
    try {
      await apiClient.dio.delete('/student/skills/$studentSkillId');
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }
}
