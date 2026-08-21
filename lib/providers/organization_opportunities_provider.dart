import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/opportunities/data/opportunity_repository.dart';
import '../models/opportunity_model.dart';
import 'auth_provider.dart';

/// Holds the authenticated organization's opportunity list and detail
/// state, and exposes create/update/delete actions to the UI.
///
/// Loading state is split into independent flags (list, details,
/// submitting, per-item deleting) rather than one shared `isLoading`, so
/// e.g. deleting one card in the list doesn't visually lock the whole
/// screen or a separate details view.
class OrganizationOpportunitiesProvider extends ChangeNotifier {
  OrganizationOpportunitiesProvider({
    required this.repository,
    required this._authProvider,
  }) {
    _authProvider.addListener(_handleAuthChanged);
  }

  final OpportunityRepository repository;
  final AuthProvider _authProvider;

  List<OpportunityModel> opportunities = [];
  bool isLoadingList = false;
  String? listErrorMessage;

  OpportunityModel? selectedOpportunity;
  bool isLoadingDetails = false;
  String? detailsErrorMessage;

  bool isSubmitting = false;
  String? formErrorMessage;

  final Set<int> _deletingIds = {};
  String? deleteErrorMessage;

  /// The in-flight list fetch, if any — guards against concurrent duplicate
  /// requests (e.g. a rebuild triggering another `loadOpportunities()` call
  /// while one is already running) without preventing an explicit
  /// pull-to-refresh once the previous fetch has finished.
  Future<void>? _pendingListFetch;
  Future<void>? _pendingDetailsFetch;

  bool isDeleting(int id) => _deletingIds.contains(id);

  void _handleAuthChanged() {
    // A different user may sign in next — don't leak the previous
    // organization's opportunities into their session.
    if (!_authProvider.isAuthenticated) {
      reset();
    }
  }

  /// Loads the organization's own opportunities. Safe to call repeatedly
  /// (e.g. from `initState` and pull-to-refresh) — a fetch already in
  /// flight is reused rather than duplicated; once it completes, calling
  /// this again starts a fresh one.
  Future<void> loadOpportunities() {
    return _pendingListFetch ??= _performLoadOpportunities();
  }

  Future<void> _performLoadOpportunities() async {
    isLoadingList = true;
    listErrorMessage = null;
    notifyListeners();

    try {
      opportunities = await repository.getOpportunities();
    } on ApiException catch (error) {
      listErrorMessage = error.message;
    }

    isLoadingList = false;
    _pendingListFetch = null;
    notifyListeners();
  }

  /// Loads a single opportunity's details. Reuses an already-loaded copy
  /// from the list when available, so navigating from the list to its
  /// details doesn't repeat a GET the app already just made.
  Future<void> loadOpportunityDetails(int id, {bool forceRefresh = false}) {
    if (!forceRefresh) {
      for (final opportunity in opportunities) {
        if (opportunity.id == id) {
          selectedOpportunity = opportunity;
          detailsErrorMessage = null;
          notifyListeners();
          return Future.value();
        }
      }
    }
    return _pendingDetailsFetch ??= _performLoadDetails(id);
  }

  Future<void> _performLoadDetails(int id) async {
    isLoadingDetails = true;
    detailsErrorMessage = null;
    notifyListeners();

    try {
      selectedOpportunity = await repository.getOpportunity(id);
    } on ApiException catch (error) {
      detailsErrorMessage = error.message;
      selectedOpportunity = null;
    }

    isLoadingDetails = false;
    _pendingDetailsFetch = null;
    notifyListeners();
  }

  Future<OpportunityModel?> createOpportunity({
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
    List<String>? eligibleMajors,
  }) async {
    isSubmitting = true;
    formErrorMessage = null;
    notifyListeners();

    OpportunityModel? created;
    try {
      created = await repository.createOpportunity(
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
        eligibleMajors: eligibleMajors,
      );
      opportunities = [...opportunities, created];
    } on ApiException catch (error) {
      formErrorMessage = error.message;
    }

    isSubmitting = false;
    notifyListeners();
    return created;
  }

  Future<OpportunityModel?> updateOpportunity({
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
    List<String>? eligibleMajors,
  }) async {
    isSubmitting = true;
    formErrorMessage = null;
    notifyListeners();

    OpportunityModel? updated;
    try {
      updated = await repository.updateOpportunity(
        id: id,
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
        eligibleMajors: eligibleMajors,
      );
      opportunities = [
        for (final existing in opportunities)
          if (existing.id == id) updated else existing,
      ];
      if (selectedOpportunity?.id == id) {
        selectedOpportunity = updated;
      }
    } on ApiException catch (error) {
      formErrorMessage = error.message;
    }

    isSubmitting = false;
    notifyListeners();
    return updated;
  }

  Future<bool> deleteOpportunity(int id) async {
    _deletingIds.add(id);
    deleteErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      await repository.deleteOpportunity(id);
      opportunities = opportunities.where((o) => o.id != id).toList();
      if (selectedOpportunity?.id == id) {
        selectedOpportunity = null;
      }
      success = true;
    } on ApiException catch (error) {
      deleteErrorMessage = error.message;
    }

    _deletingIds.remove(id);
    notifyListeners();
    return success;
  }

  void clearFormError() {
    formErrorMessage = null;
    notifyListeners();
  }

  void clearDeleteError() {
    deleteErrorMessage = null;
    notifyListeners();
  }

  /// Clears all opportunity state — called when the signed-in user
  /// changes.
  void reset() {
    opportunities = [];
    isLoadingList = false;
    listErrorMessage = null;
    selectedOpportunity = null;
    isLoadingDetails = false;
    detailsErrorMessage = null;
    isSubmitting = false;
    formErrorMessage = null;
    _deletingIds.clear();
    deleteErrorMessage = null;
    _pendingListFetch = null;
    _pendingDetailsFetch = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
