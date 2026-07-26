import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/opportunities/data/opportunity_repository.dart';
import '../models/opportunity_model.dart';
import 'auth_provider.dart';

/// Holds the student-facing browsable-opportunities list (with search,
/// filters, and pagination) and detail state.
///
/// This is deliberately a separate provider from
/// `OrganizationOpportunitiesProvider` rather than a shared one — the two
/// serve genuinely different state shapes (search/filter/pagination here vs.
/// create/update/delete there) over the same underlying
/// `OpportunityRepository`, the same way `StudentProfileProvider` and
/// `OrganizationProfileProvider` are separate despite both being "profile"
/// providers.
class StudentOpportunitiesProvider extends ChangeNotifier {
  StudentOpportunitiesProvider({
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

  bool isLoadingMore = false;
  String? loadMoreErrorMessage;

  int _currentPage = 1;
  int _lastPage = 1;
  bool get hasMore => _currentPage < _lastPage;

  OpportunityModel? selectedOpportunity;
  bool isLoadingDetails = false;
  String? detailsErrorMessage;

  // Filters applied to the next (re)fetch — all backend-documented, none
  // invented. `keyword` covers the free-text search box; the rest are
  // discrete filter selections.
  String? opportunityType;
  String? employmentType;
  String? workMode;
  String? experienceLevel;
  String? location;
  String? fieldOfStudy;
  String keyword = '';

  bool get hasActiveFilters =>
      opportunityType != null ||
      employmentType != null ||
      workMode != null ||
      experienceLevel != null ||
      location != null ||
      fieldOfStudy != null;

  /// The in-flight list fetch, if any — guards against concurrent duplicate
  /// requests without preventing an explicit refresh once the previous
  /// fetch has finished.
  Future<void>? _pendingListFetch;
  Future<void>? _pendingDetailsFetch;

  void _handleAuthChanged() {
    // A different user may sign in next — don't leak the previous
    // session's search/filter state or results into theirs.
    if (!_authProvider.isAuthenticated) {
      reset();
    }
  }

  /// Loads (or reloads) page 1 with the current filters/keyword. Safe to
  /// call repeatedly — a fetch already in flight is reused rather than
  /// duplicated; pass [forceRefresh] to start a fresh one regardless (e.g.
  /// pull-to-refresh, or after changing a filter).
  Future<void> loadOpportunities({bool forceRefresh = false}) {
    if (forceRefresh) {
      _pendingListFetch = null;
    }
    return _pendingListFetch ??= _performLoadOpportunities();
  }

  Future<void> _performLoadOpportunities() async {
    isLoadingList = true;
    listErrorMessage = null;
    notifyListeners();

    try {
      final result = await repository.getPublicOpportunities(
        opportunityType: opportunityType,
        employmentType: employmentType,
        workMode: workMode,
        experienceLevel: experienceLevel,
        location: location,
        fieldOfStudy: fieldOfStudy,
        keyword: keyword.isEmpty ? null : keyword,
      );
      opportunities = result.items;
      _currentPage = result.currentPage;
      _lastPage = result.lastPage;
    } on ApiException catch (error) {
      listErrorMessage = error.message;
    }

    isLoadingList = false;
    _pendingListFetch = null;
    notifyListeners();
  }

  /// Fetches the next page and appends it to the current results. A no-op
  /// while a page is already loading or none remains.
  Future<void> loadMore() async {
    if (isLoadingMore || !hasMore) return;

    isLoadingMore = true;
    loadMoreErrorMessage = null;
    notifyListeners();

    try {
      final result = await repository.getPublicOpportunities(
        opportunityType: opportunityType,
        employmentType: employmentType,
        workMode: workMode,
        experienceLevel: experienceLevel,
        location: location,
        fieldOfStudy: fieldOfStudy,
        keyword: keyword.isEmpty ? null : keyword,
        page: _currentPage + 1,
      );
      opportunities = [...opportunities, ...result.items];
      _currentPage = result.currentPage;
      _lastPage = result.lastPage;
    } on ApiException catch (error) {
      loadMoreErrorMessage = error.message;
    }

    isLoadingMore = false;
    notifyListeners();
  }

  /// Updates the free-text search keyword. Does not itself trigger a
  /// fetch — the search screen debounces keystrokes and calls
  /// [loadOpportunities] with `forceRefresh: true` once the user pauses.
  void updateKeyword(String value) {
    keyword = value;
  }

  /// Applies a new set of filter selections and immediately refetches page
  /// 1. Any parameter left unset clears that filter.
  Future<void> applyFilters({
    String? opportunityType,
    String? employmentType,
    String? workMode,
    String? experienceLevel,
    String? location,
    String? fieldOfStudy,
  }) {
    this.opportunityType = opportunityType;
    this.employmentType = employmentType;
    this.workMode = workMode;
    this.experienceLevel = experienceLevel;
    this.location = location;
    this.fieldOfStudy = fieldOfStudy;
    return loadOpportunities(forceRefresh: true);
  }

  Future<void> clearFilters() {
    opportunityType = null;
    employmentType = null;
    workMode = null;
    experienceLevel = null;
    location = null;
    fieldOfStudy = null;
    return loadOpportunities(forceRefresh: true);
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
      selectedOpportunity = await repository.getPublicOpportunity(id);
    } on ApiException catch (error) {
      detailsErrorMessage = error.message;
      selectedOpportunity = null;
    }

    isLoadingDetails = false;
    _pendingDetailsFetch = null;
    notifyListeners();
  }

  /// Clears all browsing state — called when the signed-in user changes.
  void reset() {
    opportunities = [];
    isLoadingList = false;
    listErrorMessage = null;
    isLoadingMore = false;
    loadMoreErrorMessage = null;
    _currentPage = 1;
    _lastPage = 1;
    selectedOpportunity = null;
    isLoadingDetails = false;
    detailsErrorMessage = null;
    opportunityType = null;
    employmentType = null;
    workMode = null;
    experienceLevel = null;
    location = null;
    fieldOfStudy = null;
    keyword = '';
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
