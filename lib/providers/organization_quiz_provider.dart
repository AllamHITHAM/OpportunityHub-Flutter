import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/assessments/data/assessment_repository.dart';
import '../features/assessments/data/question_input.dart';
import '../models/question_model.dart';
import '../models/quiz_model.dart';
import 'auth_provider.dart';

/// Holds the currently-viewed Quiz (and its questions) for the Organization
/// authoring flow, and exposes the add/update/delete-question and publish
/// actions.
///
/// Kept entirely separate from `OrganizationAssessmentProvider` — Assessment
/// creation/loading is a structurally distinct concern from Quiz
/// question-authoring, the same separation already applied throughout this
/// app's other provider pairs (see `OrganizationApplicationsProvider` vs.
/// `OrganizationAssessmentProvider`). Never references
/// `OrganizationAssessmentProvider` directly; the screen layer bridges the
/// two when needed (e.g. re-loading the Assessment after leaving the Quiz
/// editor), the same way `ScheduleInterviewScreen` bridges
/// `OrganizationAssessmentProvider`/`OrganizationApplicationsProvider`.
class OrganizationQuizProvider extends ChangeNotifier {
  OrganizationQuizProvider({
    required this.repository,
    required this._authProvider,
  }) {
    _authProvider.addListener(_handleAuthChanged);
  }

  final AssessmentRepository repository;
  final AuthProvider _authProvider;

  QuizModel? quiz;

  /// Which assessment [quiz] (or the in-flight fetch) belongs to — mirrors
  /// `OrganizationAssessmentProvider.loadedApplicationId`'s dual role: it
  /// identifies both the currently in-flight load and the most recently
  /// completed one, so a request for a different assessment never reuses
  /// this assessment's in-flight future, and a stale response for an old
  /// assessment can never overwrite state once a newer assessment has been
  /// requested.
  int? loadedAssessmentId;

  bool isLoading = false;
  String? errorMessage;

  String? actionErrorMessage;

  /// Raw field-validation errors from the most recent failed
  /// create/update-question attempt, keyed exactly as the backend sent them
  /// — never renamed/stripped here; mapping a key back to a specific form
  /// field is the form's job, not this provider's.
  Map<String, List<String>> fieldErrors = {};

  /// Question IDs with an update/delete request currently in flight —
  /// guards against a duplicate action on the same question, exactly like
  /// `OrganizationAssessmentProvider.busyApplicationIds`. A not-yet-created
  /// question has no ID yet, so question *creation* uses
  /// [isCreatingQuestion] instead.
  final Set<int> busyQuestionIds = {};

  bool isCreatingQuestion = false;
  bool isPublishing = false;

  /// The in-flight load fetch, if any — guards against concurrent
  /// duplicate requests for the *same* assessment, without preventing an
  /// explicit refresh once the previous fetch has finished.
  Future<void>? _pendingLoadFetch;

  bool isBusyQuestion(int id) => busyQuestionIds.contains(id);

  void _handleAuthChanged() {
    // A different user may sign in next — don't leak the previous
    // organization's quiz data into their session.
    if (!_authProvider.isAuthenticated) {
      reset();
    }
  }

  /// Loads the quiz (if any) for [assessmentId]. Safe to call repeatedly —
  /// a fetch already in flight *for the same assessment* is reused rather
  /// than duplicated; a request for a different assessment always starts
  /// its own fresh fetch. Pass [forceRefresh] to start a fresh one
  /// regardless of assessment.
  Future<void> loadQuiz(int assessmentId, {bool forceRefresh = false}) {
    if (forceRefresh || loadedAssessmentId != assessmentId) {
      _pendingLoadFetch = null;
    }
    loadedAssessmentId = assessmentId;
    return _pendingLoadFetch ??= _performLoad(assessmentId);
  }

  Future<void> _performLoad(int assessmentId) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    // Whether [assessmentId] is still the one currently being requested by
    // the time this fetch resolves — a later call for a *different*
    // assessment may have started while this one was in flight, and its
    // (possibly stale) result must never overwrite the newer request's
    // state.
    bool stillCurrent() => loadedAssessmentId == assessmentId;

    try {
      final result = await repository.getOrganizationQuiz(assessmentId);
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

  /// Adds a question to the currently-loaded [quiz]. Returns `true` only on
  /// success. A duplicate submission while one is already in flight is
  /// ignored (returns `false` immediately, no second repository call), and
  /// a published quiz is rejected locally before any request is made —
  /// defense-in-depth alongside the UI hiding this action for a published
  /// quiz, and the backend's own `422` if this were somehow still reached.
  Future<bool> createQuestion(QuestionInput input) async {
    final currentQuiz = quiz;
    if (currentQuiz == null || isCreatingQuestion) return false;

    if (currentQuiz.status != 'draft') {
      actionErrorMessage = 'Published quizzes cannot be modified';
      notifyListeners();
      return false;
    }

    isCreatingQuestion = true;
    actionErrorMessage = null;
    fieldErrors = {};
    notifyListeners();

    var success = false;
    try {
      final created = await repository.createQuizQuestion(
        quizId: currentQuiz.id,
        input: input,
      );
      quiz = _withQuestions(currentQuiz, [...currentQuiz.questions, created]);
      success = true;
    } on ApiException catch (error) {
      actionErrorMessage = error.message;
      fieldErrors = error.errors ?? {};
    } catch (_) {
      // An unexpected parsing/runtime error — never propagates as a raw
      // exception, never touches `quiz`, so the previous state is
      // preserved exactly as it was before this attempt.
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      isCreatingQuestion = false;
      notifyListeners();
    }
    return success;
  }

  /// Updates [questionId] on the currently-loaded [quiz]. Returns `true`
  /// only on success. Same duplicate-submit and published-quiz guards as
  /// [createQuestion], scoped to this one question via [busyQuestionIds].
  Future<bool> updateQuestion({
    required int questionId,
    required QuestionInput input,
  }) async {
    final currentQuiz = quiz;
    if (currentQuiz == null || busyQuestionIds.contains(questionId)) {
      return false;
    }

    if (currentQuiz.status != 'draft') {
      actionErrorMessage = 'Published quizzes cannot be modified';
      notifyListeners();
      return false;
    }

    busyQuestionIds.add(questionId);
    actionErrorMessage = null;
    fieldErrors = {};
    notifyListeners();

    var success = false;
    try {
      final updated = await repository.updateQuizQuestion(
        quizId: currentQuiz.id,
        questionId: questionId,
        input: input,
      );
      quiz = _withQuestions(currentQuiz, [
        for (final question in currentQuiz.questions)
          if (question.id == questionId) updated else question,
      ]);
      success = true;
    } on ApiException catch (error) {
      actionErrorMessage = error.message;
      fieldErrors = error.errors ?? {};
    } catch (_) {
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      busyQuestionIds.remove(questionId);
      notifyListeners();
    }
    return success;
  }

  /// Deletes [questionId] from the currently-loaded [quiz]. Returns `true`
  /// only on success. Same duplicate-submit and published-quiz guards as
  /// [updateQuestion].
  Future<bool> deleteQuestion(int questionId) async {
    final currentQuiz = quiz;
    if (currentQuiz == null || busyQuestionIds.contains(questionId)) {
      return false;
    }

    if (currentQuiz.status != 'draft') {
      actionErrorMessage = 'Published quizzes cannot be modified';
      notifyListeners();
      return false;
    }

    busyQuestionIds.add(questionId);
    actionErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      await repository.deleteQuizQuestion(
        quizId: currentQuiz.id,
        questionId: questionId,
      );
      quiz = _withQuestions(currentQuiz, [
        for (final question in currentQuiz.questions)
          if (question.id != questionId) question,
      ]);
      success = true;
    } on ApiException catch (error) {
      actionErrorMessage = error.message;
    } catch (_) {
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      busyQuestionIds.remove(questionId);
      notifyListeners();
    }
    return success;
  }

  /// Publishes the currently-loaded [quiz]. Returns `true` only on success.
  /// A duplicate submission while one is already in flight is ignored, and
  /// an already-published quiz is rejected locally before any request is
  /// made. On success, [quiz] is replaced wholesale with the backend's
  /// returned quiz (already `status: published`, with
  /// [QuizModel.assessmentStatus] reflecting the assessment's new
  /// `scheduled` status) — no full reload is triggered.
  Future<bool> publish() async {
    final currentQuiz = quiz;
    if (currentQuiz == null || isPublishing) return false;

    if (currentQuiz.status != 'draft') {
      actionErrorMessage = 'Only draft quizzes can be published';
      notifyListeners();
      return false;
    }

    isPublishing = true;
    actionErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      quiz = await repository.publishQuiz(currentQuiz.id);
      success = true;
    } on ApiException catch (error) {
      // Preserves the draft `quiz` exactly as it was -- in particular for
      // the documented zero-question 422, which must never look like it
      // silently published.
      actionErrorMessage = error.message;
    } catch (_) {
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      isPublishing = false;
      notifyListeners();
    }
    return success;
  }

  QuizModel _withQuestions(QuizModel base, List<QuestionModel> questions) {
    final sorted = [...questions]
      ..sort((a, b) {
        final byPosition = a.position.compareTo(b.position);
        return byPosition != 0 ? byPosition : a.id.compareTo(b.id);
      });

    return QuizModel(
      id: base.id,
      assessmentId: base.assessmentId,
      title: base.title,
      instructions: base.instructions,
      timeLimitMinutes: base.timeLimitMinutes,
      passingScore: base.passingScore,
      status: base.status,
      questions: sorted,
      createdAt: base.createdAt,
      updatedAt: base.updatedAt,
      assessmentStatus: base.assessmentStatus,
    );
  }

  void clearActionErrors() {
    actionErrorMessage = null;
    fieldErrors = {};
    notifyListeners();
  }

  /// Clears all quiz state — called when the signed-in user changes.
  void reset() {
    quiz = null;
    loadedAssessmentId = null;
    isLoading = false;
    errorMessage = null;
    actionErrorMessage = null;
    fieldErrors = {};
    busyQuestionIds.clear();
    isCreatingQuestion = false;
    isPublishing = false;
    _pendingLoadFetch = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
