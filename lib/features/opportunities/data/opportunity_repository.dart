import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/paginated_result.dart';
import '../../../models/opportunity_model.dart';

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
    String? fieldOfStudy,
    String? location,
    double? salaryMin,
    double? salaryMax,
    DateTime? applicationDeadline,
    int? positionsAvailable,
    String? status,
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
          fieldOfStudy: fieldOfStudy,
          location: location,
          salaryMin: salaryMin,
          salaryMax: salaryMax,
          applicationDeadline: applicationDeadline,
          positionsAvailable: positionsAvailable,
          status: status,
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
    String? fieldOfStudy,
    String? location,
    double? salaryMin,
    double? salaryMax,
    DateTime? applicationDeadline,
    int? positionsAvailable,
    String? status,
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
          fieldOfStudy: fieldOfStudy,
          location: location,
          salaryMin: salaryMin,
          salaryMax: salaryMax,
          applicationDeadline: applicationDeadline,
          positionsAvailable: positionsAvailable,
          status: status,
        ),
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return OpportunityModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Deletes an opportunity with
  /// `DELETE /api/organization/opportunities/{id}`.
  ///
  /// Errors: 404 (not found / not yours), 409 ("Cannot delete an
  /// opportunity that has applications").
  Future<void> deleteOpportunity(int id) async {
    try {
      await apiClient.dio.delete('/organization/opportunities/$id');
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
    String? fieldOfStudy,
    String? location,
    double? salaryMin,
    double? salaryMax,
    DateTime? applicationDeadline,
    int? positionsAvailable,
    String? status,
  }) {
    final blankableFieldOfStudy = (fieldOfStudy?.isNotEmpty ?? false)
        ? fieldOfStudy
        : null;
    final blankableLocation = (location?.isNotEmpty ?? false) ? location : null;
    final formattedDeadline = applicationDeadline == null
        ? null
        : _formatDate(applicationDeadline);

    return {
      'title': title,
      'description': description,
      'opportunity_type': opportunityType,
      'employment_type': employmentType,
      'work_mode': workMode,
      'experience_level': experienceLevel,
      'education_level': ?educationLevel,
      'field_of_study': ?blankableFieldOfStudy,
      'location': ?blankableLocation,
      'salary_min': ?salaryMin,
      'salary_max': ?salaryMax,
      'application_deadline': ?formattedDeadline,
      'positions_available': ?positionsAvailable,
      'status': ?status,
    };
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
