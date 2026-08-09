import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../routes/app_routes.dart';

/// A compact modal bottom sheet for choosing which assessment path an
/// organization wants for a shortlisted application — Interview or, as of
/// Phase 6B-2, Quiz. Call [showChooseAssessmentTypeSheet] rather than
/// constructing this directly.
///
/// This sheet never makes a backend request itself — Continue only
/// navigates to the dedicated Schedule Interview or Create Quiz screen for
/// the chosen application; the actual Assessment creation happens there.
class ChooseAssessmentTypeSheet extends StatefulWidget {
  const ChooseAssessmentTypeSheet({super.key, required this.applicationId});

  final int applicationId;

  @override
  State<ChooseAssessmentTypeSheet> createState() =>
      _ChooseAssessmentTypeSheetState();
}

class _ChooseAssessmentTypeSheetState extends State<ChooseAssessmentTypeSheet> {
  String _selectedType = 'interview';

  void _continue() {
    Navigator.of(context).pop();
    if (_selectedType == 'quiz') {
      context.push(AppRoutes.organizationCreateQuiz(widget.applicationId));
    } else {
      context.push(
        AppRoutes.organizationScheduleInterview(widget.applicationId),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

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
            'How should this candidate be evaluated?',
            style: textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
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
                  subtitle: const Text('Assess candidates with a short quiz.'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(label: 'Continue', onPressed: _continue),
        ],
      ),
    );
  }
}

/// Shows [ChooseAssessmentTypeSheet] for [applicationId].
Future<void> showChooseAssessmentTypeSheet(
  BuildContext context, {
  required int applicationId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ChooseAssessmentTypeSheet(applicationId: applicationId),
  );
}
