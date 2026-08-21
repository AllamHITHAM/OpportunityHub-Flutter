import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../providers/organization_assessment_provider.dart';
import 'assessment_display.dart';

/// A modal bottom sheet for completing a Scheduled Interview and,
/// optionally, recording its outcome — the step that moves
/// `Assessment.status` to `completed`, which is what makes Send Offer
/// eligible (see `_StatusActionsSection` in
/// `organization_application_details_screen.dart` for the eligibility
/// gate). Every field here is optional: `PUT
/// /organization/interviews/{interview}/complete` accepts a fully empty
/// body and still marks the interview completed — see
/// `CompleteInterviewRequest`'s fully-nullable rules on the backend. There
/// is no edit/undo counterpart in v1, matching `SendOfferSheet`'s own
/// "no edit/resend" precedent for a terminal action.
class CompleteInterviewSheet extends StatefulWidget {
  const CompleteInterviewSheet({
    super.key,
    required this.applicationId,
    required this.interviewId,
  });

  final int applicationId;
  final int interviewId;

  @override
  State<CompleteInterviewSheet> createState() =>
      _CompleteInterviewSheetState();
}

class _CompleteInterviewSheetState extends State<CompleteInterviewSheet> {
  final _formKey = GlobalKey<FormState>();
  final _ratingController = TextEditingController();
  final _feedbackController = TextEditingController();

  String? _decision;

  @override
  void initState() {
    super.initState();
    // A previous, unrelated failed attempt on this same provider instance
    // must never bleed into a freshly-opened sheet — matches
    // ScheduleInterviewScreen's identical reasoning.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<OrganizationAssessmentProvider>();
      provider.clearActionError();
      provider.clearFieldErrors();
    });
  }

  @override
  void dispose() {
    _ratingController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  String? _fieldError(String field) {
    final provider = context.read<OrganizationAssessmentProvider>();
    final messages = provider.fieldErrors[field];
    if (messages == null || messages.isEmpty) return null;
    return messages.first;
  }

  String? _ratingValidator(String? value) {
    final backendError = _fieldError('rating');
    if (backendError != null) return backendError;
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = int.tryParse(text);
    if (parsed == null || parsed < 1) {
      return 'Enter a whole number of at least 1';
    }
    return null;
  }

  String? _feedbackValidator(String? value) {
    final backendError = _fieldError('company_feedback');
    if (backendError != null) return backendError;
    if ((value?.trim().length ?? 0) > 2000) {
      return 'Feedback must be 2000 characters or fewer';
    }
    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    final provider = context.read<OrganizationAssessmentProvider>();
    final ratingText = _ratingController.text.trim();

    final success = await provider.completeInterview(
      applicationId: widget.applicationId,
      interviewId: widget.interviewId,
      decision: _decision,
      rating: ratingText.isEmpty ? null : int.tryParse(ratingText),
      companyFeedback: _feedbackController.text,
    );
    if (!mounted) return;

    if (!success) {
      // Re-run validation so any backend field errors surface inline
      // immediately — matches ScheduleInterviewScreen/SendOfferSheet's
      // identical pattern. Entered values are untouched (the controllers
      // were never cleared), and `assessment` was never touched by the
      // provider on failure, so no false-completed state is shown.
      _formKey.currentState?.validate();
      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationAssessmentProvider>();
    final isBusy = provider.isCompletingInterview(widget.interviewId);
    final hasFieldErrors = provider.fieldErrors.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screenHorizontal,
        right: AppSpacing.screenHorizontal,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(title: 'Complete Interview'),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String?>(
                initialValue: _decision,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Decision (optional)',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('No decision'),
                  ),
                  // `interviewDecisionLabels` also has a `pending` entry
                  // for display purposes elsewhere — deliberately excluded
                  // here, since `CompleteInterviewRequest` never accepts it
                  // as a submitted decision (an outcome can't be reset to
                  // "not yet decided" at completion time).
                  for (final value in const ['passed', 'failed', 'waiting'])
                    DropdownMenuItem<String?>(
                      value: value,
                      child: Text(interviewDecisionLabels[value] ?? value),
                    ),
                ],
                onChanged: isBusy
                    ? null
                    : (value) => setState(() => _decision = value),
              ),
              const SizedBox(height: AppSpacing.inputSpacing),
              AppTextField(
                controller: _ratingController,
                label: 'Rating (optional)',
                keyboardType: TextInputType.number,
                enabled: !isBusy,
                textInputAction: TextInputAction.next,
                validator: _ratingValidator,
              ),
              const SizedBox(height: AppSpacing.inputSpacing),
              AppTextField(
                controller: _feedbackController,
                label: 'Feedback (optional)',
                maxLines: 4,
                maxLength: 2000,
                enabled: !isBusy,
                textInputAction: TextInputAction.newline,
                validator: _feedbackValidator,
              ),
              if (!hasFieldErrors && provider.actionErrorMessage != null) ...[
                const SizedBox(height: AppSpacing.xs),
                AppErrorView(
                  title: 'Something Went Wrong',
                  message: provider.actionErrorMessage!,
                  compact: true,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: 'Complete Interview',
                isLoading: isBusy,
                onPressed: isBusy ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows [CompleteInterviewSheet] for [applicationId]/[interviewId].
/// Returns `true` only if the interview was successfully completed.
Future<bool> showCompleteInterviewSheet(
  BuildContext context, {
  required int applicationId,
  required int interviewId,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => CompleteInterviewSheet(
      applicationId: applicationId,
      interviewId: interviewId,
    ),
  );
  return result ?? false;
}
