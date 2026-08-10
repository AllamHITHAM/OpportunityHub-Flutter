import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/assessments/data/assessment_repository.dart';
import '../models/quiz_attempt_model.dart';
import '../models/quiz_model.dart';
import 'auth_provider.dart';

/// Holds the currently-viewed Quiz, the student's own attempt at it, and
/// their in-progress answer selections, for the Student quiz-taking flow.
///
/// Kept entirely separate from the read-only `StudentAssessmentProvider` —
/// that provider only ever reads an existing Assessment (which may nest a
/// student-safe [QuizModel] via [AssessmentModel.quiz]), while this one owns
/// the write path (start/answer/submit) `StudentAssessmentProvider` must
/// never expose. After a successful [submit], the screen layer (not this
/// provider) is responsible for force-refreshing
/// `StudentAssessmentProvider` so the parent application-details screen
/// picks up the newly `completed` assessment/result — the same
/// provider-bridging pattern `OrganizationQuizEditorScreen`'s callers
/// already use for `OrganizationAssessmentProvider`.
class StudentQuizProvider extends ChangeNotifier {
  StudentQuizProvider({required this.repository, required this._authProvider}) {
    _authProvider.addListener(_handleAuthChanged);
  }

  final AssessmentRepository repository;
  final AuthProvider _authProvider;

  QuizModel? quiz;
  QuizAttemptModel? attempt;

  /// Question ID -> the student's currently-selected answer text. Restored
  /// from [attempt]'s own `answers` on [start] (defensive — in practice an
  /// unsubmitted attempt never has any yet), and is the only source of
  /// truth [submit] sends to the backend.
  final Map<int, String> selectedAnswers = {};

  /// Which assessment [quiz] (or the in-flight fetch) belongs to — mirrors
  /// every other provider's `loadedXId` dual role: it identifies both the
  /// currently in-flight load and the most recently completed one, so a
  /// request for a different assessment never reuses this assessment's
  /// in-flight future, and a stale response can never overwrite state once
  /// a newer assessment has been requested.
  int? loadedAssessmentId;

  bool isLoading = false;
  String? errorMessage;

  bool isStarting = false;
  bool isSubmitting = false;
  String? actionErrorMessage;

  /// `true` when the most recent [start] call failed with a 409 — the
  /// backend's "this attempt was already submitted" response, which
  /// (unlike every other Quiz response) carries no attempt data at all, so
  /// there's no score to show. Quiz v1 has no answer-review/attempt-lookup
  /// endpoint, so this is the only way this screen can ever learn a quiz
  /// was already completed without already knowing it from the parent
  /// Assessment — see `StudentQuizScreen`.
  bool startAlreadySubmitted = false;

  /// Raw field-validation errors from the most recent failed submit,
  /// keyed exactly as the backend sent them (e.g. `answers.0.answer`).
  Map<String, List<String>> fieldErrors = {};

  /// The in-flight load fetch, if any — guards against concurrent
  /// duplicate requests for the *same* assessment, without preventing an
  /// explicit refresh once the previous fetch has finished.
  Future<void>? _pendingLoadFetch;

  /// A generation counter identifying the most recently *started* load —
  /// see `StudentAssessmentProvider._loadGeneration` for why this exists
  /// alongside [loadedAssessmentId].
  int _loadGeneration = 0;

  Timer? _timer;

  /// The attempt's real `started_at` — never a locally-recorded tap time,
  /// so a resumed attempt's countdown is exactly as accurate as a freshly
  /// started one, and reopening this screen never grants extra time.
  DateTime? effectiveStartedAt;

  /// `null` when [quiz] has no time limit — no countdown is shown at all
  /// in that case. Updated roughly once a second while an attempt is in
  /// progress.
  Duration? remainingTime;

  /// `true` once [remainingTime] has reached zero — purely a local UX
  /// signal to disable the Submit button; the backend's own time-limit
  /// check on submit is the actual authority (see [submit]'s 422 handling).
  bool isExpired = false;

  void _handleAuthChanged() {
    // A different student may sign in next — don't leak the previous
    // session's quiz/answer data into theirs.
    if (!_authProvider.isAuthenticated) {
      reset();
    }
  }

  /// Loads the published quiz (if any) for [assessmentId]. Safe to call
  /// repeatedly — a fetch already in flight *for the same assessment* is
  /// reused rather than duplicated; a request for a different assessment
  /// always starts its own fresh fetch. Pass [forceRefresh] to start a
  /// fresh one regardless of assessment. Never touches [attempt] or
  /// [selectedAnswers] — those are only ever set by [start]/[submit].
  Future<void> loadQuiz(int assessmentId, {bool forceRefresh = false}) {
    if (forceRefresh || loadedAssessmentId != assessmentId) {
      _pendingLoadFetch = null;
    }
    loadedAssessmentId = assessmentId;
    if (_pendingLoadFetch == null) {
      final generation = ++_loadGeneration;
      _pendingLoadFetch = _performLoad(assessmentId, generation);
    }
    return _pendingLoadFetch!;
  }

  Future<void> _performLoad(int assessmentId, int generation) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    bool stillCurrent() =>
        loadedAssessmentId == assessmentId && generation == _loadGeneration;

    try {
      final result = await repository.getStudentQuiz(assessmentId);
      if (stillCurrent()) {
        quiz = result;
      }
    } on ApiException catch (error) {
      if (stillCurrent()) {
        errorMessage = error.message;
      }
    } catch (_) {
      // An unexpected parsing/runtime error (e.g. malformed backend data)
      // — never leaves the section stuck loading, never shows raw
      // exception/stack-trace text.
      if (stillCurrent()) {
        errorMessage = 'Something went wrong. Please try again.';
      }
    } finally {
      if (stillCurrent()) {
        isLoading = false;
        _pendingLoadFetch = null;
      }
      notifyListeners();
    }
  }

  /// Starts (or resumes) the student's one attempt at the currently-loaded
  /// [quiz]. Returns `true` only on success. A duplicate tap while one is
  /// already in flight is ignored. On success, restores [selectedAnswers]
  /// from the attempt's own answers (empty for a genuinely fresh or
  /// resumed-but-unsubmitted attempt) and starts the countdown timer, if
  /// [QuizModel.timeLimitMinutes] is set, from the attempt's real
  /// `started_at` — never reset on a resumed attempt.
  Future<bool> start() async {
    final currentQuiz = quiz;
    if (currentQuiz == null || isStarting) return false;

    isStarting = true;
    actionErrorMessage = null;
    startAlreadySubmitted = false;
    notifyListeners();

    var success = false;
    try {
      final result = await repository.startStudentQuiz(currentQuiz.id);
      attempt = result;
      selectedAnswers
        ..clear()
        ..addAll(result.answers);
      _startTimer(result.startedAt);
      success = true;
    } on ApiException catch (error) {
      actionErrorMessage = error.message;
      startAlreadySubmitted = error.statusCode == 409;
    } catch (_) {
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      isStarting = false;
      notifyListeners();
    }
    return success;
  }

  /// Records [answer] as the student's current selection for [questionId].
  /// A no-op once the attempt is submitted, or while a submit is in
  /// flight — selections must never change once grading has happened or is
  /// about to.
  void selectAnswer({required int questionId, required String answer}) {
    final currentAttempt = attempt;
    if (currentAttempt == null || currentAttempt.isSubmitted || isSubmitting) {
      return;
    }
    selectedAnswers[questionId] = answer;
    notifyListeners();
  }

  bool hasAnswer(int questionId) => selectedAnswers.containsKey(questionId);

  /// Whether every question on [quiz] has a selected answer — mirrors the
  /// backend's own "every question must be answered exactly once"
  /// contract, so the Submit button can be disabled client-side to match.
  bool get allQuestionsAnswered {
    final currentQuiz = quiz;
    if (currentQuiz == null || currentQuiz.questions.isEmpty) return false;
    return currentQuiz.questions.every(
      (question) => selectedAnswers.containsKey(question.id),
    );
  }

  /// Submits [selectedAnswers] for grading. Returns `true` only on success.
  /// A duplicate tap while one is already in flight, or a submit attempted
  /// before every question is answered, is rejected locally before any
  /// request is made. On success, [attempt] is replaced with the backend's
  /// graded result (`submittedAt` non-null, `score` populated) and the
  /// countdown timer is stopped. On failure, [selectedAnswers] is left
  /// completely untouched, so the student never loses their in-progress
  /// selections.
  Future<bool> submit() async {
    final currentQuiz = quiz;
    final currentAttempt = attempt;
    if (currentQuiz == null ||
        currentAttempt == null ||
        currentAttempt.isSubmitted ||
        isSubmitting ||
        !allQuestionsAnswered) {
      return false;
    }

    isSubmitting = true;
    actionErrorMessage = null;
    fieldErrors = {};
    notifyListeners();

    var success = false;
    try {
      final result = await repository.submitStudentQuiz(
        quizId: currentQuiz.id,
        answers: Map<int, String>.from(selectedAnswers),
      );
      attempt = result;
      _stopTimer();
      success = true;
    } on ApiException catch (error) {
      actionErrorMessage = error.message;
      fieldErrors = error.errors ?? {};
    } catch (_) {
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
    return success;
  }

  void _startTimer(DateTime? startedAt) {
    _timer?.cancel();
    _timer = null;
    effectiveStartedAt = startedAt;
    isExpired = false;

    final limitMinutes = quiz?.timeLimitMinutes;
    if (startedAt == null || limitMinutes == null) {
      remainingTime = null;
      return;
    }

    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final startedAt = effectiveStartedAt;
    final limitMinutes = quiz?.timeLimitMinutes;
    if (startedAt == null || limitMinutes == null) return;

    final deadline = startedAt.add(Duration(minutes: limitMinutes));
    final remaining = deadline.difference(DateTime.now());

    if (remaining.isNegative || remaining == Duration.zero) {
      remainingTime = Duration.zero;
      isExpired = true;
      _stopTimer();
    } else {
      remainingTime = remaining;
    }
    notifyListeners();
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Clears all quiz/attempt/answer state — called when the signed-in
  /// student changes.
  void reset() {
    quiz = null;
    attempt = null;
    selectedAnswers.clear();
    loadedAssessmentId = null;
    isLoading = false;
    errorMessage = null;
    isStarting = false;
    isSubmitting = false;
    actionErrorMessage = null;
    startAlreadySubmitted = false;
    fieldErrors = {};
    _stopTimer();
    effectiveStartedAt = null;
    remainingTime = null;
    isExpired = false;
    // Invalidates any load still in flight, the same defense-in-depth
    // `StudentAssessmentProvider.reset()` already applies.
    _loadGeneration++;
    _pendingLoadFetch = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    _stopTimer();
    super.dispose();
  }
}
