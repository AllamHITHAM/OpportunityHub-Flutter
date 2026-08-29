import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/organization/data/organization_dashboard_repository.dart';
import '../models/organization_dashboard_stats_model.dart';
import 'auth_provider.dart';

/// Holds the Organization dashboard's real recruitment statistics.
///
/// Kept entirely separate from `OrganizationOpportunitiesProvider`/
/// `OrganizationApplicationsProvider` — Dashboard is an independent
/// resource, the same separation already applied throughout this app's
/// other provider pairs (see `AdminDashboardProvider`, which this mirrors
/// exactly).
class OrganizationDashboardProvider extends ChangeNotifier {
  OrganizationDashboardProvider({
    required this.repository,
    required this._authProvider,
  }) {
    _authProvider.addListener(_handleAuthChanged);
  }

  final OrganizationDashboardRepository repository;
  final AuthProvider _authProvider;

  OrganizationDashboardStatsModel? stats;
  bool isLoading = false;
  String? errorMessage;

  /// The in-flight load fetch, if any — guards against concurrent
  /// duplicate requests, exactly like every other provider's
  /// single-in-flight-fetch pattern in this app. There's no per-ID keying
  /// here because there's only ever one dashboard to load, not one per
  /// some ID.
  Future<void>? _pendingLoad;

  void _handleAuthChanged() {
    // A different organization may sign in next — don't leak the previous
    // session's statistics into theirs.
    if (!_authProvider.isAuthenticated) {
      reset();
    }
  }

  /// Loads the dashboard statistics. Safe to call repeatedly — a fetch
  /// already in flight is reused rather than duplicated. Pass
  /// [forceRefresh] to start a fresh one regardless.
  Future<void> load({bool forceRefresh = false}) {
    if (forceRefresh) {
      _pendingLoad = null;
    }
    return _pendingLoad ??= _performLoad();
  }

  Future<void> _performLoad() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final result = await repository.getDashboardStats();
      stats = result;
    } on ApiException catch (error) {
      // Deliberately never touches `stats` — a refresh failure must never
      // blank out statistics the organization is already looking at.
      errorMessage = error.message;
    } catch (_) {
      // An unexpected parsing/runtime error (e.g. malformed backend data)
      // — never leaves the dashboard stuck loading, never shows raw
      // exception/stack-trace text, and never touches `stats`.
      errorMessage = 'Something went wrong. Please try again.';
    } finally {
      isLoading = false;
      _pendingLoad = null;
      notifyListeners();
    }
  }

  /// Clears all dashboard state — called when the signed-in user changes.
  void reset() {
    stats = null;
    isLoading = false;
    errorMessage = null;
    _pendingLoad = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
