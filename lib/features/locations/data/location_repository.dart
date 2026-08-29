import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../models/location_model.dart';

/// Talks to the shared, role-agnostic canonical Location Catalog endpoint
/// (Phase O8.2) — `GET /api/locations`. Both a Student (available work
/// locations) and an Organization (an Opportunity's location) read from
/// this exact same catalog.
class LocationRepository {
  LocationRepository({required this.apiClient});

  final ApiClient apiClient;

  Future<List<LocationModel>> getLocations() async {
    try {
      final response = await apiClient.dio.get('/locations');
      final data = apiClient.parseData(response) as List;
      return data
          .map((json) => LocationModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }

  /// Resolves a typed location name to one canonical [LocationModel]
  /// (Recommendation Accuracy Patch) -- `POST /api/locations`. The backend
  /// reuses an existing canonical name or known alias whenever one
  /// matches, and only ever creates a brand new catalog entry when nothing
  /// at all does; this never sends or stores raw free text anywhere else.
  Future<LocationModel> addLocation(String name) async {
    try {
      final response = await apiClient.dio.post(
        '/locations',
        data: {'name': name},
      );
      final data = apiClient.parseData(response) as Map<String, dynamic>;
      return LocationModel.fromJson(data);
    } on DioException catch (error) {
      throw apiClient.handleError(error);
    }
  }
}
