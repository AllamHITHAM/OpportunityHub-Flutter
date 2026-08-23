import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../core/utils/cv_file_open_result.dart';
import '../core/utils/cv_file_opener.dart' as file_opener;
import '../features/cv/data/cv_repository.dart';
import '../features/cv/data/picked_cv_file.dart';
import '../features/skills/data/student_skill_repository.dart';
import '../models/cv_model.dart';
import '../models/cv_skill_suggestion_model.dart';
import 'auth_provider.dart';

typedef CvFileAction =
    Future<CvFileOpenResult> Function(Uint8List bytes, String fileName);

/// Holds the authenticated student's CV list and exposes create/delete/
/// set-default actions to the UI.
///
/// Loading state is split into independent flags (list, submitting,
/// per-item busy) rather than one shared `isLoading`, so e.g. deleting one
/// card doesn't visually lock the whole screen or an unrelated action.
class StudentCvProvider extends ChangeNotifier {
  StudentCvProvider({
    required this.repository,
    required this.studentSkillRepository,
    required this._authProvider,
    CvFileAction? viewCvFile,
    CvFileAction? downloadCvFile,
  }) : _viewCvFile = viewCvFile ?? file_opener.viewCvFile,
       _downloadCvFile = downloadCvFile ?? file_opener.downloadCvFile {
    _authProvider.addListener(_handleAuthChanged);
  }

  final CvRepository repository;

  /// The real platform action for View/Download — injectable so tests can
  /// exercise the full orchestration (fetch bytes → hand off → real
  /// success/failure) without a real browser. Defaults to the real,
  /// platform-resolved implementation (`cv_file_opener.dart`).
  final CvFileAction _viewCvFile;
  final CvFileAction _downloadCvFile;

  /// Used only by [addSelectedSkills] to accept AI suggestions through
  /// the existing Student Skill endpoint -- extraction itself never
  /// touches this.
  final StudentSkillRepository studentSkillRepository;
  final AuthProvider _authProvider;

  List<CvModel> cvs = [];
  bool isLoadingList = false;
  String? listErrorMessage;

  bool isSubmitting = false;
  String? formErrorMessage;

  final Set<int> _busyIds = {};
  String? actionErrorMessage;

  /// The in-flight list fetch, if any — guards against concurrent duplicate
  /// requests (e.g. a rebuild triggering another `loadCvs()` call while one
  /// is already running) without preventing an explicit refresh once the
  /// previous fetch has finished.
  Future<void>? _pendingListFetch;

  bool isBusy(int id) => _busyIds.contains(id);

  /// The student's current default CV, if any — exposed for the future
  /// Student Applications apply flow to pre-select without re-deriving
  /// this search itself.
  CvModel? get defaultCv {
    for (final cv in cvs) {
      if (cv.isDefault) return cv;
    }
    return null;
  }

  void _handleAuthChanged() {
    // A different user may sign in next — don't leak the previous
    // student's CVs into their session.
    if (!_authProvider.isAuthenticated) {
      reset();
    }
  }

  /// Loads the student's CVs. Safe to call repeatedly (e.g. from
  /// `initState` and pull-to-refresh) — a fetch already in flight is
  /// reused rather than duplicated; pass [forceRefresh] to start a fresh
  /// one regardless.
  Future<void> loadCvs({bool forceRefresh = false}) {
    if (forceRefresh) {
      _pendingListFetch = null;
    }
    return _pendingListFetch ??= _performLoad();
  }

  Future<void> _performLoad() async {
    isLoadingList = true;
    listErrorMessage = null;
    notifyListeners();

    try {
      cvs = await repository.getStudentCvs();
    } on ApiException catch (error) {
      listErrorMessage = error.message;
    } catch (_) {
      // An unexpected parsing/runtime error (e.g. malformed backend data) —
      // never leaves the screen stuck loading, and never shows raw
      // exception/stack-trace text to the user.
      listErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      isLoadingList = false;
      _pendingListFetch = null;
      notifyListeners();
    }
  }

  Future<CvModel?> createCv({
    required String title,
    required PickedCvFile file,
  }) async {
    isSubmitting = true;
    formErrorMessage = null;
    notifyListeners();

    CvModel? created;
    try {
      created = await repository.createCv(title: title, file: file);
      cvs = [...cvs, created];
    } on ApiException catch (error) {
      formErrorMessage = _bestErrorMessage(error);
    }

    isSubmitting = false;
    notifyListeners();
    return created;
  }

  /// Picks the most useful message for an [ApiException]: the first
  /// field-specific validation message when one exists (e.g. "The title
  /// field must not be greater than 255 characters."), falling back to the
  /// generic top-level message otherwise. Never surfaces raw exception or
  /// stack-trace text — both sources here are always human-readable
  /// strings the backend itself produced.
  String _bestErrorMessage(ApiException error) {
    final fieldErrors = error.errors;
    if (fieldErrors != null) {
      for (final messages in fieldErrors.values) {
        if (messages.isNotEmpty) return messages.first;
      }
    }
    return error.message;
  }

  // -----------------------------------------------------------------
  // View / Download CV (Phase 8A-6.3)
  // -----------------------------------------------------------------
  //
  // Root cause fixed here: "View CV" previously only ever fetched the
  // authenticated PDF bytes into memory and reported success on that
  // alone — nothing was ever done with the bytes, so no tab opened and
  // nothing appeared in Chrome Downloads. View and Download are now two
  // real, separate actions; both still fetch bytes through the exact
  // same secure `CvRepository.downloadCv` endpoint, then hand off to the
  // platform-resolved opener (`cv_file_opener.dart`) — real success means
  // the viewer/tab or the browser download was actually triggered, per
  // [CvFileOpenResult], never merely that bytes arrived.

  final Set<int> _viewingIds = {};
  String? viewErrorMessage;

  bool isViewingCv(int cvId) => _viewingIds.contains(cvId);

  /// Opens [cvId]'s PDF for viewing. A duplicate call for the same CV
  /// while one is already in flight is ignored.
  Future<bool> viewCv(int cvId, String title) =>
      _openFile(cvId, title, _viewingIds, _viewCvFile, (msg) => viewErrorMessage = msg);

  final Set<int> _downloadingIds = {};
  String? downloadErrorMessage;

  bool isDownloading(int cvId) => _downloadingIds.contains(cvId);

  /// Triggers a real browser download of [cvId]'s PDF. A duplicate call
  /// for the same CV while one is already in flight is ignored.
  Future<bool> downloadCvFile(int cvId, String title) => _openFile(
    cvId,
    title,
    _downloadingIds,
    _downloadCvFile,
    (msg) => downloadErrorMessage = msg,
  );

  Future<bool> _openFile(
    int cvId,
    String title,
    Set<int> inFlightIds,
    CvFileAction action,
    void Function(String?) setError,
  ) async {
    if (inFlightIds.contains(cvId)) return false;

    inFlightIds.add(cvId);
    setError(null);
    notifyListeners();

    var success = false;
    try {
      final bytes = await repository.downloadCv(cvId);
      final result = await action(bytes, '$title.pdf');
      success = result.success;
      if (!success) {
        setError(result.errorMessage ?? 'Something went wrong. Please try again.');
      }
    } on ApiException catch (error) {
      setError(error.message);
    } catch (_) {
      setError('Something went wrong. Please try again.');
    } finally {
      inFlightIds.remove(cvId);
      notifyListeners();
    }
    return success;
  }

  /// The rename dialog's own inline error — kept separate from
  /// [actionErrorMessage] (delete/set-default's SnackBar-shown error) so a
  /// rename failure shows inline in the still-open dialog, exactly where
  /// the student is looking, instead of behind it in a SnackBar.
  String? renameErrorMessage;

  /// Renames [id] to [title] via the real backend endpoint (Phase 8A-6.2)
  /// — metadata only, the PDF file is never touched. Shares [_busyIds]
  /// with delete/set-default, so a rename can't race a conflicting action
  /// on the same CV. Only ever confirmed by the backend before the local
  /// list reflects the new title — no optimistic update.
  Future<bool> renameCv(int id, String title) async {
    if (_busyIds.contains(id)) return false;

    _busyIds.add(id);
    renameErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      final updated = await repository.updateTitle(cvId: id, title: title);
      cvs = [for (final cv in cvs) if (cv.id == id) updated else cv];
      success = true;
    } on ApiException catch (error) {
      renameErrorMessage = error.message;
    } finally {
      _busyIds.remove(id);
      notifyListeners();
    }
    return success;
  }

  Future<bool> deleteCv(int id) async {
    // Blocks a duplicate delete for the same CV, and also blocks a
    // conflicting set-default on the same CV while one is already in
    // flight — both actions share `_busyIds`, checked before either starts
    // any work.
    if (_busyIds.contains(id)) return false;

    _busyIds.add(id);
    actionErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      await repository.deleteCv(id);
      cvs = cvs.where((cv) => cv.id != id).toList();
      success = true;
    } on ApiException catch (error) {
      actionErrorMessage = error.message;
    } finally {
      _busyIds.remove(id);
      notifyListeners();
    }
    return success;
  }

  Future<bool> setDefaultCv(int id) async {
    // See deleteCv — the same `_busyIds` guard blocks a duplicate
    // set-default and a conflicting delete on the same CV.
    if (_busyIds.contains(id)) return false;

    _busyIds.add(id);
    actionErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      final updated = await repository.setDefaultCv(id);
      cvs = [
        for (final cv in cvs)
          if (cv.id == updated.id) updated else cv.copyWith(isDefault: false),
      ];
      success = true;
    } on ApiException catch (error) {
      actionErrorMessage = error.message;
    } finally {
      _busyIds.remove(id);
      notifyListeners();
    }
    return success;
  }

  // -----------------------------------------------------------------
  // AI CV Skill Extraction (Phase 8A-6)
  // -----------------------------------------------------------------

  bool isExtracting = false;
  String? extractionErrorMessage;

  /// The CV currently being analyzed, if any -- lets the UI show a
  /// per-card loading state instead of locking the whole screen.
  int? extractingCvId;
  List<CvSkillSuggestion> skillSuggestions = [];

  bool isAddingSkills = false;
  String? addSkillsErrorMessage;

  /// Requests AI-derived skill suggestions for [cvId]. A duplicate tap
  /// while one is already in flight is ignored. Failure preserves the
  /// existing CV list untouched -- only [extractionErrorMessage] and
  /// [skillSuggestions] change.
  Future<void> extractSkills(int cvId) async {
    if (isExtracting) return;

    isExtracting = true;
    extractingCvId = cvId;
    extractionErrorMessage = null;
    skillSuggestions = [];
    notifyListeners();

    try {
      skillSuggestions = await repository.extractSkills(cvId);
    } on ApiException catch (error) {
      extractionErrorMessage = error.message;
    } catch (_) {
      extractionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      isExtracting = false;
      notifyListeners();
    }
  }

  /// Accepts a set of AI-suggested [skillIds] by POSTing each one
  /// individually through the existing Student Skill endpoint -- the AI
  /// extraction step never mutates the student's skills on its own; this
  /// explicit, separate action is the only thing that does. Sent with
  /// `source: 'cv_ai'` and the CV that was analyzed (Phase 8A-6.1), so the
  /// resulting StudentSkill is correctly recorded as CV-supported rather
  /// than self-declared -- the backend independently verifies this claim
  /// against real extraction evidence, so nothing here can spoof it.
  /// Returns `true` only if every skill was added successfully (see
  /// [addSkillsErrorMessage] otherwise). Never triggers a match_score
  /// recalculation -- that stays organization-controlled.
  Future<bool> addSelectedSkills(List<int> skillIds) async {
    if (skillIds.isEmpty || isAddingSkills) return false;

    isAddingSkills = true;
    addSkillsErrorMessage = null;
    notifyListeners();

    var allSucceeded = true;
    final addedIds = <int>{};

    for (final skillId in skillIds) {
      try {
        await studentSkillRepository.addSkill(
          skillId: skillId,
          source: 'cv_ai',
          cvId: extractingCvId,
        );
        addedIds.add(skillId);
      } on ApiException catch (error) {
        allSucceeded = false;
        addSkillsErrorMessage = error.message;
      } catch (_) {
        allSucceeded = false;
        addSkillsErrorMessage = 'Something went wrong. Please try again.';
      }
    }

    skillSuggestions = [
      for (final suggestion in skillSuggestions)
        if (addedIds.contains(suggestion.skillId))
          suggestion.copyWith(alreadyAdded: true)
        else
          suggestion,
    ];

    isAddingSkills = false;
    notifyListeners();
    return allSucceeded;
  }

  /// Clears all CV state — called when the signed-in user changes.
  void reset() {
    cvs = [];
    isLoadingList = false;
    listErrorMessage = null;
    isSubmitting = false;
    formErrorMessage = null;
    _busyIds.clear();
    actionErrorMessage = null;
    renameErrorMessage = null;
    _pendingListFetch = null;
    _viewingIds.clear();
    viewErrorMessage = null;
    _downloadingIds.clear();
    downloadErrorMessage = null;
    isExtracting = false;
    extractionErrorMessage = null;
    extractingCvId = null;
    skillSuggestions = [];
    isAddingSkills = false;
    addSkillsErrorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
