import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/assessment_model.dart';
import '../../../models/question_model.dart';
import '../../../models/quiz_attempt_model.dart';
import '../../../models/quiz_model.dart';
import '../../../providers/student_quiz_provider.dart';
import '../../opportunities/presentation/opportunity_display.dart';
import '../data/assessment_repository.dart';
import 'assessment_display.dart';

/// Student Quiz taking — reached by Assessment ID alone (a route parameter,
/// never GoRouter `extra`), matching [AppRoutes.studentQuiz] and the same
/// convention `OrganizationQuizEditorScreen` already uses for its own
/// Assessment-ID-addressed route.
///
/// Deliberately self-contained about the Assessment's own `result`: Quiz v1
/// has no attempt-lookup endpoint, so the only way this screen can ever
/// learn the graded [AssessmentModel.result] is by fetching the Assessment
/// directly (via [AssessmentRepository.getStudentAssessment], addressed by
/// this same Assessment ID) right after a successful submit — never by
/// reading `StudentAssessmentProvider`, which is read-only and keyed by
/// Application ID, not Assessment ID. `StudentApplicationDetailsScreen` is
/// still responsible for force-refreshing that provider itself once this
/// screen is popped, so its own summary reflects the newly `completed`
/// assessment.
class StudentQuizScreen extends StatefulWidget {
  const StudentQuizScreen({super.key, required this.assessmentId});

  final int assessmentId;

  @override
  State<StudentQuizScreen> createState() => _StudentQuizScreenState();
}

class _StudentQuizScreenState extends State<StudentQuizScreen> {
  AssessmentModel? _refreshedAssessment;
  bool _isLoadingResult = false;
  String? _resultErrorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StudentQuizProvider>().loadQuiz(widget.assessmentId);
    });
  }

  Future<void> _loadResult() async {
    setState(() {
      _isLoadingResult = true;
      _resultErrorMessage = null;
    });

    try {
      final assessment = await context
          .read<AssessmentRepository>()
          .getStudentAssessment(widget.assessmentId);
      if (!mounted) return;
      setState(() => _refreshedAssessment = assessment);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _resultErrorMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _resultErrorMessage = 'Something went wrong. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isLoadingResult = false);
    }
  }

  Future<void> _handleSubmit(StudentQuizProvider provider) async {
    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Submit Quiz',
      message:
          'Are you sure you want to submit your answers? You cannot retake '
          'this quiz.',
      confirmLabel: 'Submit',
      type: AppConfirmationType.warning,
    );
    if (!confirmed || !mounted) return;

    final success = await provider.submit();
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quiz submitted successfully')),
      );
      unawaited(_loadResult());
    } else if (provider.actionErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentQuizProvider>();
    final isThisOne = provider.loadedAssessmentId == widget.assessmentId;
    final quiz = isThisOne ? provider.quiz : null;

    return Scaffold(
      appBar: AppBar(title: Text(quiz?.title ?? 'Quiz')),
      body: SafeArea(child: _buildBody(provider, quiz, isThisOne)),
    );
  }

  Widget _buildBody(
    StudentQuizProvider provider,
    QuizModel? quiz,
    bool isThisOne,
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

    if (attempt == null) {
      return _QuizIntroView(quiz: quiz, provider: provider);
    }

    if (attempt.isSubmitted) {
      return _QuizResultView(
        quiz: quiz,
        attempt: attempt,
        refreshedAssessment: _refreshedAssessment,
        isLoadingResult: _isLoadingResult,
        resultErrorMessage: _resultErrorMessage,
        onRetryResult: _loadResult,
      );
    }

    return _QuizTakingView(
      quiz: quiz,
      provider: provider,
      onSubmit: () => _handleSubmit(provider),
    );
  }
}

/// Shown before the student's attempt has started (or been resumed) —
/// quiz metadata, a brief one-attempt/timer/no-restart explanation, and the
/// single Start Quiz action. [StudentQuizProvider.start] is what actually
/// determines fresh-start vs. resume; this view has no idea which one will
/// happen and doesn't need to.
class _QuizIntroView extends StatelessWidget {
  const _QuizIntroView({required this.quiz, required this.provider});

  final QuizModel quiz;
  final StudentQuizProvider provider;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final timeLimit = quiz.timeLimitMinutes;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(quiz.title, style: textTheme.headlineSmall),
                if (quiz.instructions != null &&
                    quiz.instructions!.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(quiz.instructions!, style: textTheme.bodyMedium),
                ],
                const SizedBox(height: AppSpacing.sm),
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
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'You have one attempt at this quiz.'
            '${timeLimit != null ? ' Once you start, you will have $timeLimit minutes to finish.' : ''}'
            ' You cannot retake it after submitting.',
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (provider.startAlreadySubmitted) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
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
    );
  }
}

/// The question-answering view — one scrollable page for every question
/// (not "Question X of Y" paging), a top bar with the answered count and
/// (when [QuizModel.timeLimitMinutes] is set) a countdown, and the Submit
/// action. Never renders any correct-answer indication or per-question
/// score — see [_QuestionAnswerCard], which never reads
/// [QuestionModel.correctAnswer] at all.
class _QuizTakingView extends StatelessWidget {
  const _QuizTakingView({
    required this.quiz,
    required this.provider,
    required this.onSubmit,
  });

  final QuizModel quiz;
  final StudentQuizProvider provider;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final sortedQuestions = [...quiz.questions]
      ..sort((a, b) => a.position.compareTo(b.position));
    final answeredCount = provider.selectedAnswers.length;
    final totalCount = quiz.questions.length;
    final canSubmit =
        provider.allQuestionsAnswered &&
        !provider.isExpired &&
        !provider.isSubmitting;

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
            children: [
              Expanded(
                child: Text(
                  '$answeredCount of $totalCount answered',
                  style: textTheme.bodyMedium,
                ),
              ),
              if (quiz.timeLimitMinutes != null)
                StatusChip(
                  icon: Icons.timer_outlined,
                  label: provider.isExpired
                      ? 'Time expired'
                      : _formatDuration(provider.remainingTime),
                  type: provider.isExpired
                      ? AppStatusType.error
                      : AppStatusType.info,
                ),
            ],
          ),
        ),
        Expanded(
          child: IgnorePointer(
            ignoring: provider.isSubmitting,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final question in sortedQuestions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _QuestionAnswerCard(
                        question: question,
                        selectedAnswer: provider.selectedAnswers[question.id],
                        onSelect: (answer) => provider.selectAnswer(
                          questionId: question.id,
                          answer: answer,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (provider.isExpired)
                const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    'Time expired. You can no longer submit this quiz.',
                    textAlign: TextAlign.center,
                  ),
                ),
              if (provider.actionErrorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    provider.actionErrorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
              PrimaryButton(
                label: 'Submit Quiz',
                isLoading: provider.isSubmitting,
                onPressed: canSubmit ? onSubmit : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A single question's prompt/points plus its answer choices — a
/// [RadioListTile] per option for `multiple_choice`, or a fixed True/False
/// pair for `true_false`. Deliberately never reads
/// [QuestionModel.correctAnswer] (always `null` on this Student-facing
/// response anyway — see that field's own doc comment) and never shows any
/// per-question correctness before submission.
class _QuestionAnswerCard extends StatelessWidget {
  const _QuestionAnswerCard({
    required this.question,
    required this.selectedAnswer,
    required this.onSelect,
  });

  final QuestionModel question;
  final String? selectedAnswer;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final options = question.type == 'true_false'
        ? const ['True', 'False']
        : question.options ?? const [];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusChip(label: '#${question.position}', compact: true),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(question.prompt, style: textTheme.titleSmall),
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

/// The post-submission summary — score (from the attempt this exact
/// session just submitted; there is no later way to retrieve it, see
/// `StudentQuizScreen`'s own doc comment), passing score, and the
/// Assessment's own `result` once it's been fetched. Never shows a correct
/// answer or per-question review.
class _QuizResultView extends StatelessWidget {
  const _QuizResultView({
    required this.quiz,
    required this.attempt,
    required this.refreshedAssessment,
    required this.isLoadingResult,
    required this.resultErrorMessage,
    required this.onRetryResult,
  });

  final QuizModel quiz;
  final QuizAttemptModel attempt;
  final AssessmentModel? refreshedAssessment;
  final bool isLoadingResult;
  final String? resultErrorMessage;
  final VoidCallback onRetryResult;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final result = refreshedAssessment?.result;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text('Quiz Completed', style: textTheme.titleLarge),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (attempt.score != null)
                  OpportunityDetailRow(
                    label: 'Score',
                    value: '${attempt.score}%',
                  ),
                OpportunityDetailRow(
                  label: 'Passing Score',
                  value: '${quiz.passingScore}%',
                ),
                if (result != null)
                  OpportunityDetailRow(
                    label: 'Result',
                    value: assessmentResultLabels[result] ?? result,
                  )
                else if (isLoadingResult)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.xs),
                    child: AppLoading(
                      compact: true,
                      message: 'Loading result...',
                    ),
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
          ),
        ],
      ),
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
