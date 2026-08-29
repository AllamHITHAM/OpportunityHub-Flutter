import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/locations/data/location_repository.dart';
import '../models/location_model.dart';

/// The real, full canonical Location Catalog (Phase O8.2) -- shared by the
/// Student Profile Edit screen's "Available Work Locations" multi-select
/// and the Create/Edit Opportunity screen's single Location picker, so the
/// same caching/loading logic isn't duplicated per feature. Mirrors
/// `StudentSkillProvider`'s own catalog-loading shape (cached by default,
/// `forceRefresh` to bypass).
class LocationCatalogProvider extends ChangeNotifier {
  LocationCatalogProvider({required this.repository});

  final LocationRepository repository;

  List<LocationModel> locations = [];
  bool isLoading = false;
  String? errorMessage;
  Future<void>? _pendingFetch;

  Future<void> load({bool forceRefresh = false}) {
    if (forceRefresh) {
      _pendingFetch = null;
    }
    if (!forceRefresh && locations.isNotEmpty) {
      return _pendingFetch ?? Future.value();
    }
    return _pendingFetch ??= _performLoad();
  }

  Future<void> _performLoad() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      locations = await repository.getLocations();
    } on ApiException catch (error) {
      errorMessage = error.message;
    } catch (_) {
      errorMessage = 'Something went wrong. Please try again.';
    } finally {
      isLoading = false;
      _pendingFetch = null;
      notifyListeners();
    }
  }

  bool isAddingLocation = false;
  String? addLocationErrorMessage;

  /// Resolves [name] to a canonical Location via the backend's typed-
  /// search-or-add endpoint (Recommendation Accuracy Patch) -- reusing an
  /// existing catalog entry whenever the backend finds one (by canonical
  /// name or a known alias), and only ever adding a genuinely new entry to
  /// [locations] when the backend actually created one. Returns `null` on
  /// failure ([addLocationErrorMessage] then carries the real reason).
  Future<LocationModel?> addLocation(String name) async {
    isAddingLocation = true;
    addLocationErrorMessage = null;
    notifyListeners();

    LocationModel? result;
    try {
      result = await repository.addLocation(name);
      if (!locations.contains(result)) {
        locations = [...locations, result]
          ..sort((a, b) => a.canonicalName.compareTo(b.canonicalName));
      }
    } on ApiException catch (error) {
      addLocationErrorMessage = error.message;
    } catch (_) {
      addLocationErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      isAddingLocation = false;
      notifyListeners();
    }

    return result;
  }
}
