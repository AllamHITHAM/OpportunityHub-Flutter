import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/admin/data/admin_skills_repository.dart';
import '../models/skill_model.dart';
import 'auth_provider.dart';

/// Holds the Admin skill-management list and exposes the create/update/
/// delete actions.
///
/// Kept entirely separate from `AdminUsersProvider`/
/// `AdminOrganizationsProvider`/`AdminDashboardProvider` — the same
/// per-resource separation already applied throughout this app's other
/// provider pairs (see `OrganizationAssessmentProvider` vs
/// `OrganizationApplicationsProvider`).
class AdminSkillsProvider extends ChangeNotifier {
  AdminSkillsProvider({required this.repository, required this._authProvider}) {
    _authProvider.addListener(_handleAuthChanged);
  }

  final AdminSkillsRepository repository;
  final AuthProvider _authProvider;

  List<SkillModel> skills = [];
  bool isLoading = false;
  String? errorMessage;

  String? actionErrorMessage;

  /// Laravel validation errors from the most recent create/update attempt,
  /// keyed by field name (currently only ever `name`) — cleared at the
  /// start of every new attempt, exactly like
  /// `OrganizationAssessmentProvider.fieldErrors`.
  Map<String, List<String>> fieldErrors = {};

  /// Skill IDs with an update/delete request currently in flight — guards
  /// against a duplicate action for the same skill, exactly like
  /// `AdminOrganizationsProvider.busyOrganizationIds`. Independent per
  /// skill, so acting on one skill never blocks another.
  final Set<int> busySkillIds = {};

  /// Whether a create request is currently in flight — separate from
  /// [busySkillIds] since a not-yet-created skill has no ID to key by.
  bool isCreating = false;

  /// The in-flight list fetch, if any — guards against concurrent
  /// duplicate requests, without preventing an explicit refresh once the
  /// previous fetch has finished.
  Future<void>? _pendingLoad;

  /// A generation counter identifying the most recently started list load
  /// — the same `forceRefresh`-vs-stale-response guard used by
  /// `AdminUsersProvider`/`AdminOrganizationsProvider`. `forceRefresh`
  /// deliberately discards [_pendingLoad] so a fresh fetch starts even
  /// while an old one is still in flight, which means two `getSkills()`
  /// calls can genuinely race; each `_performLoad` call captures its own
  /// generation and only writes `skills`/`errorMessage`/`isLoading`/
  /// [_pendingLoad] if it's still the most recent one by the time it
  /// resolves.
  int _loadGeneration = 0;

  bool isBusy(int skillId) => busySkillIds.contains(skillId);

  void _handleAuthChanged() {
    // A different admin may sign in next — don't leak the previous
    // session's skill list into theirs.
    if (!_authProvider.isAuthenticated) {
      reset();
    }
  }

  /// Loads every skill. Safe to call repeatedly — a fetch already in
  /// flight is reused rather than duplicated. Pass [forceRefresh] to start
  /// a fresh one regardless.
  Future<void> load({bool forceRefresh = false}) {
    if (forceRefresh) {
      _pendingLoad = null;
    }
    return _pendingLoad ??= _performLoad(++_loadGeneration);
  }

  Future<void> _performLoad(int generation) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final result = await repository.getSkills();
      // A forceRefresh started a newer load while this one was still in
      // flight — that newer call already owns `skills`/`errorMessage`, so
      // this now-stale response must not overwrite it.
      if (generation != _loadGeneration) return;
      skills = result;
    } on ApiException catch (error) {
      if (generation != _loadGeneration) return;
      // Deliberately never touches `skills` — a refresh failure must
      // never blank out a list the admin is already looking at.
      errorMessage = error.message;
    } catch (_) {
      if (generation != _loadGeneration) return;
      // An unexpected parsing/runtime error (e.g. malformed backend data)
      // — never leaves the list stuck loading, never shows raw
      // exception/stack-trace text, and never touches `skills`.
      errorMessage = 'Something went wrong. Please try again.';
    } finally {
      // Only the current generation may clear isLoading/_pendingLoad — a
      // stale call's finally must not clear `_pendingLoad` out from under
      // a newer load that's still genuinely in flight.
      if (generation == _loadGeneration) {
        isLoading = false;
        _pendingLoad = null;
      }
      notifyListeners();
    }
  }

  /// Creates a skill named [name]. Returns `true` only on success. A
  /// duplicate submission while one is already in flight is ignored
  /// (returns `false` immediately, no second repository call).
  Future<bool> createSkill({required String name}) async {
    if (isCreating) return false;

    isCreating = true;
    actionErrorMessage = null;
    fieldErrors = {};
    notifyListeners();

    var success = false;
    try {
      final created = await repository.createSkill(name: name);
      skills = [...skills, created];
      success = true;
    } on ApiException catch (error) {
      actionErrorMessage = error.message;
      fieldErrors = error.errors ?? {};
    } catch (_) {
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      isCreating = false;
      notifyListeners();
    }
    return success;
  }

  /// Updates [skillId]'s name to [name]. Returns `true` only on success. A
  /// duplicate submission for the same skill while one is already in
  /// flight is ignored (returns `false` immediately, no second repository
  /// call) — a different skill's update is entirely unaffected.
  Future<bool> updateSkill({required int skillId, required String name}) async {
    if (busySkillIds.contains(skillId)) return false;

    busySkillIds.add(skillId);
    actionErrorMessage = null;
    fieldErrors = {};
    notifyListeners();

    var success = false;
    try {
      final updated = await repository.updateSkill(
        skillId: skillId,
        name: name,
      );
      skills = [
        for (final skill in skills)
          if (skill.id == skillId) updated else skill,
      ];
      success = true;
    } on ApiException catch (error) {
      // Never touches `skills`, so the old name is preserved exactly as
      // it was before this attempt.
      actionErrorMessage = error.message;
      fieldErrors = error.errors ?? {};
    } catch (_) {
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      busySkillIds.remove(skillId);
      notifyListeners();
    }
    return success;
  }

  /// Deletes [skillId]. Returns `true` only on success. A duplicate
  /// submission for the same skill while one is already in flight is
  /// ignored (returns `false` immediately, no second repository call).
  Future<bool> deleteSkill(int skillId) async {
    if (busySkillIds.contains(skillId)) return false;

    busySkillIds.add(skillId);
    actionErrorMessage = null;
    fieldErrors = {};
    notifyListeners();

    var success = false;
    try {
      await repository.deleteSkill(skillId);
      skills = skills.where((skill) => skill.id != skillId).toList();
      success = true;
    } on ApiException catch (error) {
      // Covers the backend's 409 "Cannot delete a skill that is currently
      // in use" — never touches `skills`, so the skill stays in the list
      // exactly as it was before this attempt.
      actionErrorMessage = error.message;
    } catch (_) {
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      busySkillIds.remove(skillId);
      notifyListeners();
    }
    return success;
  }

  void clearActionErrors() {
    actionErrorMessage = null;
    fieldErrors = {};
    notifyListeners();
  }

  /// Clears all skill-management state — called when the signed-in admin
  /// changes.
  void reset() {
    skills = [];
    isLoading = false;
    errorMessage = null;
    actionErrorMessage = null;
    fieldErrors = {};
    busySkillIds.clear();
    isCreating = false;
    _pendingLoad = null;
    // Invalidates any load still in flight — a stale response arriving
    // after a logout/session change must not repopulate the next admin's
    // list with the previous session's data.
    _loadGeneration++;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
