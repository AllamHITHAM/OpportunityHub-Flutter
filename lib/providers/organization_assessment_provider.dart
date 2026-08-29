import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/assessments/data/assessment_repository.dart';
import '../features/assessments/data/interview_create_input.dart';
import '../features/assessments/data/quiz_create_input.dart';
import '../features/offers/data/send_offer_input.dart';
import '../models/assessment_model.dart';
import 'auth_provider.dart';

/// Holds the currently-viewed application's Assessment *history* (Phase
/// 10A.3) and exposes the "create an interview/quiz assessment" action —
/// including "Advance to Interview" (Phase 10A.3), which is just another
/// call to the same [createAssessment] the application's very first
/// Assessment used, now legal once the application's most recent
/// Assessment has been finalized (see [latestAssessment]).
///
/// Kept entirely separate from `OrganizationApplicationsProvider` and
/// `StudentApplicationsProvider` — Assessment is a structurally distinct
/// concern from recruitment-status review, the same separation already
/// applied throughout this app's other provider pairs. Never references
/// `OrganizationApplicationsProvider` directly; the screen layer is
/// responsible for bridging the two (see
/// `OrganizationApplicationsProvider.patchApplication`).
class OrganizationAssessmentProvider extends ChangeNotifier {
  OrganizationAssessmentProvider({
    required this.repository,
    required this._authProvider,
  }) {
    _authProvider.addListener(_handleAuthChanged);
  }

  final AssessmentRepository repository;
  final AuthProvider _authProvider;

  /// The full Assessment *history* for [loadedApplicationId], oldest first
  /// (Phase 10A.3) — before this phase an application could only ever have
  /// one Assessment, so this held at most one element; a completed Quiz
  /// followed by a real "Advance to Interview" Assessment now both live
  /// here, in full, never collapsed down to just one.
  List<AssessmentModel> assessments = [];

  /// The application's *current* Assessment — the last element of
  /// [assessments] (already chronologically ordered by the backend), or
  /// `null` when [assessments] is empty. This is what every action-gating
  /// decision (Complete Interview, Advance to Interview, Send Offer
  /// eligibility mirroring the backend's own `OfferService`) should read,
  /// never [assessments] directly, and never an arbitrary element — the
  /// same "explicit current/latest concept, never an ambiguous single
  /// record" requirement this phase's backend model changes also follow
  /// (see `Application::assessment` on the backend).
  AssessmentModel? get latestAssessment =>
      assessments.isEmpty ? null : assessments.last;

  /// Which application [assessments] (or the in-flight fetch) belongs to —
  /// mirrors `OrganizationApplicationsProvider._pendingListOpportunityId`'s
  /// dual role: it identifies both the currently in-flight load and the
  /// most recently completed one, so a request for a different
  /// application never reuses this application's in-flight future, and a
  /// stale response for an old application can never overwrite state once
  /// a newer application has been requested.
  int? loadedApplicationId;

  bool isLoading = false;
  String? errorMessage;

  String? actionErrorMessage;

  /// Raw field-validation errors from the most recent failed create
  /// attempt, keyed exactly as the backend sent them (e.g.
  /// `interview.meeting_link`) — never renamed/stripped here, so no nested
  /// key information is lost; mapping a key back to a specific form field
  /// is the form screen's job, not this provider's.
  Map<String, List<String>> fieldErrors = {};

  /// Application IDs with a create request currently in flight — guards
  /// against a duplicate submission for the same application, exactly like
  /// `OrganizationApplicationsProvider.busyApplicationIds`.
  final Set<int> busyApplicationIds = {};

  /// Interview IDs with a complete request currently in flight — the same
  /// duplicate-submission guard as [busyApplicationIds], keyed by
  /// interview rather than application since completion always targets a
  /// specific Interview.
  final Set<int> completingInterviewIds = {};

  /// Assessment IDs with a manual quiz-result-release request currently in
  /// flight (Phase 10A.2) — the same duplicate-submission guard as
  /// [completingInterviewIds], keyed by Assessment since release always
  /// targets a specific Assessment.
  final Set<int> releasingResultAssessmentIds = {};

  /// Assessment IDs with a next-action decision request currently in
  /// flight (Phase 10A.4A) — the same duplicate-submission guard as
  /// [releasingResultAssessmentIds], shared by all three decision types
  /// ([setNextActionInterview]/[setNextActionOffer]/[setNextActionReject])
  /// since only one decision can ever be in flight for a given Assessment
  /// at once.
  final Set<int> settingNextActionAssessmentIds = {};

  /// The in-flight load fetch, if any — guards against concurrent
  /// duplicate requests for the *same* application, without preventing an
  /// explicit refresh once the previous fetch has finished.
  Future<void>? _pendingLoadFetch;

  bool get isCreating => busyApplicationIds.isNotEmpty;

  bool isCreatingFor(int applicationId) =>
      busyApplicationIds.contains(applicationId);

  bool isCompletingInterview(int interviewId) =>
      completingInterviewIds.contains(interviewId);

  bool isReleasingResult(int assessmentId) =>
      releasingResultAssessmentIds.contains(assessmentId);

  bool isSettingNextAction(int assessmentId) =>
      settingNextActionAssessmentIds.contains(assessmentId);

  bool hasAssessmentFor(int applicationId) =>
      loadedApplicationId == applicationId && assessments.isNotEmpty;

  void _handleAuthChanged() {
    // A different user may sign in next — don't leak the previous
    // organization's assessment data into their session.
    if (!_authProvider.isAuthenticated) {
      reset();
    }
  }

  /// Loads the assessment (if any) for [applicationId]. Safe to call
  /// repeatedly — a fetch already in flight *for the same application* is
  /// reused rather than duplicated; a request for a different application
  /// always starts its own fresh fetch. Pass [forceRefresh] to start a
  /// fresh one regardless of application.
  Future<void> loadForApplication(
    int applicationId, {
    bool forceRefresh = false,
  }) {
    if (forceRefresh || loadedApplicationId != applicationId) {
      _pendingLoadFetch = null;
    }
    loadedApplicationId = applicationId;
    return _pendingLoadFetch ??= _performLoad(applicationId);
  }

  Future<void> _performLoad(int applicationId) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    // Whether [applicationId] is still the one currently being requested
    // by the time this fetch resolves — a later call for a *different*
    // application may have started while this one was in flight, and its
    // (possibly stale) result must never overwrite the newer request's
    // state.
    bool stillCurrent() => loadedApplicationId == applicationId;

    try {
      final result = await repository.getAssessmentsForApplication(
        applicationId,
      );
      if (stillCurrent()) {
        assessments = result;
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

  /// Creates an assessment for [applicationId]. Returns `true` only on
  /// success. A duplicate submission for the same application while one is
  /// already in flight is ignored (returns `false` immediately, no second
  /// repository call).
  ///
  /// Exactly one of [interviewInput]/[quizInput] must be provided, matching
  /// [type]: `type == 'interview'` requires [interviewInput] (and rejects a
  /// [quizInput]); `type == 'quiz'` requires [quizInput] (and rejects an
  /// [interviewInput]). Both present, or the wrong one for [type], is a
  /// local programming error — this never reaches the network, matching
  /// [AssessmentRepository.createAssessment]'s own local validation.
  ///
  /// **Phase 10A.3**: if [applicationId]'s history is already loaded (the
  /// common case for "Advance to Interview" — the organization can only
  /// see that action once a completed Quiz is already showing), the newly
  /// created Assessment is *appended* to [assessments] rather than
  /// replacing it, so the completed Quiz that made this creation legal in
  /// the first place stays visible. Only replaces [assessments] wholesale
  /// (as `[created]`) when this is a genuinely fresh application context —
  /// matches the pre-10A.3 behavior exactly for that case.
  Future<bool> createAssessment({
    required int applicationId,
    required String type,
    InterviewCreateInput? interviewInput,
    QuizCreateInput? quizInput,
  }) async {
    if (type == 'interview' && quizInput != null) {
      throw ArgumentError.value(
        quizInput,
        'quizInput',
        'quizInput must not be provided when type is "interview"',
      );
    }
    if (type == 'quiz' && interviewInput != null) {
      throw ArgumentError.value(
        interviewInput,
        'interviewInput',
        'interviewInput must not be provided when type is "quiz"',
      );
    }

    if (busyApplicationIds.contains(applicationId)) return false;

    busyApplicationIds.add(applicationId);
    actionErrorMessage = null;
    fieldErrors = {};
    notifyListeners();

    var success = false;
    try {
      final created = await repository.createAssessment(
        applicationId: applicationId,
        type: type,
        interviewInput: interviewInput,
        quizInput: quizInput,
      );
      assessments = loadedApplicationId == applicationId
          ? [...assessments, created]
          : [created];
      loadedApplicationId = applicationId;
      success = true;
    } on ApiException catch (error) {
      actionErrorMessage = error.message;
      fieldErrors = error.errors ?? {};
    } catch (_) {
      // An unexpected parsing/runtime error — never propagates as a raw
      // exception, never shows raw exception/stack-trace text, and never
      // touches `assessments`, so the previous state is preserved exactly
      // as it was before this attempt.
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      busyApplicationIds.remove(applicationId);
      notifyListeners();
    }
    return success;
  }

  /// Phase 10A.4B — advances [applicationId]'s candidate straight to the
  /// Opportunity's already-published shared Quiz template. Same
  /// busy-guard/state-update shape as [createAssessment], but creates only
  /// a new Assessment referencing the shared Quiz, never a new Quiz row.
  ///
  /// A `422` here most often means the shared Quiz isn't published yet
  /// (`actionErrorMessage` carries the backend's own clear message, e.g.
  /// `"This opportunity's quiz is not published yet."`) — surfaced as-is,
  /// never replaced with a generic message.
  Future<bool> advanceToSharedQuiz(int applicationId) async {
    if (busyApplicationIds.contains(applicationId)) return false;

    busyApplicationIds.add(applicationId);
    actionErrorMessage = null;
    fieldErrors = {};
    notifyListeners();

    var success = false;
    try {
      final created = await repository.advanceToSharedQuiz(applicationId);
      assessments = loadedApplicationId == applicationId
          ? [...assessments, created]
          : [created];
      loadedApplicationId = applicationId;
      success = true;
    } on ApiException catch (error) {
      actionErrorMessage = error.message;
    } catch (_) {
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      busyApplicationIds.remove(applicationId);
      notifyListeners();
    }
    return success;
  }

  /// Completes [interviewId] (belonging to [applicationId]'s currently
  /// tracked assessment) and, only on success, refreshes [assessments] from
  /// the backend so the completed Interview's `status`/`result`/nested
  /// `interview` all reflect the post-completion state — the completion
  /// endpoint itself returns
  /// the updated Interview, not the Assessment shape this provider holds,
  /// so a targeted reload through the same [loadForApplication] path
  /// already used elsewhere is the least-coupled way to stay in sync
  /// without duplicating the backend's own decision -> result mapping
  /// here. Returns `true` only on success. A duplicate submission for the
  /// same interview while one is already in flight is ignored (returns
  /// `false` immediately, no second repository call).
  Future<bool> completeInterview({
    required int applicationId,
    required int interviewId,
    String? decision,
    int? rating,
    String? companyFeedback,
  }) async {
    if (completingInterviewIds.contains(interviewId)) return false;

    completingInterviewIds.add(interviewId);
    actionErrorMessage = null;
    fieldErrors = {};
    notifyListeners();

    var success = false;
    try {
      await repository.completeInterview(
        interviewId: interviewId,
        decision: decision,
        rating: rating,
        companyFeedback: companyFeedback,
      );

      await loadForApplication(applicationId, forceRefresh: true);
      success = true;
    } on ApiException catch (error) {
      actionErrorMessage = error.message;
      fieldErrors = error.errors ?? {};
    } catch (_) {
      // An unexpected parsing/runtime error — never propagates as a raw
      // exception, never shows raw exception/stack-trace text, and never
      // touches `assessments`, so the previous state is preserved exactly
      // as it was before this attempt.
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      completingInterviewIds.remove(interviewId);
      notifyListeners();
    }
    return success;
  }

  /// Manually releases [assessmentId]'s already-graded Quiz result to the
  /// Student (Phase 10A.2). On success, replaces the matching element of
  /// [assessments] in place from the response (Phase 10A.3 — [assessments]
  /// is now a history, so this can no longer just overwrite a single
  /// field) — mirroring [createAssessment]'s own direct-assignment pattern
  /// rather than [completeInterview]'s reload-via [loadForApplication],
  /// since `releaseQuizResult` already returns the full updated Assessment
  /// and a second round-trip would be redundant. Only applied when
  /// [applicationId] is still the one currently loaded, so a release for an
  /// application the organization has since navigated away from can never
  /// overwrite newer state. Returns `true` only on success. A duplicate
  /// submission for the same assessment while one is already in flight is
  /// ignored (returns `false` immediately, no second repository call).
  Future<bool> releaseQuizResult({
    required int applicationId,
    required int assessmentId,
  }) async {
    if (releasingResultAssessmentIds.contains(assessmentId)) return false;

    releasingResultAssessmentIds.add(assessmentId);
    actionErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      final updated = await repository.releaseQuizResult(assessmentId);
      if (loadedApplicationId == applicationId) {
        assessments = [
          for (final existing in assessments)
            existing.id == updated.id ? updated : existing,
        ];
      }
      success = true;
    } on ApiException catch (error) {
      actionErrorMessage = error.message;
    } catch (_) {
      // An unexpected parsing/runtime error — never propagates as a raw
      // exception, never shows raw exception/stack-trace text, and never
      // touches `assessments`, so the previous state is preserved exactly
      // as it was before this attempt.
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      releasingResultAssessmentIds.remove(assessmentId);
      notifyListeners();
    }
    return success;
  }

  /// Stages "Advance to Interview" as [assessmentId]'s next-step decision
  /// (Phase 10A.4A). On success, replaces the matching element of
  /// [assessments] in place from the response (which now carries
  /// `next_action`/`next_action_assessment`), the same pattern
  /// [releaseQuizResult] already uses. Returns `true` only on success. A
  /// duplicate submission for the same assessment while one is already in
  /// flight is ignored.
  Future<bool> setNextActionInterview({
    required int applicationId,
    required int assessmentId,
    required InterviewCreateInput input,
  }) => _setNextAction(
    applicationId: applicationId,
    assessmentId: assessmentId,
    call: () => repository.setNextActionInterview(assessmentId, input),
  );

  /// Stages "Proceed to Offer" as [assessmentId]'s next-step decision
  /// (Phase 10A.4A). See [setNextActionInterview] for the shared
  /// state-update/error-handling behavior.
  Future<bool> setNextActionOffer({
    required int applicationId,
    required int assessmentId,
    required SendOfferInput input,
  }) => _setNextAction(
    applicationId: applicationId,
    assessmentId: assessmentId,
    call: () => repository.setNextActionOffer(assessmentId, input),
  );

  /// Stages "Reject" as [assessmentId]'s next-step decision (Phase
  /// 10A.4A). See [setNextActionInterview] for the shared state-update/
  /// error-handling behavior.
  Future<bool> setNextActionReject({
    required int applicationId,
    required int assessmentId,
  }) => _setNextAction(
    applicationId: applicationId,
    assessmentId: assessmentId,
    call: () => repository.setNextActionReject(assessmentId),
  );

  Future<bool> _setNextAction({
    required int applicationId,
    required int assessmentId,
    required Future<AssessmentModel> Function() call,
  }) async {
    if (settingNextActionAssessmentIds.contains(assessmentId)) return false;

    settingNextActionAssessmentIds.add(assessmentId);
    actionErrorMessage = null;
    fieldErrors = {};
    notifyListeners();

    var success = false;
    try {
      final updated = await call();
      if (loadedApplicationId == applicationId) {
        assessments = [
          for (final existing in assessments)
            existing.id == updated.id ? updated : existing,
        ];
      }
      success = true;
    } on ApiException catch (error) {
      actionErrorMessage = error.message;
      fieldErrors = error.errors ?? {};
    } catch (_) {
      // An unexpected parsing/runtime error — never propagates as a raw
      // exception, never shows raw exception/stack-trace text, and never
      // touches `assessments`, so the previous state is preserved exactly
      // as it was before this attempt.
      actionErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      settingNextActionAssessmentIds.remove(assessmentId);
      notifyListeners();
    }
    return success;
  }

  void clearActionError() {
    actionErrorMessage = null;
    notifyListeners();
  }

  void clearFieldErrors() {
    fieldErrors = {};
    notifyListeners();
  }

  /// Clears all assessment state — called when the signed-in user changes.
  void reset() {
    assessments = [];
    loadedApplicationId = null;
    isLoading = false;
    errorMessage = null;
    actionErrorMessage = null;
    fieldErrors = {};
    busyApplicationIds.clear();
    completingInterviewIds.clear();
    releasingResultAssessmentIds.clear();
    _pendingLoadFetch = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
