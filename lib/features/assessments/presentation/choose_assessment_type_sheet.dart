import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../providers/organization_applications_provider.dart';
import '../../../providers/organization_assessment_provider.dart';
import '../../../routes/app_routes.dart';

/// A compact modal bottom sheet for choosing which assessment path an
/// organization wants for a shortlisted application — Interview or, as of
/// Phase 6B-2, Quiz. Call [showChooseAssessmentTypeSheet] rather than
/// constructing this directly.
///
/// For the ad-hoc case (`recruitmentProcess == 'none'`, the pre-10A.4B
/// default), this sheet never makes a backend request itself — Continue
/// only navigates to the dedicated Schedule Interview or Create Quiz screen
/// for the chosen application; the actual Assessment creation happens
/// there, exactly as before this phase.
///
/// **Phase 10A.4B**: when the Opportunity has a declared
/// [recruitmentProcess], the choice narrows to match it instead of always
/// offering both — `interview` shows Interview only, `quiz` shows Quiz
/// only, and for `quiz` Continue *does* make a real request itself
/// (`OrganizationAssessmentProvider.advanceToSharedQuiz()`), since
/// advancing to an already-configured shared Quiz needs no further form to
/// fill in first.
class ChooseAssessmentTypeSheet extends StatefulWidget {
  const ChooseAssessmentTypeSheet({
    super.key,
    required this.applicationId,
    this.recruitmentProcess = 'none',
  });

  final int applicationId;

  /// One of: none, interview, quiz (Phase 10A.4B) — the owning
  /// Opportunity's declared process. `none` (the default here too, for any
  /// caller that hasn't been updated to pass it) preserves the original
  /// unrestricted choice.
  final String recruitmentProcess;

  @override
  State<ChooseAssessmentTypeSheet> createState() =>
      _ChooseAssessmentTypeSheetState();
}

class _ChooseAssessmentTypeSheetState extends State<ChooseAssessmentTypeSheet> {
  late String _selectedType = widget.recruitmentProcess == 'quiz'
      ? 'quiz'
      : 'interview';

  bool get _isNarrowedToQuiz => widget.recruitmentProcess == 'quiz';

  Future<void> _continue() async {
    if (_isNarrowedToQuiz) {
      await _advanceToSharedQuiz();
      return;
    }

    Navigator.of(context).pop();
    if (_selectedType == 'quiz') {
      context.push(AppRoutes.organizationCreateQuiz(widget.applicationId));
    } else {
      context.push(
        AppRoutes.organizationScheduleInterview(widget.applicationId),
      );
    }
  }

  Future<void> _advanceToSharedQuiz() async {
    final provider = context.read<OrganizationAssessmentProvider>();
    final success = await provider.advanceToSharedQuiz(widget.applicationId);
    if (!mounted) return;

    if (!success) {
      if (provider.actionErrorMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
      }
      return;
    }

    final created = provider.latestAssessment;
    final updatedApplication = created?.application;
    final applicationsProvider = context
        .read<OrganizationApplicationsProvider>();
    if (updatedApplication != null) {
      applicationsProvider.patchApplication(updatedApplication);
    } else {
      applicationsProvider.loadApplicationDetails(
        widget.applicationId,
        forceRefresh: true,
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Candidate advanced to the shared quiz')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // Only ever touches `OrganizationAssessmentProvider` when narrowed to
    // Quiz -- the `none`/`interview` paths still make no backend request
    // and need no provider in the widget tree at all, exactly as before
    // this phase (short-circuited, not just unused: `context.select` would
    // throw if actually called with no provider present).
    final isBusy = _isNarrowedToQuiz
        ? context.select<OrganizationAssessmentProvider, bool>(
            (provider) => provider.isCreatingFor(widget.applicationId),
          )
        : false;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screenHorizontal,
        right: AppSpacing.screenHorizontal,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Choose Assessment'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _isNarrowedToQuiz
                ? 'This opportunity uses a shared quiz for every candidate.'
                : 'How should this candidate be evaluated?',
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (widget.recruitmentProcess == 'none')
            RadioGroup<String>(
              groupValue: _selectedType,
              onChanged: (value) =>
                  setState(() => _selectedType = value ?? _selectedType),
              child: Column(
                children: [
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    value: 'interview',
                    title: const Text('Interview'),
                    subtitle: const Text(
                      'Schedule an online, onsite, or phone interview.',
                    ),
                  ),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    value: 'quiz',
                    title: const Text('Quiz'),
                    subtitle: const Text(
                      'Assess candidates with a short quiz.',
                    ),
                  ),
                ],
              ),
            )
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                widget.recruitmentProcess == 'quiz'
                    ? Icons.quiz_outlined
                    : Icons.event_outlined,
              ),
              title: Text(
                widget.recruitmentProcess == 'quiz' ? 'Quiz' : 'Interview',
              ),
              subtitle: Text(
                widget.recruitmentProcess == 'quiz'
                    ? "The candidate will use this opportunity's shared quiz."
                    : 'Schedule an online, onsite, or phone interview.',
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: _isNarrowedToQuiz ? 'Advance to Quiz' : 'Continue',
            isLoading: isBusy,
            onPressed: isBusy ? null : _continue,
          ),
        ],
      ),
    );
  }
}

/// Shows [ChooseAssessmentTypeSheet] for [applicationId].
Future<void> showChooseAssessmentTypeSheet(
  BuildContext context, {
  required int applicationId,
  String recruitmentProcess = 'none',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ChooseAssessmentTypeSheet(
      applicationId: applicationId,
      recruitmentProcess: recruitmentProcess,
    ),
  );
}
