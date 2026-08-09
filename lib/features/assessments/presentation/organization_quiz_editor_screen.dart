import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/question_model.dart';
import '../../../models/quiz_model.dart';
import '../../../providers/organization_quiz_provider.dart';
import '../../opportunities/presentation/opportunity_display.dart';
import 'assessment_display.dart';
import 'question_form_sheet.dart';

/// Organization-only Quiz authoring: quiz metadata, the question list, and
/// add/edit/delete/publish actions while the quiz is still a draft. Reached
/// by Assessment ID alone (a route parameter, never GoRouter `extra`),
/// matching every other organization-application route in this app.
///
/// Every mutation action is hidden once `quiz.status == 'published'` — see
/// `OrganizationQuizProvider` for the matching backend-defense-in-depth
/// guard.
class OrganizationQuizEditorScreen extends StatefulWidget {
  const OrganizationQuizEditorScreen({super.key, required this.assessmentId});

  final int assessmentId;

  @override
  State<OrganizationQuizEditorScreen> createState() =>
      _OrganizationQuizEditorScreenState();
}

class _OrganizationQuizEditorScreenState
    extends State<OrganizationQuizEditorScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OrganizationQuizProvider>().loadQuiz(widget.assessmentId);
    });
  }

  Future<void> _addQuestion() async {
    final created = await showQuestionFormSheet(context);
    if (!mounted || !created) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Question added successfully')),
    );
  }

  Future<void> _editQuestion(QuestionModel question) async {
    final updated = await showQuestionFormSheet(context, existing: question);
    if (!mounted || !updated) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Question updated successfully')),
    );
  }

  Future<void> _deleteQuestion(
    OrganizationQuizProvider provider,
    QuestionModel question,
  ) async {
    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Delete Question',
      message: 'Delete this question? This cannot be undone.',
      confirmLabel: 'Delete',
      type: AppConfirmationType.danger,
    );
    if (!confirmed || !mounted) return;

    final success = await provider.deleteQuestion(question.id);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Question deleted successfully')),
      );
    } else if (provider.actionErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
    }
  }

  Future<void> _publish(OrganizationQuizProvider provider) async {
    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Publish Quiz',
      message:
          'Are you sure you want to publish this quiz? You will not be '
          'able to modify its questions afterwards.',
      confirmLabel: 'Publish',
      type: AppConfirmationType.warning,
    );
    if (!confirmed || !mounted) return;

    final success = await provider.publish();
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quiz published successfully')),
      );
    } else if (provider.actionErrorMessage != null) {
      // Covers the documented zero-question 422 -- the quiz stays draft
      // (the provider never touches `quiz` on failure) and the backend's
      // own message is shown as-is.
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationQuizProvider>();
    final isThisOne = provider.loadedAssessmentId == widget.assessmentId;
    final quiz = isThisOne ? provider.quiz : null;

    return Scaffold(
      appBar: AppBar(title: Text(quiz?.title ?? 'Quiz Editor')),
      body: SafeArea(child: _buildBody(provider, quiz, isThisOne)),
      floatingActionButton: quiz != null && quiz.status == 'draft'
          ? FloatingActionButton.extended(
              onPressed: _addQuestion,
              icon: const Icon(Icons.add),
              label: const Text('Add Question'),
            )
          : null,
    );
  }

  Widget _buildBody(
    OrganizationQuizProvider provider,
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

    final isDraft = quiz.status == 'draft';

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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        quiz.title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    StatusChip(
                      label: quizStatusLabels[quiz.status] ?? quiz.status,
                      type: quizStatusChipType(quiz.status),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (quiz.instructions != null &&
                    quiz.instructions!.trim().isNotEmpty) ...[
                  Text(
                    quiz.instructions!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                OpportunityDetailRow(
                  label: 'Time Limit',
                  value: quiz.timeLimitMinutes != null
                      ? '${quiz.timeLimitMinutes} minutes'
                      : 'Not specified',
                ),
                OpportunityDetailRow(
                  label: 'Passing Score',
                  value: '${quiz.passingScore}%',
                ),
                OpportunityDetailRow(
                  label: 'Questions',
                  value: '${quiz.questions.length}',
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (!isDraft)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.md),
              child: AppErrorView(
                compact: true,
                icon: Icons.lock_outline,
                title: 'Published',
                message: 'Published quizzes cannot be modified.',
              ),
            ),
          if (quiz.questions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: AppEmptyView(
                icon: Icons.quiz_outlined,
                title: 'No Questions Yet',
                message: 'Add at least one question before publishing.',
              ),
            )
          else
            for (final question in quiz.questions)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _QuestionCard(
                  question: question,
                  isDraft: isDraft,
                  isBusy: provider.isBusyQuestion(question.id),
                  onEdit: () => _editQuestion(question),
                  onDelete: () => _deleteQuestion(provider, question),
                ),
              ),
          if (isDraft) ...[
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              label: 'Publish Quiz',
              isLoading: provider.isPublishing,
              onPressed: provider.isPublishing
                  ? null
                  : () => _publish(provider),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.isDraft,
    required this.isBusy,
    required this.onEdit,
    required this.onDelete,
  });

  final QuestionModel question;
  final bool isDraft;
  final bool isBusy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final options = question.options;

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
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: [
              StatusChip(
                label: questionTypeLabels[question.type] ?? question.type,
                type: AppStatusType.info,
                compact: true,
              ),
              StatusChip(
                label:
                    '${question.points} pt${question.points == 1 ? '' : 's'}',
                compact: true,
              ),
            ],
          ),
          if (options != null && options.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            for (final option in options)
              Text(
                option == question.correctAnswer ? '• $option ✓' : '• $option',
                style: textTheme.bodySmall,
              ),
          ],
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Correct answer: ${question.correctAnswer}',
            style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (isDraft) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: isBusy ? null : onEdit,
                  child: const Text('Edit'),
                ),
                const SizedBox(width: AppSpacing.xs),
                TextButton(
                  onPressed: isBusy ? null : onDelete,
                  child: const Text('Delete'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
