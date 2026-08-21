import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/skills/data/student_skill_repository.dart';
import '../models/student_skill_model.dart';
import 'auth_provider.dart';

/// Holds the authenticated student's own skill list (Phase 8A-6.1's "My
/// Skills" screen), each carrying its evidence `source` so the student can
/// see which skills are CV-supported vs self-declared, plus the ability to
/// remove one from their own profile.
///
/// Adding a skill is out of scope here: accepting an AI CV suggestion
/// already goes through `StudentCvProvider.addSelectedSkills`, and the
/// ordinary manual-add flow has no Flutter UI yet.
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

  void reset() {
    skills = [];
    isLoading = false;
    errorMessage = null;
    actionErrorMessage = null;
    busySkillIds.clear();
    _pendingFetch = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
