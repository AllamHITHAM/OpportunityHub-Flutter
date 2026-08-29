import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/paginated_result.dart';
import '../../../models/opportunity_model.dart';
import '../../../models/opportunity_skill_model.dart';
import '../../../models/skill_model.dart';

/// Talks to the Laravel opportunity endpoints — both the organization's own
/// (`/organization/opportunities`) and the public/student-facing ones
/// (`/opportunities`). Both operate on the same underlying entity, so one
/// repository serves both rather than duplicating request/parsing logic
/// across two classes.
///
/// The organization's own list endpoint (unlike the public opportunities
/// listing) returns a plain array — it is not paginated.
class OpportunityRepository {
  OpportunityRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Fetches the authenticated organization's own opportunities with
  /// `GET /api/organization/opportunities`.
  Future<List<OpportunityModel>> getOpportunities() async {
    try {
      final response = await apiClient.dio.get('/organization/opportunities');
      final data = apiClient.parseData(response) as List;
      return data
          .map(
            (json) => OpportunityModel.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Fetches a single opportunity with
  /// `GET /api/organization/opportunities/{id}`.
  ///
  /// The backend returns a 404 ("Opportunity not found") both when the ID
  /// doesn't exist and when it belongs to a different organization —
  /// deliberately indistinguishable, so both surface as [ApiException]
  /// here without a special "not mine" case.
  Future<OpportunityModel> getOpportunity(int id) async {
    try {
      final response = await apiClient.dio.get(
        '/organization/opportunities/$id',
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return OpportunityModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Creates an opportunity with `POST /api/organization/opportunities`.
  ///
  /// Requires an approved organization — the backend returns 403
  /// ("Organization is not approved to publish opportunities") otherwise.
  Future<OpportunityModel> createOpportunity({
    required String title,
    required String description,
    required String opportunityType,
    required String employmentType,
    required String workMode,
    required String experienceLevel,
    String? educationLevel,
    int? locationId,
    double? salaryMin,
    double? salaryMax,
    DateTime? applicationDeadline,
    int? positionsAvailable,
    String? status,
    List<String>? eligibleMajors,
    Map<int, bool>? skills,
    String? recruitmentProcess,
  }) async {
    try {
      final response = await apiClient.dio.post(
        '/organization/opportunities',
        data: _buildPayload(
          title: title,
          description: description,
          opportunityType: opportunityType,
          employmentType: employmentType,
          workMode: workMode,
          experienceLevel: experienceLevel,
          educationLevel: educationLevel,
          locationId: locationId,
          salaryMin: salaryMin,
          salaryMax: salaryMax,
          applicationDeadline: applicationDeadline,
          positionsAvailable: positionsAvailable,
          status: status,
          eligibleMajors: eligibleMajors,
          skills: skills,
          recruitmentProcess: recruitmentProcess,
        ),
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return OpportunityModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Updates an opportunity with `PUT /api/organization/opportunities/{id}`.
  ///
  /// Unlike create, the backend doesn't require [applicationDeadline] to be
  /// today or later here — an already-passed deadline can still be edited.
  Future<OpportunityModel> updateOpportunity({
    required int id,
    required String title,
    required String description,
    required String opportunityType,
    required String employmentType,
    required String workMode,
    required String experienceLevel,
    String? educationLevel,
    int? locationId,
    double? salaryMin,
    double? salaryMax,
    DateTime? applicationDeadline,
    int? positionsAvailable,
    String? status,
    List<String>? eligibleMajors,
    Map<int, bool>? skills,
    String? recruitmentProcess,
  }) async {
    try {
      final response = await apiClient.dio.put(
        '/organization/opportunities/$id',
        data: _buildPayload(
          title: title,
          description: description,
          opportunityType: opportunityType,
          employmentType: employmentType,
          workMode: workMode,
          experienceLevel: experienceLevel,
          educationLevel: educationLevel,
          locationId: locationId,
          salaryMin: salaryMin,
          salaryMax: salaryMax,
          applicationDeadline: applicationDeadline,
          positionsAvailable: positionsAvailable,
          status: status,
          eligibleMajors: eligibleMajors,
          skills: skills,
          recruitmentProcess: recruitmentProcess,
        ),
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return OpportunityModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Fetches the real, full canonical Skill Catalog for the Required
  /// Skills multi-select (Phase O8.2) with
  /// `GET /api/organization/skills/catalog` — an Organization-side mirror
  /// of the Student's own `GET /api/student/skills/catalog`.
  Future<List<SkillModel>> getSkillCatalog() async {
    try {
      final response = await apiClient.dio.get('/organization/skills/catalog');
      final data = apiClient.parseData(response) as List;
      return data
          .map((json) => SkillModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Replaces [opportunityId]'s entire Required/Preferred Skill set in one
  /// call with `PUT /api/organization/opportunities/{id}/skills` (Phase
  /// O8.2) — every entry a real, canonical `skills.id`, never free text.
  Future<List<OpportunitySkillModel>> syncOpportunitySkills(
    int opportunityId,
    Map<int, bool> skillIdToIsRequired,
  ) async {
    try {
      final response = await apiClient.dio.put(
        '/organization/opportunities/$opportunityId/skills',
        data: {
          'skills': [
            for (final entry in skillIdToIsRequired.entries)
              {'skill_id': entry.key, 'is_required': entry.value},
          ],
        },
      );
      final data = apiClient.parseData(response) as List;
      return data
          .map(
            (json) =>
                OpportunitySkillModel.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Deletes an opportunity with
  /// `DELETE /api/organization/opportunities/{id}` — used by the
  /// Organization Opportunities management screen, unrestricted by
  /// status.
  ///
  /// Errors: 404 (not found / not yours), 409 ("Cannot delete an
  /// opportunity that has recruitment history").
  Future<void> deleteOpportunity(int id) async {
    try {
      await apiClient.dio.delete('/organization/opportunities/$id');
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Fetches one real, backend-paginated/filtered/sorted page of the
  /// authenticated organization's own closed opportunities with
  /// `GET /api/organization/opportunities/closed` (Closed Opportunities
  /// Scalability Polish) — never the unbounded [getOpportunities] list
  /// filtered client-side, which is what the Company Profile's "Closed
  /// Opportunities" section used before this.
  ///
  /// [datePreset] (`all`/`last_30_days`/`last_3_months`/`last_6_months`/
  /// `this_year`/`older`) and a custom [closedFrom]/[closedTo] range are
  /// mutually exclusive on the backend — passing both simply lets the
  /// custom range win (matching the UI, which only ever offers one or the
  /// other). Returns both the requested page (via the shared
  /// [PaginatedResult] wrapper every other paginated endpoint in this app
  /// already uses) and the organization's real TOTAL closed count,
  /// unaffected by whatever filter is applied — the accordion header's
  /// "Closed Opportunities (N)" always reads that, never the filtered
  /// page's own total.
  Future<({PaginatedResult<OpportunityModel> result, int totalClosed})> getClosedOpportunities({
    String? datePreset,
    DateTime? closedFrom,
    DateTime? closedTo,
    String sort = 'newest',
    int page = 1,
    int perPage = 15,
  }) async {
    try {
      final response = await apiClient.dio.get(
        '/organization/opportunities/closed',
        queryParameters: {
          'date_preset': ?datePreset,
          'closed_from': ?(closedFrom != null ? _formatDate(closedFrom) : null),
          'closed_to': ?(closedTo != null ? _formatDate(closedTo) : null),
          'sort': sort,
          'page': page,
          'per_page': perPage,
        },
      );
      final raw = response.data as Map<String, dynamic>;
      final data = raw['data'] as Map<String, dynamic>;
      final items = (data['data'] as List)
          .map(
            (json) => OpportunityModel.fromJson(json as Map<String, dynamic>),
          )
          .toList();
      return (
        result: PaginatedResult(
          items: items,
          currentPage: data['current_page'] as int,
          lastPage: data['last_page'] as int,
          total: data['total'] as int,
        ),
        totalClosed: raw['total_closed'] as int? ?? 0,
      );
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Permanently deletes a *closed* opportunity with
  /// `DELETE /api/organization/opportunities/{id}/closed` (Company
  /// Profile Polish phase) — the Company Profile's own "Closed
  /// Opportunities" cleanup action. Deliberately a separate call from
  /// [deleteOpportunity]: the backend additionally requires
  /// `status === 'closed'` here.
  ///
  /// Errors: 404 (not found / not yours), 409 (not closed, or has
  /// recruitment history).
  Future<void> deleteClosedOpportunity(int id) async {
    try {
      await apiClient.dio.delete('/organization/opportunities/$id/closed');
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Fetches the publicly browsable, open opportunities with
  /// `GET /api/opportunities` — the same endpoint whether the caller is an
  /// anonymous visitor or an authenticated student; the backend applies no
  /// auth middleware here at all.
  ///
  /// Unlike the organization's own list, this is paginated by the backend,
  /// so the result carries the current/last page and total count alongside
  /// the items for the given [page].
  Future<PaginatedResult<OpportunityModel>> getPublicOpportunities({
    String? opportunityType,
    String? employmentType,
    String? workMode,
    String? experienceLevel,
    String? location,
    String? fieldOfStudy,
    String? keyword,
    int? organizationId,
    int page = 1,
    int perPage = 15,
  }) async {
    try {
      final response = await apiClient.dio.get(
        '/opportunities',
        queryParameters: {
          'opportunity_type': ?opportunityType,
          'employment_type': ?employmentType,
          'work_mode': ?workMode,
          'experience_level': ?experienceLevel,
          'location': ?location,
          'field_of_study': ?fieldOfStudy,
          'keyword': ?keyword,
          // Organization Public Profile phase: scopes to one
          // organization's own open opportunities for the Company
          // Profile screen's "Open Opportunities" section.
          'organization_id': ?organizationId,
          'page': page,
          'per_page': perPage,
        },
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      final items = (data['data'] as List)
          .map(
            (json) => OpportunityModel.fromJson(json as Map<String, dynamic>),
          )
          .toList();
      return PaginatedResult(
        items: items,
        currentPage: data['current_page'] as int,
        lastPage: data['last_page'] as int,
        total: data['total'] as int,
      );
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Fetches a single publicly browsable opportunity with
  /// `GET /api/opportunities/{id}`.
  ///
  /// The backend returns a 404 both for a genuinely nonexistent ID and for
  /// one that exists but isn't open (or whose organization isn't approved)
  /// — deliberately indistinguishable, same as the organization endpoint's
  /// "not found / not yours".
  Future<OpportunityModel> getPublicOpportunity(int id) async {
    try {
      final response = await apiClient.dio.get('/opportunities/$id');
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return OpportunityModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Builds the shared create/update request body. Optional fields left
  /// null (or blank strings) are omitted entirely rather than sent as
  /// `null`/empty — `positions_available` in particular has a NOT-NULL
  /// database column with a default of 1, so explicitly sending `null`
  /// would risk a database error rather than falling back to that default.
  Map<String, dynamic> _buildPayload({
    required String title,
    required String description,
    required String opportunityType,
    required String employmentType,
    required String workMode,
    required String experienceLevel,
    String? educationLevel,
    int? locationId,
    double? salaryMin,
    double? salaryMax,
    DateTime? applicationDeadline,
    int? positionsAvailable,
    String? status,
    List<String>? eligibleMajors,
    Map<int, bool>? skills,
    String? recruitmentProcess,
  }) {
    final formattedDeadline = applicationDeadline == null
        ? null
        : _formatDate(applicationDeadline);
    final skillsPayload = skills == null
        ? null
        : [
            for (final entry in skills.entries)
              {'skill_id': entry.key, 'is_required': entry.value},
          ];

    return {
      'title': title,
      'description': description,
      'opportunity_type': opportunityType,
      'employment_type': employmentType,
      'work_mode': workMode,
      'experience_level': experienceLevel,
      'education_level': ?educationLevel,
      // Opportunity Academic Matching Cleanup: `field_of_study` is
      // deprecated and no longer sent by this form at all -- Eligible
      // Majors (`eligible_majors` below) is the sole academic-eligibility
      // input. The legacy backend column/value, if any, is left exactly
      // as it was on any existing Opportunity (this key is simply never
      // included, never explicitly cleared).
      // Phase O8.2: the canonical Location Catalog ID -- never free text.
      // Sent whenever the form has one selected (including switching to
      // Remote, where the form clears it back to `null` and this key is
      // still sent so the backend mirrors the legacy `location` string
      // back to `null` too, rather than leaving a stale value behind).
      'location_id': locationId,
      'salary_min': ?salaryMin,
      'salary_max': ?salaryMax,
      'application_deadline': ?formattedDeadline,
      'positions_available': ?positionsAvailable,
      'status': ?status,
      // Sent only when non-null -- an explicit empty list still sends
      // the key (clearing the Opportunity's eligible majors on update),
      // while `null` omits it entirely (leaves the existing set
      // untouched on update; means "none" on create). See
      // `OpportunityController::update()`'s own doc comment (backend).
      'eligible_majors': ?eligibleMajors,
      // Opportunity Requirements Integrity Patch: Required Skills are now
      // saved atomically with the Opportunity itself (in the same request
      // and backend transaction), never through a separate, later
      // `PUT .../skills` call -- see `OpportunityController::store()`.
      // Same "sent only when non-null" convention as `eligible_majors`.
      'skills': ?skillsPayload,
      // Phase 10A.4B: same "sent only when non-null" convention as every
      // other optional field here -- see `StoreOpportunityRequest`/
      // `UpdateOpportunityRequest`'s own doc comments (backend).
      'recruitment_process': ?recruitmentProcess,
    };
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
