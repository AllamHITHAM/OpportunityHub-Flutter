import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/assessment_model.dart';
import '../../../models/question_model.dart';
import '../../../models/quiz_attempt_model.dart';
import '../../../models/quiz_model.dart';
import '../../../providers/student_quiz_provider.dart';
import '../../opportunities/presentation/opportunity_display.dart';
import '../data/assessment_repository.dart';
import 'assessment_display.dart';

const double _desktopBreakpoint = 1200;

enum _ScreenTier { compact, desktop }

_ScreenTier _tierFor(double width) =>
    width >= _desktopBreakpoint ? _ScreenTier.desktop : _ScreenTier.compact;

/// Real display order for a quiz's questions -- `position` then `id`,
/// mirroring the backend's own `orderBy('position')->orderBy('id')`
/// exactly (`Quiz::questions()`). This tiebreak matters in practice, not
/// just in theory: the Organization authoring form doesn't currently send
/// an explicit `position` when adding a question, so real quizzes often
/// have every question at the backend's own default `position = 0` --
/// without the `id` tiebreak, [List.sort] (not a stable sort in Dart) could
/// reorder such a quiz's questions unpredictably between rebuilds.
List<QuestionModel> _sortedQuestions(List<QuestionModel> questions) {
  final sorted = [...questions];
  sorted.sort((a, b) {
    final byPosition = a.position.compareTo(b.position);
    return byPosition != 0 ? byPosition : a.id.compareTo(b.id);
  });
  return sorted;
}

/// Student Quiz taking — reached by Assessment ID alone (a route parameter,
/// never GoRouter `extra`), matching [AppRoutes.studentQuiz] and the same
/// convention `OrganizationQuizEditorScreen` already uses for its own
/// Assessment-ID-addressed route.
///
/// Deliberately self-contained about the Assessment's own `result` and
/// Opportunity context: Quiz v1 has no attempt-lookup endpoint, so the only
/// way this screen can ever learn the graded [AssessmentModel.result] (or
/// show which Opportunity this quiz belongs to) is by fetching the
/// Assessment directly (via [AssessmentRepository.getStudentAssessment],
/// addressed by this same Assessment ID) — once on load, for header
/// context, and again right after a successful submit, for the graded
/// result — never by reading `StudentAssessmentProvider`, which is
/// read-only and keyed by Application ID, not Assessment ID.
/// `StudentApplicationDetailsScreen` is still responsible for
/// force-refreshing that provider itself once this screen is popped, so its
/// own summary reflects the newly `completed` assessment.
///
/// The Assessment response's `application.opportunity` never carries the
/// organization's name (the backend eager-loads `application.opportunity`
/// only, not `.organizationProfile`) — so only the Opportunity title is
/// shown as header context, never an invented/omitted-then-guessed
/// organization name.
///
/// **Result release (Phase 10A.2)**: `assessment.result` is `null` on the
/// backend response both when grading genuinely hasn't happened yet *and*
/// when it has but hasn't been released to the Student yet
/// (`Quiz.resultReleaseMode` other than `immediate`) — this screen can
/// only ever reach [_QuizResultView] once `attempt.isSubmitted` is true,
/// so within that view a `null` result unambiguously means "submitted,
/// pending release", never "not graded yet".
class StudentQuizScreen extends StatefulWidget {
  const StudentQuizScreen({super.key, required this.assessmentId});

  final int assessmentId;

  @override
  State<StudentQuizScreen> createState() => _StudentQuizScreenState();
}

class _StudentQuizScreenState extends State<StudentQuizScreen> {
  AssessmentModel? _assessment;
  bool _isLoadingAssessment = false;
  String? _assessmentErrorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StudentQuizProvider>().loadQuiz(widget.assessmentId);
      unawaited(_loadAssessment());
    });
  }

  /// Fetches the parent Assessment — used both for the Opportunity-title
  /// header context (available as soon as this loads, before the quiz even
  /// starts) and, once the attempt is submitted, the graded `result` (only
  /// ever exposed on `Assessment`, never on `QuizAttemptModel` — see this
  /// class's own doc comment). Called once on load and again after a
  /// successful submit; safe either way since [_isLoadingAssessment]/
  /// [_assessmentErrorMessage] are only ever rendered by [_QuizResultView],
  /// which doesn't exist yet on the first call.
  Future<void> _loadAssessment() async {
    setState(() {
      _isLoadingAssessment = true;
      _assessmentErrorMessage = null;
    });

    try {
      final assessment = await context
          .read<AssessmentRepository>()
          .getStudentAssessment(widget.assessmentId);
      if (!mounted) return;
      setState(() => _assessment = assessment);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _assessmentErrorMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () =>
            _assessmentErrorMessage = 'Something went wrong. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isLoadingAssessment = false);
    }
  }

  Future<void> _handleSubmit(StudentQuizProvider provider) async {
    final total = provider.quiz?.questions.length ?? 0;
    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Submit Assessment',
      message:
          'You have answered all $total question${total == 1 ? '' : 's'}. '
          'Once submitted, you cannot change your answers or retake this '
          'assessment.',
      confirmLabel: 'Submit',
      type: AppConfirmationType.warning,
    );
    if (!confirmed || !mounted) return;

    final success = await provider.submit();
    if (!mounted) return;

    if (success) {
      unawaited(_loadAssessment());
    } else if (provider.actionErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
    }
  }

  /// Confirms leaving mid-quiz — only ever reachable when there's real
  /// unsaved progress to lose (see [build]'s `hasUnsavedProgress`), since
  /// answers are never persisted server-side until the final [submit] (see
  /// `StudentQuizProvider.submit`'s own doc comment). An attempt that has
  /// started but has zero answers selected yet has nothing to lose, so
  /// leaving is never intercepted for that case — there would be nothing
  /// truthful to warn about.
  Future<void> _confirmLeave() async {
    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Leave assessment?',
      message:
          "Your answers haven't been submitted yet and will be lost if you "
          'leave now.',
      confirmLabel: 'Leave',
      cancelLabel: 'Stay',
      type: AppConfirmationType.warning,
    );
    if (confirmed && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentQuizProvider>();
    final isThisOne = provider.loadedAssessmentId == widget.assessmentId;
    final quiz = isThisOne ? provider.quiz : null;
    final attempt = provider.attempt;
    final tier = _tierFor(MediaQuery.sizeOf(context).width);
    final opportunityTitle = _assessment?.application?.opportunity?.title;

    // Only real when there's something to actually lose -- an attempt has
    // started, isn't submitted yet, and has at least one selected answer.
    final hasUnsavedProgress =
        attempt != null && !attempt.isSubmitted && provider.selectedAnswers.isNotEmpty;

    return PopScope<Object?>(
      canPop: !hasUnsavedProgress,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_confirmLeave());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(quiz?.title ?? 'Assessment', overflow: TextOverflow.ellipsis),
              if (opportunityTitle != null && opportunityTitle.trim().isNotEmpty)
                Text(
                  opportunityTitle,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
          actions: const [ThemeToggleButton()],
        ),
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: AppMotion.reduced(context, AppMotion.slow),
            switchInCurve: AppMotion.entrance,
            switchOutCurve: AppMotion.standard,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.03),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: KeyedSubtree(
              key: ValueKey(_bodyStateKey(provider, quiz, isThisOne, attempt)),
              child: _buildBody(provider, quiz, isThisOne, tier),
            ),
          ),
        ),
      ),
    );
  }

  String _bodyStateKey(
    StudentQuizProvider provider,
    QuizModel? quiz,
    bool isThisOne,
    QuizAttemptModel? attempt,
  ) {
    if (provider.isLoading && !(isThisOne && quiz != null)) return 'loading';
    if (isThisOne && provider.errorMessage != null && quiz == null) {
      return 'error';
    }
    if (!isThisOne || quiz == null) return 'empty';
    // Phase 10A.4B addendum: both only ever apply before an attempt exists
    // — a student who already started keeps their in-progress/submitted
    // view regardless of the clock (see [StudentQuizProvider.isUpcoming]/
    // [isDeadlinePassed]'s own doc comments).
    if (attempt == null && provider.isUpcoming) return 'upcoming';
    if (attempt == null && provider.isDeadlinePassed) return 'deadline_passed';
    if (attempt == null) return 'intro';
    if (attempt.isSubmitted) return 'result';
    return 'taking';
  }

  Widget _buildBody(
    StudentQuizProvider provider,
    QuizModel? quiz,
    bool isThisOne,
    _ScreenTier tier,
  ) {
    if (provider.isLoading && !(isThisOne && quiz != null)) {
      return const AppLoading();
    }

    if (isThisOne && provider.errorMessage != null && quiz == null) {
      return AppErrorView(
        message: provider.errorMessage!,
        onRetry: () =>
            provider.loadQuiz(widget.assessmentId, forceRefresh: true),
      );
    }

    if (!isThisOne || quiz == null) {
      return const AppEmptyView(
        icon: Icons.quiz_outlined,
        title: 'No Quiz Found',
        message: 'This assessment has no quiz to display.',
      );
    }

    final attempt = provider.attempt;

    // Phase 10A.4B addendum — both states are checked before [attempt] is
    // even considered: an attempt can only exist once [start] succeeded,
    // which the backend itself only allows inside the real window, so a
    // `null` attempt here always means "never started", and these two
    // states are mutually exclusive with each other and with "already
    // started". Neither ever shows a question or a Start action — the
    // backend independently enforces the same restriction if reached
    // directly (a disabled Flutter button alone is not the real gate).
    if (attempt == null && provider.isUpcoming) {
      return _QuizUpcomingView(quiz: quiz, tier: tier);
    }
    if (attempt == null && provider.isDeadlinePassed) {
      return _QuizDeadlinePassedView(quiz: quiz, tier: tier);
    }

    if (attempt == null) {
      return _QuizIntroView(quiz: quiz, provider: provider, tier: tier);
    }

    if (attempt.isSubmitted) {
      return _QuizResultView(
        quiz: quiz,
        attempt: attempt,
        tier: tier,
        assessment: _assessment,
        isLoadingResult: _isLoadingAssessment,
        resultErrorMessage: _assessmentErrorMessage,
        onRetryResult: _loadAssessment,
      );
    }

    return _QuizTakingView(
      quiz: quiz,
      provider: provider,
      tier: tier,
      onSubmit: () => _handleSubmit(provider),
    );
  }
}

/// Phase 10A.4B addendum — shown when [StudentQuizProvider.isUpcoming] is
/// true: the candidate has been assigned to this quiz but their own window
/// hasn't opened yet. Never shows a question, a Start action, or even the
/// quiz's title/instructions/passing-score detail — the backend itself
/// hides `questions` from the underlying response in this state (see
/// `Student\QuizController::show()`), and nothing here promises anything
/// the Organization hasn't actually configured. Just the real, truthful
/// schedule.
class _QuizUpcomingView extends StatelessWidget {
  const _QuizUpcomingView({required this.quiz, required this.tier});

  final QuizModel quiz;
  final _ScreenTier tier;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final availableAt = quiz.availableAt;
    final dueAt = quiz.dueAt;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: tier == _ScreenTier.desktop ? 640 : double.infinity,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primaryContainer,
                    ),
                    child: Icon(
                      Icons.hourglass_top_outlined,
                      color: AppColors.primaryDark,
                      size: 34,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Assessment Upcoming',
                  textAlign: TextAlign.center,
                  style: textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'You have been selected to complete "${quiz.title}". It '
                  'is not available yet.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                if (availableAt != null)
                  OpportunityDetailRow(
                    label: 'Available From',
                    value: formatDateTime(availableAt),
                  ),
                if (dueAt != null)
                  OpportunityDetailRow(
                    label: 'Submission Deadline',
                    value: formatDateTime(dueAt),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Phase 10A.4B addendum — shown when
/// [StudentQuizProvider.isDeadlinePassed] is true: the candidate's
/// submission deadline passed without ever starting the quiz. Deliberately
/// makes no claim about the Application's outcome — "Do not invent: Quiz
/// result = failed... Organization retains recruitment authority" (the
/// addendum spec's own wording) — this is purely a truthful timing state,
/// never a decision.
class _QuizDeadlinePassedView extends StatelessWidget {
  const _QuizDeadlinePassedView({required this.quiz, required this.tier});

  final QuizModel quiz;
  final _ScreenTier tier;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final dueAt = quiz.dueAt;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: tier == _ScreenTier.desktop ? 640 : double.infinity,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surfaceVariant,
                    ),
                    child: Icon(
                      Icons.event_busy_outlined,
                      color: AppColors.textSecondary,
                      size: 34,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Assessment Deadline Passed',
                  textAlign: TextAlign.center,
                  style: textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'The submission window for "${quiz.title}" has closed.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'The organization will review your application and '
                  'notify you of next steps.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (dueAt != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  OpportunityDetailRow(
                    label: 'Deadline Was',
                    value: formatDateTime(dueAt),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown before the student's attempt has started (or been resumed) —
/// quiz metadata, a brief one-attempt/timer/no-restart explanation, and the
/// single Start Quiz action. [StudentQuizProvider.start] is what actually
/// determines fresh-start vs. resume; this view has no idea which one will
/// happen and doesn't need to.
class _QuizIntroView extends StatelessWidget {
  const _QuizIntroView({
    required this.quiz,
    required this.provider,
    required this.tier,
  });

  final QuizModel quiz;
  final StudentQuizProvider provider;
  final _ScreenTier tier;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final timeLimit = quiz.timeLimitMinutes;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: tier == _ScreenTier.desktop ? 640 : double.infinity,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primaryContainer,
                          ),
                          child: Icon(
                            Icons.quiz_outlined,
                            color: AppColors.primaryDark,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(quiz.title, style: textTheme.headlineSmall),
                        ),
                      ],
                    ),
                    if (quiz.instructions != null &&
                        quiz.instructions!.trim().isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(quiz.instructions!, style: textTheme.bodyMedium),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    OpportunityDetailRow(
                      label: 'Questions',
                      value: '${quiz.questions.length}',
                    ),
                    OpportunityDetailRow(
                      label: 'Passing Score',
                      value: '${quiz.passingScore}%',
                    ),
                    OpportunityDetailRow(
                      label: 'Time Limit',
                      value: timeLimit != null
                          ? '$timeLimit minutes'
                          : 'No time limit',
                    ),
                    if (quiz.dueAt != null)
                      OpportunityDetailRow(
                        label: 'Submission Deadline',
                        value: formatDateTime(quiz.dueAt!),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: AppRadius.mediumRadius,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'You have one attempt at this quiz.'
                        '${timeLimit != null ? ' Once you start, you will have $timeLimit minutes to finish.' : ''}'
                        ' You cannot retake it after submitting.',
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (provider.startAlreadySubmitted) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'You have already completed this quiz.',
                        style: textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                if (provider.actionErrorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppErrorView(
                    compact: true,
                    title: 'Something Went Wrong',
                    message: provider.actionErrorMessage!,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                PrimaryButton(
                  label: 'Start Quiz',
                  isLoading: provider.isStarting,
                  onPressed: provider.isStarting ? null : provider.start,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The question-answering view. Renders according to
/// [QuizModel.displayMode] (Phase 10A.2) — `single` (one question per
/// page), `paginated` ([QuizModel.questionsPerPage] questions per page), or
/// `all` (every question on one scrollable page, the pre-Phase-10A.2
/// behavior). A top bar always shows truthful *overall* progress (never
/// just the current page's) and, when [QuizModel.timeLimitMinutes] is set,
/// a countdown. On a desktop-width viewport, a compact question navigator
/// sits alongside the questions, tracking which question is currently in
/// view/on-page and letting the student jump to any question — jumping to
/// a question on a different page switches pages first.
///
/// Never renders any correct-answer indication or per-question score — see
/// [_QuestionAnswerCard], which never reads [QuestionModel.correctAnswer]
/// at all.
class _QuizTakingView extends StatefulWidget {
  const _QuizTakingView({
    required this.quiz,
    required this.provider,
    required this.tier,
    required this.onSubmit,
  });

  final QuizModel quiz;
  final StudentQuizProvider provider;
  final _ScreenTier tier;
  final VoidCallback onSubmit;

  @override
  State<_QuizTakingView> createState() => _QuizTakingViewState();
}

class _QuizTakingViewState extends State<_QuizTakingView> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _questionKeys = {};
  int? _currentQuestionId;
  int _currentPageIndex = 0;

  List<QuestionModel> get _questions => _sortedQuestions(widget.quiz.questions);

  /// How many questions render per page. `all`/unrecognized modes put
  /// every question on the one page (matching the pre-Phase-10A.2
  /// behavior); `single` is always exactly one; `paginated` uses the
  /// Organization's configured [QuizModel.questionsPerPage] (falling back
  /// to "all" defensively if that's somehow unset).
  int get _pageSize {
    final total = _questions.length;
    if (total == 0) return 1;
    return switch (widget.quiz.displayMode) {
      'single' => 1,
      'paginated' => widget.quiz.questionsPerPage != null && widget.quiz.questionsPerPage! > 0
          ? widget.quiz.questionsPerPage!
          : total,
      _ => total,
    };
  }

  bool get _isPaged => widget.quiz.displayMode != 'all' && _pageSize < _questions.length;

  int get _pageCount => (_questions.length / _pageSize).ceil().clamp(1, 1 << 30);

  List<QuestionModel> get _currentPageQuestions {
    final start = _currentPageIndex * _pageSize;
    final end = (start + _pageSize).clamp(0, _questions.length);
    if (start >= _questions.length) return const [];
    return _questions.sublist(start, end);
  }

  @override
  void initState() {
    super.initState();
    for (final question in widget.quiz.questions) {
      _questionKeys[question.id] = GlobalKey();
    }
    _scrollController.addListener(_updateCurrentQuestion);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateCurrentQuestion());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateCurrentQuestion);
    _scrollController.dispose();
    super.dispose();
  }

  /// A lightweight "scrollspy" — the current question is whichever
  /// currently-rendered question card's top edge is the last one to have
  /// scrolled past a fixed point near the top of the viewport. Purely a
  /// local UX signal for the navigator panel; never sent anywhere, never
  /// affects answer state. Questions outside the current page have no
  /// attached render object and are skipped, so this naturally narrows to
  /// "current page" in paginated/single modes.
  void _updateCurrentQuestion() {
    int? current;
    for (final question in _currentPageQuestions) {
      final renderObject = _questionKeys[question.id]?.currentContext?.findRenderObject();
      final box = renderObject is RenderBox ? renderObject : null;
      if (box == null || !box.attached) continue;
      if (box.localToGlobal(Offset.zero).dy <= 220) {
        current = question.id;
      } else {
        break;
      }
    }
    current ??= _currentPageQuestions.isNotEmpty ? _currentPageQuestions.first.id : null;
    if (current != _currentQuestionId && mounted) {
      setState(() => _currentQuestionId = current);
    }
  }

  void _scrollToQuestion(int questionId) {
    final questionContext = _questionKeys[questionId]?.currentContext;
    if (questionContext == null) return;
    Scrollable.ensureVisible(
      questionContext,
      duration: AppMotion.reduced(context, AppMotion.normal),
      curve: AppMotion.standard,
      alignment: 0.05,
    );
  }

  /// Navigator-chip tap handler — switches pages first (if the target
  /// question lives on a different page than the current one), then
  /// scrolls to it once the new page has rendered.
  void _goToQuestion(int questionId) {
    final index = _questions.indexWhere((q) => q.id == questionId);
    if (index == -1) return;

    final targetPage = index ~/ _pageSize;
    if (targetPage != _currentPageIndex) {
      setState(() {
        _currentPageIndex = targetPage;
        _currentQuestionId = questionId;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToQuestion(questionId));
      return;
    }

    _scrollToQuestion(questionId);
  }

  void _goToPage(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= _pageCount) return;
    setState(() {
      _currentPageIndex = pageIndex;
      _currentQuestionId = _currentPageQuestions.isNotEmpty
          ? _currentPageQuestions.first.id
          : null;
    });
    _scrollController.jumpTo(0);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateCurrentQuestion());
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    final quiz = widget.quiz;
    final textTheme = Theme.of(context).textTheme;
    final answeredCount = provider.selectedAnswers.length;
    final totalCount = quiz.questions.length;
    final canSubmit =
        provider.allQuestionsAnswered &&
        !provider.isExpired &&
        !provider.isSubmitting;
    final isPaged = _isPaged;
    final isLastPage = _currentPageIndex >= _pageCount - 1;
    final pageQuestions = _currentPageQuestions;

    final questionList = SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final question in pageQuestions)
            Padding(
              key: _questionKeys[question.id],
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _QuestionAnswerCard(
                question: question,
                displayNumber: _questions.indexOf(question) + 1,
                selectedAnswer: provider.selectedAnswers[question.id],
                onSelect: (answer) => provider.selectAnswer(
                  questionId: question.id,
                  answer: answer,
                ),
              ),
            ),
        ],
      ),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            AppSpacing.sm,
            AppSpacing.screenHorizontal,
            0,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$answeredCount of $totalCount answered',
                      style: textTheme.bodyMedium,
                    ),
                    if (isPaged) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        _pageSize == 1
                            ? 'Question ${_currentPageIndex + 1} of $totalCount'
                            : 'Questions ${_currentPageIndex * _pageSize + 1}–'
                                  '${(_currentPageIndex * _pageSize + pageQuestions.length)} of $totalCount',
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xxs),
                    _AnimatedProgressBar(
                      value: totalCount == 0 ? 0 : answeredCount / totalCount,
                    ),
                  ],
                ),
              ),
              // Phase 10A.4B addendum: shown whenever either real
              // constraint applies — the personal time limit, or the
              // candidate's own submission deadline — since
              // `provider.remainingTime` already reflects whichever of the
              // two is the truthful, earlier cutoff (see
              // `StudentQuizProvider._effectiveDeadline`). Neither this
              // countdown nor its expiry flag is itself authoritative — the
              // backend independently re-checks on submit.
              if (quiz.timeLimitMinutes != null || quiz.dueAt != null) ...[
                const SizedBox(width: AppSpacing.sm),
                StatusChip(
                  icon: Icons.timer_outlined,
                  label: provider.isExpired
                      ? (provider.isDeadlineBindingOnExpiry
                            ? 'Deadline passed'
                            : 'Time expired')
                      : _formatDuration(provider.remainingTime),
                  type: provider.isExpired
                      ? AppStatusType.error
                      : AppStatusType.info,
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: IgnorePointer(
            ignoring: provider.isSubmitting,
            child: widget.tier == _ScreenTier.desktop
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: questionList,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 280,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            top: AppSpacing.screenHorizontal,
                            right: AppSpacing.screenHorizontal,
                          ),
                          child: _QuestionNavigatorPanel(
                            questions: _questions,
                            provider: provider,
                            currentQuestionId: _currentQuestionId,
                            onQuestionTap: _goToQuestion,
                          ),
                        ),
                      ),
                    ],
                  )
                : questionList,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (provider.isExpired)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    provider.isDeadlineBindingOnExpiry
                        ? 'The submission deadline has passed. You can no '
                              'longer submit this quiz.'
                        : 'Time expired. You can no longer submit this quiz.',
                    textAlign: TextAlign.center,
                  ),
                ),
              if (provider.actionErrorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    provider.actionErrorMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.error),
                  ),
                ),
              if (isPaged)
                Row(
                  children: [
                    if (_currentPageIndex > 0)
                      Expanded(
                        child: SecondaryButton(
                          label: 'Previous',
                          onPressed: () => _goToPage(_currentPageIndex - 1),
                        ),
                      ),
                    if (_currentPageIndex > 0) const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      flex: isLastPage ? 1 : 2,
                      child: isLastPage
                          ? PrimaryButton(
                              label: 'Submit Quiz',
                              isLoading: provider.isSubmitting,
                              onPressed: canSubmit ? widget.onSubmit : null,
                            )
                          : PrimaryButton(
                              label: 'Next',
                              onPressed: () => _goToPage(_currentPageIndex + 1),
                            ),
                    ),
                  ],
                )
              else
                PrimaryButton(
                  label: 'Submit Quiz',
                  isLoading: provider.isSubmitting,
                  onPressed: canSubmit ? widget.onSubmit : null,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A truthful, animated fill from the previous ratio to [value] (0..1) --
/// never an indeterminate/fake-progress animation.
class _AnimatedProgressBar extends StatelessWidget {
  const _AnimatedProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.reduced(context, AppMotion.normal);
    return ClipRRect(
      borderRadius: AppRadius.pillRadius,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: value.clamp(0, 1)),
        duration: duration,
        curve: AppMotion.standard,
        builder: (context, animatedValue, _) => LinearProgressIndicator(
          value: animatedValue,
          minHeight: 6,
          backgroundColor: AppColors.surfaceVariant,
          valueColor: AlwaysStoppedAnimation(AppColors.primary),
        ),
      ),
    );
  }
}

/// The desktop-only compact progress/navigation panel — a real progress
/// bar plus one numbered chip per question (human 1-based numbering, by
/// display order — never the raw, possibly-zero-based-and-duplicated
/// backend `position` value), distinguishing answered/unanswered (a check
/// icon, not color alone) and the currently in-view/on-page question (a
/// thicker border, not color alone). Tapping a chip navigates to it (and,
/// in paginated/single display mode, switches pages first); it never
/// submits or marks anything -- purely navigation.
class _QuestionNavigatorPanel extends StatelessWidget {
  const _QuestionNavigatorPanel({
    required this.questions,
    required this.provider,
    required this.currentQuestionId,
    required this.onQuestionTap,
  });

  final List<QuestionModel> questions;
  final StudentQuizProvider provider;
  final int? currentQuestionId;
  final ValueChanged<int> onQuestionTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final total = questions.length;
    final answered = provider.selectedAnswers.length;

    return SingleChildScrollView(
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Progress', style: textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            _AnimatedProgressBar(value: total == 0 ? 0 : answered / total),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '$answered of $total answered',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Questions', style: textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (var i = 0; i < questions.length; i++)
                  _QuestionNavigatorChip(
                    displayNumber: i + 1,
                    isAnswered: provider.hasAnswer(questions[i].id),
                    isCurrent: questions[i].id == currentQuestionId,
                    onTap: () => onQuestionTap(questions[i].id),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionNavigatorChip extends StatelessWidget {
  const _QuestionNavigatorChip({
    required this.displayNumber,
    required this.isAnswered,
    required this.isCurrent,
    required this.onTap,
  });

  final int displayNumber;
  final bool isAnswered;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.reduced(context, AppMotion.fast);
    final label =
        'Question $displayNumber, ${isAnswered ? 'answered' : 'not answered'}'
        '${isCurrent ? ', currently visible' : ''}';

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: AppColors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: duration,
            curve: AppMotion.standard,
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isAnswered
                  ? AppColors.primaryContainer
                  : AppColors.surfaceVariant,
              border: Border.all(
                color: isCurrent ? AppColors.primary : AppColors.border,
                width: isCurrent ? 2 : 1,
              ),
            ),
            child: isAnswered
                ? Icon(Icons.check, size: 16, color: AppColors.primaryDark)
                : Text(
                    '$displayNumber',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// A single question's prompt/points plus its answer choices — a
/// [RadioListTile] per option for `multiple_choice`, or a fixed True/False
/// pair for `true_false`. Deliberately never reads
/// [QuestionModel.correctAnswer] (always `null` on this Student-facing
/// response anyway — see that field's own doc comment) and never shows any
/// per-question correctness before submission. The answered state is shown
/// with a check icon (not color alone), so it reads correctly without
/// color vision. [displayNumber] is the question's 1-based position in the
/// real display order (see [_sortedQuestions]) — never the raw, possibly
/// zero-based-and-duplicated backend `position` value.
class _QuestionAnswerCard extends StatelessWidget {
  const _QuestionAnswerCard({
    required this.question,
    required this.displayNumber,
    required this.selectedAnswer,
    required this.onSelect,
  });

  final QuestionModel question;
  final int displayNumber;
  final String? selectedAnswer;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final options = question.type == 'true_false'
        ? const ['True', 'False']
        : question.options ?? const [];
    final duration = AppMotion.reduced(context, AppMotion.fast);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusChip(label: '#$displayNumber', compact: true),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(question.prompt, style: textTheme.titleSmall),
              ),
              const SizedBox(width: AppSpacing.xs),
              AnimatedSwitcher(
                duration: duration,
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: selectedAnswer != null
                    ? Icon(
                        Icons.check_circle,
                        key: const ValueKey('answered'),
                        size: 18,
                        color: AppColors.success,
                        semanticLabel: 'Answered',
                      )
                    : const SizedBox.shrink(key: ValueKey('unanswered')),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '${question.points} pt${question.points == 1 ? '' : 's'}',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          RadioGroup<String>(
            groupValue: selectedAnswer,
            onChanged: (value) {
              if (value == null) return;
              onSelect(value);
            },
            child: Column(
              children: [
                for (final option in options)
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    value: option,
                    title: Text(option),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The post-submission view — three distinct states, distinguished by two
/// independent signals (Phase 10A.2):
///
/// 1. **Released** (`assessment.result` non-null): the real
///    score/passing-score/result, with result-specific, respectful copy
///    ([_ReleasedResultCard]) — never "You failed!" or similar aggressive
///    language, and never claims a recruitment decision
///    (Interview/Offer/rejection) the Organization hasn't actually made.
/// 2. **Released at submit, but the follow-up decision fetch hasn't
///    resolved yet** (`result` still null, but `attempt.score` is
///    non-null — the backend only ever hides `score` on the submit
///    response when it's genuinely not releasing yet, so a non-null score
///    here means release already happened and this is purely a transient
///    re-fetch of the parent Assessment): shows what's already known
///    (score, passing score) plus a loading/retry state for the result
///    itself ([_AwaitingDecisionCard]) — this is NOT the hidden-result
///    case, so it would be dishonest to hide the score the Student
///    already legitimately has.
/// 3. **Genuinely hidden, pending release** (`result` null AND
///    `attempt.score` null — the backend hid `score` on the submit
///    response itself because `Quiz.resultReleaseMode` isn't `immediate`
///    and the configured moment hasn't arrived): a restrained "submitted"
///    state with no score hint at all ([_SubmittedPendingCard]).
class _QuizResultView extends StatelessWidget {
  const _QuizResultView({
    required this.quiz,
    required this.attempt,
    required this.tier,
    required this.assessment,
    required this.isLoadingResult,
    required this.resultErrorMessage,
    required this.onRetryResult,
  });

  final QuizModel quiz;
  final QuizAttemptModel attempt;
  final _ScreenTier tier;
  final AssessmentModel? assessment;
  final bool isLoadingResult;
  final String? resultErrorMessage;
  final VoidCallback onRetryResult;

  @override
  Widget build(BuildContext context) {
    final result = assessment?.result;

    final Widget content;
    if (result != null) {
      content = _ReleasedResultCard(quiz: quiz, attempt: attempt, result: result);
    } else if (attempt.score != null) {
      content = _AwaitingDecisionCard(
        quiz: quiz,
        attempt: attempt,
        isLoadingResult: isLoadingResult,
        resultErrorMessage: resultErrorMessage,
        onRetryResult: onRetryResult,
      );
    } else {
      content = _SubmittedPendingCard(
        isLoadingResult: isLoadingResult,
        resultErrorMessage: resultErrorMessage,
        onRetryResult: onRetryResult,
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: tier == _ScreenTier.desktop ? 640 : double.infinity,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
          child: content,
        ),
      ),
    );
  }
}

/// Score/passing-score are already known (the result was released at
/// submit time — see [_QuizResultView]'s own doc comment for exactly why
/// a non-null [QuizAttemptModel.score] means this), but the follow-up
/// fetch of the parent Assessment (needed for the actual pass/fail
/// [AssessmentModel.result]) hasn't resolved yet, or failed. Shows a
/// loading/retry state for just that missing piece rather than hiding
/// what's already legitimately known.
class _AwaitingDecisionCard extends StatelessWidget {
  const _AwaitingDecisionCard({
    required this.quiz,
    required this.attempt,
    required this.isLoadingResult,
    required this.resultErrorMessage,
    required this.onRetryResult,
  });

  final QuizModel quiz;
  final QuizAttemptModel attempt;
  final bool isLoadingResult;
  final String? resultErrorMessage;
  final VoidCallback onRetryResult;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final duration = AppMotion.reduced(context, AppMotion.slow);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: duration,
                curve: AppMotion.entrance,
                builder: (context, t, child) => Opacity(
                  opacity: t,
                  child: Transform.scale(scale: 0.85 + (0.15 * t), child: child),
                ),
                child: Icon(
                  Icons.check_circle_outline,
                  color: AppColors.success,
                  size: 28,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text('Quiz Completed', style: textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          OpportunityDetailRow(label: 'Score', value: '${attempt.score}%'),
          OpportunityDetailRow(
            label: 'Passing Score',
            value: '${quiz.passingScore}%',
          ),
          if (isLoadingResult)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.xs),
              child: AppLoading(compact: true, message: 'Loading result...'),
            )
          else if (resultErrorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: AppErrorView(
                compact: true,
                message: resultErrorMessage!,
                onRetry: onRetryResult,
              ),
            ),
        ],
      ),
    );
  }
}

/// "Assessment Submitted" — the default, restrained post-submit state
/// while the result is genuinely hidden from the Student. No score hint,
/// no fake progress/timing promise.
class _SubmittedPendingCard extends StatelessWidget {
  const _SubmittedPendingCard({
    required this.isLoadingResult,
    required this.resultErrorMessage,
    required this.onRetryResult,
  });

  final bool isLoadingResult;
  final String? resultErrorMessage;
  final VoidCallback onRetryResult;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final duration = AppMotion.reduced(context, AppMotion.slow);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: duration,
              curve: AppMotion.entrance,
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.scale(scale: 0.85 + (0.15 * t), child: child),
              ),
              child: Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryContainer,
                ),
                child: Icon(
                  Icons.check_circle_outline,
                  color: AppColors.primaryDark,
                  size: 34,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Assessment Submitted',
            textAlign: TextAlign.center,
            style: textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Thank you for completing the assessment.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Your responses were submitted successfully. The organization '
            'will review the assessment process and you will be notified '
            'when your result is available.',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          if (isLoadingResult) ...[
            const SizedBox(height: AppSpacing.md),
            const AppLoading(compact: true, message: 'Checking status...'),
          ] else if (resultErrorMessage != null) ...[
            const SizedBox(height: AppSpacing.md),
            AppErrorView(
              compact: true,
              message: resultErrorMessage!,
              onRetry: onRetryResult,
            ),
          ],
        ],
      ),
    );
  }
}

/// The released-result state — real score/passing-score/result, plus
/// respectful, truthful next-step copy that never claims a recruitment
/// decision (Interview/Offer/rejection) the Organization hasn't actually
/// made yet, matching `docs/BUSINESS_RULES.md`'s own "result and decision
/// stay separate" rule.
class _ReleasedResultCard extends StatelessWidget {
  const _ReleasedResultCard({
    required this.quiz,
    required this.attempt,
    required this.result,
  });

  final QuizModel quiz;
  final QuizAttemptModel attempt;
  final String result;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final duration = AppMotion.reduced(context, AppMotion.slow);
    final passed = result == 'passed';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: duration,
                    curve: AppMotion.entrance,
                    builder: (context, t, child) => Opacity(
                      opacity: t,
                      child: Transform.scale(scale: 0.85 + (0.15 * t), child: child),
                    ),
                    child: Icon(
                      passed ? Icons.check_circle_outline : Icons.info_outline,
                      color: passed ? AppColors.success : AppColors.textSecondary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text('Assessment Result', style: textTheme.titleLarge),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (attempt.score != null)
                OpportunityDetailRow(label: 'Score', value: '${attempt.score}%'),
              OpportunityDetailRow(
                label: 'Passing Score',
                value: '${quiz.passingScore}%',
              ),
              OpportunityDetailRow(
                label: 'Result',
                value: assessmentResultLabels[result] ?? result,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          passed
              ? 'Congratulations — you have successfully completed the '
                    'assessment. The organization will contact you regarding '
                    'the next step in the recruitment process.'
              : 'Thank you for the time and effort you put into the '
                    'assessment. The organization will review your results as '
                    'part of your overall application, and you will be '
                    'notified of next steps.',
          style: textTheme.bodyMedium,
        ),
      ],
    );
  }
}

String _formatDuration(Duration? duration) {
  final value = duration ?? Duration.zero;
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
