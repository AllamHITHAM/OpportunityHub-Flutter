import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/skills/data/student_skill_repository.dart';
import '../models/skill_model.dart';
import '../models/student_skill_model.dart';
import 'auth_provider.dart';

/// Holds the authenticated student's own skill list (Phase 8A-6.1's "My
/// Skills" screen), each carrying its evidence `source` so the student can
/// see which skills are CV-supported vs self-declared; the real Skill
/// catalog for a Manual Add Skill flow (Phase 8A-6.3); and the ability to
/// add or remove a skill from the student's own profile.
///
/// Accepting an AI CV suggestion still goes through
/// `StudentCvProvider.addSelectedSkills` -- entirely separate from
/// [addSkill] here, which is always `source: manual` (the backend, never
/// this provider, is what actually assigns the source).
class StudentSkillProvider extends ChangeNotifier {
  StudentSkillProvider({
    required this.repository,
    required this._authProvider,
  }) {
    _authProvider.addListener(_handleAuthChanged);
  }

  final StudentSkillRepository repository;
  final AuthProvider _authProvider;

  List<StudentSkillModel> skills = [];
  bool isLoading = false;
  String? errorMessage;

  String? actionErrorMessage;

  /// `StudentSkill` row ids with a delete request currently in flight --
  /// guards against a duplicate action for the same row, exactly like
  /// `AdminSkillsProvider.busySkillIds`. Independent per row, so removing
  /// one skill never blocks another.
  final Set<int> busySkillIds = {};

  /// The in-flight list fetch, if any — guards against concurrent
  /// duplicate requests, without preventing an explicit refresh once the
  /// previous fetch has finished. Mirrors `StudentCvProvider._pendingListFetch`.
  Future<void>? _pendingFetch;

  /// The real, full Skill catalog (Phase 8A-6.3) for the Manual Add Skill
  /// picker -- never a partial or hardcoded list.
  List<SkillModel> catalogSkills = [];
  bool isLoadingCatalog = false;
  String? catalogErrorMessage;
  Future<void>? _pendingCatalogFetch;

  bool isAddingSkill = false;
  String? addErrorMessage;

  bool isBusy(int studentSkillId) => busySkillIds.contains(studentSkillId);

  void _handleAuthChanged() {
    if (!_authProvider.isAuthenticated) {
      reset();
    }
  }

  Future<void> load({bool forceRefresh = false}) {
    if (forceRefresh) {
      _pendingFetch = null;
    }
    return _pendingFetch ??= _performLoad();
  }

  Future<void> _performLoad() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      skills = await repository.getStudentSkills();
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

  /// Removes [studentSkillId] (a `StudentSkill` row id) from the student's
  /// own profile. Returns `true` only on success. A duplicate submission
  /// for the same row while one is already in flight is ignored (returns
  /// `false` immediately, no second repository call). Only ever deletes
  /// the student's relationship row -- the global `Skill` catalog entry is
  /// never touched (see `StudentSkillRepository.deleteSkill`).
  Future<bool> deleteSkill(int studentSkillId) async {
    if (busySkillIds.contains(studentSkillId)) return false;

    busySkillIds.add(studentSkillId);
    actionErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      await repository.deleteSkill(studentSkillId);
      skills = skills.where((skill) => skill.id != studentSkillId).toList();
      success = true;
    } on ApiException catch (error) {
      // Never touches `skills`, so the skill stays visible exactly as it
      // was before this attempt.
      actionErrorMessage = error.message;
    } catch (_) {
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      busySkillIds.remove(studentSkillId);
      notifyListeners();
    }
    return success;
  }

  /// Fetches the real Skill catalog for the Manual Add Skill picker.
  /// Mirrors [load]'s single-in-flight-request pattern, but cached across
  /// sheet opens by default -- the catalog rarely changes, so reopening
  /// the sheet doesn't need a fresh network round trip every time; pass
  /// [forceRefresh] to force one anyway.
  Future<void> loadCatalog({bool forceRefresh = false}) {
    if (forceRefresh) {
      _pendingCatalogFetch = null;
    }
    if (!forceRefresh && catalogSkills.isNotEmpty) {
      return _pendingCatalogFetch ?? Future.value();
    }
    return _pendingCatalogFetch ??= _performLoadCatalog();
  }

  Future<void> _performLoadCatalog() async {
    isLoadingCatalog = true;
    catalogErrorMessage = null;
    notifyListeners();

    try {
      catalogSkills = await repository.getSkillCatalog();
    } on ApiException catch (error) {
      catalogErrorMessage = error.message;
    } catch (_) {
      catalogErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      isLoadingCatalog = false;
      _pendingCatalogFetch = null;
      notifyListeners();
    }
  }

  /// Manually adds [skillId] at the student's chosen [level] to their own
  /// profile -- always `source: manual`; the backend is the sole authority
  /// on what source ends up stored (see `StudentSkillRepository.addSkill`).
  /// Returns `true` only once the backend has actually persisted the row,
  /// which is then appended to [skills] from the real response -- never a
  /// locally-fabricated entry. A duplicate submission while one is already
  /// in flight is ignored (returns `false` immediately, no second
  /// repository call).
  Future<bool> addSkill({required int skillId, required String level}) async {
    if (isAddingSkill) return false;

    isAddingSkill = true;
    addErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      final added = await repository.addSkill(skillId: skillId, level: level);
      skills = [...skills, added];
      success = true;
    } on ApiException catch (error) {
      addErrorMessage = error.message;
    } catch (_) {
      addErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      isAddingSkill = false;
      notifyListeners();
    }
    return success;
  }

  void reset() {
    skills = [];
    isLoading = false;
    errorMessage = null;
    actionErrorMessage = null;
    busySkillIds.clear();
    _pendingFetch = null;
    catalogSkills = [];
    isLoadingCatalog = false;
    catalogErrorMessage = null;
    _pendingCatalogFetch = null;
    isAddingSkill = false;
    addErrorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
