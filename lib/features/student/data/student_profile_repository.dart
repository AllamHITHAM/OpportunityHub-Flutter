import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../models/student_profile_model.dart';

/// Talks to the Laravel student-profile endpoints.
class StudentProfileRepository {
  StudentProfileRepository({required this.apiClient});

  final ApiClient apiClient;

  /// Creates the student's profile with `POST /api/student/profile`.
  ///
  /// Only sends the fields the backend documents for this call — never
  /// account fields (name/email/password) or a GPA, which this endpoint
  /// doesn't accept.
  ///
  /// [currentLocationId] and [availableLocationIds] (Student Location
  /// Profile Patch) are optional here too — a Student may finish Profile
  /// Setup without configuring either and add them later via Edit Profile.
  ///
  /// [interestedIn] (Candidate Opportunity Preferences patch) is required
  /// by the backend on create (`min:1`) — the canonical Opportunity Type
  /// values only, never free text.
  Future<StudentProfileModel> createProfile({
    required String university,
    required String major,
    required int graduationYear,
    required List<String> interestedIn,
    int? currentLocationId,
    List<int>? availableLocationIds,
  }) async {
    try {
      final response = await apiClient.dio.post(
        '/student/profile',
        data: {
          'university': university,
          'major': major,
          'graduation_year': graduationYear,
          'interested_in': interestedIn,
          'current_location_id': currentLocationId,
          'available_location_ids': ?availableLocationIds,
        },
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return StudentProfileModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Fetches the current student's own profile with
  /// `GET /api/student/profile`.
  ///
  /// Returns `null` on the documented 404 ("Student profile not found") —
  /// that's an expected outcome (the student hasn't completed onboarding
  /// yet), not an error. Any other failure still throws [ApiException].
  Future<StudentProfileModel?> getProfile() async {
    try {
      final response = await apiClient.dio.get('/student/profile');
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return StudentProfileModel.fromJson(data);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return null;
      }
      throw apiClient.handleError(error);
    }
  }

  /// Updates the student's existing profile with `PUT /api/student/profile`
  /// — same allow-listed fields and same canonical response shape as
  /// [createProfile]. Every field is sent on every call (the Edit Profile
  /// form always submits its full current state), so an optional field left
  /// blank is sent as `null` and genuinely clears it, matching what the
  /// user sees on screen.
  ///
  /// [currentLocationId] (Student Location Profile Patch) is always sent
  /// too, replacing the student's current/home location outright — `null`
  /// genuinely clears it. [availableLocationIds] (Phase O8.2) is also
  /// always sent, replacing the student's whole available-locations set
  /// with exactly this list — real canonical Location IDs, never free
  /// text. An empty list is a real "clear my locations" instruction,
  /// distinct from omitting the field entirely (which this app's Edit
  /// Profile form never does, since it always submits the full current
  /// selection).
  /// [interestedIn] (Candidate Opportunity Preferences patch) is always
  /// sent, replacing the Student's whole preference set outright — the
  /// Edit Profile form always submits its full current selection, and the
  /// backend rejects an explicitly-empty array (`min:1` whenever the key
  /// is present), so this app's own form validation guarantees at least
  /// one entry before this method is ever called.
  Future<StudentProfileModel> updateProfile({
    required String university,
    required String major,
    required int graduationYear,
    required List<String> interestedIn,
    String? phone,
    String? bio,
    int? currentLocationId,
    List<int> availableLocationIds = const [],
  }) async {
    try {
      final response = await apiClient.dio.put(
        '/student/profile',
        data: {
          'university': university,
          'major': major,
          'graduation_year': graduationYear,
          'interested_in': interestedIn,
          'phone': phone,
          'bio': bio,
          'current_location_id': currentLocationId,
          'available_location_ids': availableLocationIds,
        },
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return StudentProfileModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }
}
