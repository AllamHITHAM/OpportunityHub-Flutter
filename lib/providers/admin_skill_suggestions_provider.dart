import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/admin/data/admin_skill_suggestions_repository.dart';
import '../models/skill_suggestion_model.dart';
import 'auth_provider.dart';

/// Holds the Admin pending skill-suggestion list and exposes the
/// approve/reject actions (Phase 8A-6.1). Kept entirely separate from
/// `AdminSkillsProvider`, mirroring this app's existing per-resource
/// provider separation (see `AdminSkillsProvider`'s own doc comment).
class AdminSkillSuggestionsProvider extends ChangeNotifier {
  AdminSkillSuggestionsProvider({
    required this.repository,
    required this._authProvider,
  }) {
    _authProvider.addListener(_handleAuthChanged);
  }

  final AdminSkillSuggestionsRepository repository;
  final AuthProvider _authProvider;

  List<SkillSuggestionModel> suggestions = [];
  bool isLoading = false;
  String? errorMessage;

  String? actionErrorMessage;

  /// Suggestion IDs with an approve/reject request currently in flight —
  /// guards against a duplicate action for the same suggestion, mirroring
  /// `AdminSkillsProvider.busySkillIds`.
  final Set<int> busySuggestionIds = {};

  Future<void>? _pendingLoad;

  bool isBusy(int suggestionId) => busySuggestionIds.contains(suggestionId);

  void _handleAuthChanged() {
    if (!_authProvider.isAuthenticated) {
      reset();
    }
  }

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
      suggestions = await repository.getPendingSuggestions();
    } on ApiException catch (error) {
      errorMessage = error.message;
    } catch (_) {
      errorMessage = 'Something went wrong. Please try again.';
    } finally {
      isLoading = false;
      _pendingLoad = null;
      notifyListeners();
    }
  }

  /// Approves [suggestionId] and removes it from the local list on
  /// success -- the backend has already created/linked the real Skill by
  /// the time this returns. Returns `true` only on success.
  Future<bool> approve(int suggestionId) =>
      _review(suggestionId, (id) => repository.approve(id));

  /// Rejects [suggestionId] and removes it from the local list on
  /// success. Returns `true` only on success.
  Future<bool> reject(int suggestionId) =>
      _review(suggestionId, (id) => repository.reject(id));

  Future<bool> _review(
    int suggestionId,
    Future<void> Function(int) call,
  ) async {
    if (busySuggestionIds.contains(suggestionId)) return false;

    busySuggestionIds.add(suggestionId);
    actionErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      await call(suggestionId);
      suggestions = suggestions
          .where((suggestion) => suggestion.id != suggestionId)
          .toList();
      success = true;
    } on ApiException catch (error) {
      actionErrorMessage = error.message;
    } catch (_) {
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      busySuggestionIds.remove(suggestionId);
      notifyListeners();
    }
    return success;
  }

  void reset() {
    suggestions = [];
    isLoading = false;
    errorMessage = null;
    actionErrorMessage = null;
    busySuggestionIds.clear();
    _pendingLoad = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
