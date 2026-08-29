import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/quiz_candidate_result_model.dart';
import '../../../providers/organization_quiz_provider.dart';
import '../../../routes/app_routes.dart';
import 'assessment_display.dart';

/// One filter option for the candidate list below — purely client-side over
/// the already-loaded [QuizCandidateResultModel] rows (Phase 10A.4B,
/// section 17: "make the results screen useful but not overbuilt" — no
/// invented analytics, just the real fields the backend already returns).
enum _ResultFilter { all, passed, failed, decisionRequired, released, pending }

const _nextActionLabels = {
  'interview': 'Interview',
  'offer': 'Offer',
  'reject': 'Reject',
};

/// UI Phase O5: below this width, candidates render as compact stacked
/// cards; at or above it, as a compact structured "table-card" row with
/// clearly labeled columns — a comparison layout desktop has room for.
const _tableBreakpoint = 900.0;

/// UI Phase O5: a centered, intentional desktop width, matching the same
/// "don't stretch a page edge-to-edge" treatment already applied to the
/// Dashboard, Opportunities list, and Opportunity Details.
const _maxContentWidth = 1120.0;

bool _isDecisionRequired(QuizCandidateResultModel row) =>
    row.status == 'completed' && row.nextAction == null;

/// The real next-step label for [row] — the released/staged decision when
/// one exists, otherwise `null` (the caller decides how to phrase "no
/// decision yet" for its own layout, since desktop and mobile want
/// different wording for that state).
String? _nextActionLabel(QuizCandidateResultModel row) =>
    row.nextAction == null
    ? null
    : (_nextActionLabels[row.nextAction] ?? row.nextAction);

/// Phase 10A.4B addendum — a one-line timing summary for [row], combining
/// the derived label with whichever of [availableAt]/[dueAt] is the most
/// relevant real date for that state (opens-at while upcoming, due-at
/// otherwise).
String _timingDescription(QuizCandidateResultModel row) {
  final label = quizTimingStatusLabels[row.timingStatus] ?? row.timingStatus!;

  if (row.timingStatus == 'upcoming' && row.availableAt != null) {
    return '$label — opens ${formatDateTime(row.availableAt!)}';
  }
  if (row.dueAt != null &&
      (row.timingStatus == 'available' ||
          row.timingStatus == 'in_progress' ||
          row.timingStatus == 'deadline_passed')) {
    final verb = row.timingStatus == 'deadline_passed' ? 'was due' : 'due';
    return '$label — $verb ${formatDateTime(row.dueAt!)}';
  }

  return label;
}

/// [row]'s submission state, in plain words — real fields only:
/// [QuizCandidateResultModel.timingStatus] when the backend has computed
/// one (Phase 10A.4B addendum), otherwise a humanized
/// [QuizCandidateResultModel.status] (a completed Assessment is truthfully
/// "Submitted" in a quiz-results context).
String _submissionLabel(QuizCandidateResultModel row) {
  if (row.timingStatus != null) {
    return quizTimingStatusLabels[row.timingStatus] ?? row.timingStatus!;
  }
  if (row.status == 'completed') return 'Submitted';
  return assessmentStatusLabels[row.status] ?? row.status;
}

/// Submission Timestamp Fix — a secondary detail line under
/// [_submissionLabel], or `null` when there's nothing real to add.
///
/// Once submitted, [_timingDescription] has no due/opens date left to show
/// (`timingStatus == 'submitted'` falls through to just repeating its own
/// label) — that repeated "Submitted" under "Submitted" was the actual
/// bug. The real fix is [QuizCandidateResultModel.submittedAt] (this
/// table's own real timestamp): once present, show that instead of calling
/// [_timingDescription] again. Before submission, [_timingDescription]'s
/// opens/due-date line is still genuinely useful and not a duplicate, so it
/// stays. Never invents a timestamp — with neither field available, this
/// returns `null` and the caller renders nothing extra.
String? _submissionDetailLine(QuizCandidateResultModel row) {
  if (row.submittedAt != null) {
    return formatDateTime(row.submittedAt!);
  }
  if (row.timingStatus != null && row.timingStatus != 'submitted') {
    return _timingDescription(row);
  }
  return null;
}

Color _scoreColor(QuizCandidateResultModel row) {
  if (row.result == 'passed') return AppColors.success;
  if (row.result == 'failed') return AppColors.error;
  return AppColors.textPrimary;
}

/// Phase 10A.4B — every candidate's score/result/decision/release state for
/// an Opportunity's shared Quiz, in one place, so the Organization no
/// longer has to open every Application individually to see this (section
/// 16). Read-only: each row's "Review / Decide" hands off to the real,
/// existing per-candidate Application Details screen for the actual
/// decision actions (section 20 — no mass/batch decisions here).
///
/// UI Phase O5: purely a presentation polish over that same real data — a
/// theme toggle, a compact desktop comparison layout, mobile cards with
/// clearly labeled fields, and a more prominent score. No scoring,
/// decision, release, or navigation behavior changed.
class OrganizationQuizResultsScreen extends StatefulWidget {
  const OrganizationQuizResultsScreen({super.key, required this.opportunityId});

  final int opportunityId;

  @override
  State<OrganizationQuizResultsScreen> createState() =>
      _OrganizationQuizResultsScreenState();
}

class _OrganizationQuizResultsScreenState
    extends State<OrganizationQuizResultsScreen> {
  _ResultFilter _filter = _ResultFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OrganizationQuizProvider>().loadResults(
        widget.opportunityId,
      );
    });
  }

  bool _matchesFilter(QuizCandidateResultModel row) {
    switch (_filter) {
      case _ResultFilter.all:
        return true;
      case _ResultFilter.passed:
        return row.result == 'passed';
      case _ResultFilter.failed:
        return row.result == 'failed';
      case _ResultFilter.decisionRequired:
        return _isDecisionRequired(row);
      case _ResultFilter.released:
        return row.resultReleasedAt != null;
      case _ResultFilter.pending:
        return row.status == 'completed' && row.resultReleasedAt == null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Establishes a real Theme dependency for this whole build — the
    // AppBar subtitle and several sub-widgets below read `AppColors.x`
    // directly rather than through `Theme.of(context).textTheme`, so this
    // is what makes the toggle refresh them immediately (see AppCard's own
    // UI Phase O4.1 fix for the full mechanism).
    final textTheme = Theme.of(context).textTheme;

    final provider = context.watch<OrganizationQuizProvider>();
    final isThisOne = provider.loadedResultsOpportunityId == widget.opportunityId;
    final results = isThisOne ? provider.results : null;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Quiz Results'),
            if (results != null)
              Text(
                results.quiz.title,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
        actions: const [ThemeToggleSurface()],
      ),
      body: SafeArea(child: _buildBody(provider, results, isThisOne)),
    );
  }

  Widget _buildBody(
    OrganizationQuizProvider provider,
    QuizResultsModel? results,
    bool isThisOne,
  ) {
    if (provider.isLoadingResults && !(isThisOne && results != null)) {
      return const AppLoading();
    }

    if (isThisOne && provider.resultsErrorMessage != null && results == null) {
      return AppErrorView(
        message: provider.resultsErrorMessage!,
        onRetry: () =>
            provider.loadResults(widget.opportunityId, forceRefresh: true),
      );
    }

    if (!isThisOne || results == null) {
      return const AppEmptyView(
        icon: Icons.leaderboard_outlined,
        title: 'No Results Yet',
        message: 'No candidates have been advanced to this quiz yet.',
      );
    }

    final candidates = results.candidates;

    // Distinct from the filtered-to-nothing case below -- this is a real
    // "nobody has been advanced to this quiz yet" state, shown even though
    // `results` itself loaded successfully (an empty list is not an error).
    if (candidates.isEmpty) {
      return const AppEmptyView(
        icon: Icons.leaderboard_outlined,
        title: 'No Results Yet',
        message: 'No candidates have been advanced to this quiz yet.',
      );
    }

    final filtered = candidates.where(_matchesFilter).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _tableBreakpoint;

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenHorizontal,
                AppSpacing.sm,
                AppSpacing.screenHorizontal,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: _Centered(
                  child: _SummaryRow(candidates: candidates),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenHorizontal,
                vertical: AppSpacing.sm,
              ),
              sliver: SliverToBoxAdapter(
                child: _Centered(child: _buildFilters()),
              ),
            ),
            if (filtered.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: AppEmptyView(
                  icon: Icons.filter_alt_off_outlined,
                  title: 'No Matching Candidates',
                  message: 'No candidates match this filter.',
                ),
              )
            else ...[
              if (isWide)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenHorizontal,
                    0,
                    AppSpacing.screenHorizontal,
                    AppSpacing.xxs,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _Centered(child: const _ResultsHeaderRow()),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenHorizontal,
                  0,
                  AppSpacing.screenHorizontal,
                  AppSpacing.xl,
                ),
                sliver: SliverToBoxAdapter(
                  child: _Centered(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < filtered.length; i++) ...[
                          if (i > 0) const SizedBox(height: AppSpacing.sm),
                          isWide
                              ? _CandidateTableRow(row: filtered[i])
                              : _CandidateCard(row: filtered[i]),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildFilters() {
    final options = {
      _ResultFilter.all: 'All',
      _ResultFilter.passed: 'Passed',
      _ResultFilter.failed: 'Failed',
      _ResultFilter.decisionRequired: 'Decision Required',
      _ResultFilter.released: 'Released',
      _ResultFilter.pending: 'Pending',
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final entry in options.entries) ...[
            ChoiceChip(
              label: Text(entry.value),
              selected: _filter == entry.key,
              selectedColor: AppColors.primaryContainer,
              side: BorderSide(
                color: _filter == entry.key
                    ? AppColors.primary
                    : AppColors.border,
              ),
              labelStyle: TextStyle(
                fontWeight: _filter == entry.key
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: _filter == entry.key
                    ? AppColors.primaryDark
                    : AppColors.textPrimary,
              ),
              onSelected: (_) => setState(() => _filter = entry.key),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

/// Centers [child] within [_maxContentWidth] on wide viewports, and lets it
/// use the full width below that — the same desktop-width treatment used
/// throughout the rest of the Organization UI.
class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxContentWidth),
        child: child,
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.candidates});

  final List<QuizCandidateResultModel> candidates;

  @override
  Widget build(BuildContext context) {
    final completed = candidates.where((c) => c.status == 'completed').length;
    final passed = candidates.where((c) => c.result == 'passed').length;
    final failed = candidates.where((c) => c.result == 'failed').length;
    final decisionRequired = candidates.where(_isDecisionRequired).length;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _MetricTile(
          label: 'Completed',
          value: completed,
          accentColor: AppColors.primary,
        ),
        _MetricTile(
          label: 'Passed',
          value: passed,
          accentColor: AppColors.success,
        ),
        _MetricTile(
          label: 'Failed',
          value: failed,
          accentColor: AppColors.error,
        ),
        _MetricTile(
          label: 'Decision Required',
          value: decisionRequired,
          accentColor: AppColors.warning,
        ),
      ],
    );
  }
}

/// One compact summary metric — its own small bordered tile rather than one
/// large sparse card, so the summary reads as a set of distinct counts
/// (UI Phase O5) instead of a loosely-labeled block of numbers.
class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.accentColor,
  });

  final String label;
  final int value;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      constraints: const BoxConstraints(minWidth: 108),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.mediumRadius,
        border: Border.all(color: AppColors.secondaryLight),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: textTheme.headlineSmall?.copyWith(
              color: accentColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

const _candidateFlex = 3;
const _scoreFlex = 1;
const _resultFlex = 1;
const _nextStepFlex = 1;
const _releaseFlex = 1;
const _submissionFlex = 2;
const _actionWidth = 100.0;

/// Desktop-only column labels above the [_CandidateTableRow] list — this is
/// what lets each row's cells stay bare values (UI Phase O5 section 5: "do
/// not allow them to read as one sentence") rather than needing a repeated
/// "Label: value" prefix the way the mobile card does.
class _ResultsHeaderRow extends StatelessWidget {
  const _ResultsHeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: AppColors.textSecondary,
      fontWeight: FontWeight.w600,
    );

    Widget label(String text, int flex) =>
        Expanded(flex: flex, child: Text(text, style: style));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          label('Candidate', _candidateFlex),
          label('Score', _scoreFlex),
          label('Result', _resultFlex),
          label('Next Step', _nextStepFlex),
          label('Release', _releaseFlex),
          label('Submission', _submissionFlex),
          const SizedBox(width: _actionWidth),
        ],
      ),
    );
  }
}

/// A compact, structured row for desktop/tablet comparison — one candidate
/// per row, columns aligned with [_ResultsHeaderRow] above the list.
class _CandidateTableRow extends StatelessWidget {
  const _CandidateTableRow({required this.row});

  final QuizCandidateResultModel row;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final mutedStyle = textTheme.bodyMedium?.copyWith(
      color: AppColors.textSecondary,
    );
    final nextActionLabel = _nextActionLabel(row);
    final nextStepText = nextActionLabel ??
        (_isDecisionRequired(row) ? 'Decision Required' : 'Awaiting Submission');

    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: _candidateFlex,
            child: Text(
              row.studentName,
              style: textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _scoreFlex,
            child: row.score != null
                ? Text(
                    '${row.score}%',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _scoreColor(row),
                    ),
                  )
                : Text('—', style: mutedStyle),
          ),
          Expanded(
            flex: _resultFlex,
            child: row.result != null
                ? StatusChip(
                    label: row.result == 'passed' ? 'Passed' : 'Failed',
                    type: row.result == 'passed'
                        ? AppStatusType.success
                        : AppStatusType.error,
                    compact: true,
                  )
                : Text('—', style: mutedStyle),
          ),
          Expanded(
            flex: _nextStepFlex,
            child: Text(
              nextStepText,
              style: textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: _releaseFlex,
            child: Text(
              row.resultReleasedAt != null ? 'Released' : 'Pending',
              style: mutedStyle,
            ),
          ),
          Expanded(
            flex: _submissionFlex,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _submissionLabel(row),
                  style: mutedStyle,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_submissionDetailLine(row) case final detail?)
                  Text(
                    detail,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          SizedBox(
            width: _actionWidth,
            child: SecondaryButton(
              label: row.nextAction == null ? 'Decide' : 'Review',
              height: 36,
              onPressed: () => context.push(
                AppRoutes.organizationApplicationDetails(row.applicationId),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact candidate card for narrower viewports — no desktop columns,
/// every field explicitly labeled ("Next Step: Interview") since there's no
/// column header to supply that context (UI Phase O5 section 10).
class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.row});

  final QuizCandidateResultModel row;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final mutedStyle = textTheme.bodySmall?.copyWith(
      color: AppColors.textSecondary,
    );
    final nextActionLabel = _nextActionLabel(row);
    final nextStepText = nextActionLabel != null
        ? 'Next Step: $nextActionLabel'
        : (_isDecisionRequired(row)
              ? 'Decision: Required'
              : 'Next Step: Awaiting Submission');

    return AppCard(
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(row.studentName, style: textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xxs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (row.score != null)
                Text(
                  '${row.score}%',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _scoreColor(row),
                  ),
                )
              else
                Text('Not submitted', style: mutedStyle),
              if (row.result != null)
                StatusChip(
                  label: row.result == 'passed' ? 'Passed' : 'Failed',
                  type: row.result == 'passed'
                      ? AppStatusType.success
                      : AppStatusType.error,
                  compact: true,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(nextStepText, style: textTheme.bodySmall),
          Text(
            'Release: ${row.resultReleasedAt != null ? 'Released' : 'Pending'}',
            style: mutedStyle,
          ),
          Text('Submission: ${_submissionLabel(row)}', style: mutedStyle),
          if (_submissionDetailLine(row) case final detail?) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              detail,
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textMuted,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: SecondaryButton(
              label: row.nextAction == null ? 'Decide' : 'Review',
              height: 36,
              onPressed: () => context.push(
                AppRoutes.organizationApplicationDetails(row.applicationId),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
