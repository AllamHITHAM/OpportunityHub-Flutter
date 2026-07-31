import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../providers/student_applications_provider.dart';
import '../../../providers/student_cv_provider.dart';
import '../../../routes/app_routes.dart';

/// A modal bottom sheet to apply to an opportunity — CV selection plus an
/// optional cover letter. Call [showApplyBottomSheet] rather than
/// constructing this directly; it also wires up the ancestor providers
/// this sheet needs.
class ApplyBottomSheet extends StatefulWidget {
  const ApplyBottomSheet({
    super.key,
    required this.opportunityId,
    required this.opportunityTitle,
  });

  final int opportunityId;
  final String opportunityTitle;

  @override
  State<ApplyBottomSheet> createState() => _ApplyBottomSheetState();
}

class _ApplyBottomSheetState extends State<ApplyBottomSheet> {
  final _coverLetterController = TextEditingController();
  int? _selectedCvId;
  bool _defaultCvApplied = false;

  /// Whether this sheet instance has attempted a submission yet. The
  /// provider's `formErrorMessage` only gets cleared when a new `apply()`
  /// call starts — not when a sheet is dismissed and reopened — so
  /// without this guard a freshly-opened sheet could briefly show an
  /// error left over from a previous sheet session, before the student
  /// has done anything in this one.
  bool _hasSubmitted = false;

  @override
  void dispose() {
    _coverLetterController.dispose();
    super.dispose();
  }

  void _goToManageCvs() {
    Navigator.of(context).pop(false);
    context.push(AppRoutes.studentCvs);
  }

  Future<void> _submit(StudentApplicationsProvider applicationsProvider) async {
    final cvId = _selectedCvId;
    if (cvId == null) return;

    _hasSubmitted = true;
    FocusScope.of(context).unfocus();

    final coverLetter = _coverLetterController.text.trim();
    final created = await applicationsProvider.apply(
      opportunityId: widget.opportunityId,
      cvId: cvId,
      coverLetter: coverLetter.isEmpty ? null : coverLetter,
    );
    if (!mounted) return;
    if (created == null) return;

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final cvProvider = context.watch<StudentCvProvider>();
    final applicationsProvider = context.watch<StudentApplicationsProvider>();
    final isLoading = applicationsProvider.isSubmitting;

    // Pre-select the default CV exactly once, as soon as it becomes
    // available — never overrides a selection the student already made.
    if (!_defaultCvApplied && cvProvider.defaultCv != null) {
      _selectedCvId = cvProvider.defaultCv!.id;
      _defaultCvApplied = true;
    }

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screenHorizontal,
        right: AppSpacing.screenHorizontal,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SectionHeader(title: 'Apply to ${widget.opportunityTitle}'),
            const SizedBox(height: AppSpacing.sm),
            if (cvProvider.isLoadingList && cvProvider.cvs.isEmpty)
              const AppLoading(compact: true)
            else if (cvProvider.cvs.isEmpty)
              AppEmptyView(
                compact: true,
                icon: Icons.description_outlined,
                title: 'No CV Yet',
                message: 'Add a CV before applying to this opportunity.',
                actionLabel: 'Manage CVs',
                onAction: _goToManageCvs,
              )
            else ...[
              Text('CV', style: Theme.of(context).textTheme.titleSmall),
              RadioGroup<int>(
                groupValue: _selectedCvId,
                onChanged: isLoading
                    ? (_) {}
                    : (value) => setState(() => _selectedCvId = value),
                child: Column(
                  children: [
                    for (final cv in cvProvider.cvs)
                      RadioListTile<int>(
                        contentPadding: EdgeInsets.zero,
                        value: cv.id,
                        enabled: !isLoading,
                        title: Text(cv.title),
                        subtitle: Text(cv.filePath),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.inputSpacing),
              AppTextField(
                controller: _coverLetterController,
                label: 'Cover Letter (optional)',
                hint: 'Tell the organization why you are a good fit',
                maxLines: 4,
                maxLength: 2000,
                enabled: !isLoading,
              ),
              if (_hasSubmitted &&
                  applicationsProvider.formErrorMessage != null) ...[
                const SizedBox(height: AppSpacing.xs),
                AppErrorView(
                  title: 'Something Went Wrong',
                  message: applicationsProvider.formErrorMessage!,
                  compact: true,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: 'Submit Application',
                isLoading: isLoading,
                onPressed: _selectedCvId == null
                    ? null
                    : () => _submit(applicationsProvider),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shows [ApplyBottomSheet] with the ancestor providers it needs, and
/// returns `true` only when an application was successfully submitted.
Future<bool> showApplyBottomSheet(
  BuildContext context, {
  required int opportunityId,
  required String opportunityTitle,
}) async {
  final cvProvider = context.read<StudentCvProvider>();
  final applicationsProvider = context.read<StudentApplicationsProvider>();

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => MultiProvider(
      providers: [
        ChangeNotifierProvider<StudentCvProvider>.value(value: cvProvider),
        ChangeNotifierProvider<StudentApplicationsProvider>.value(
          value: applicationsProvider,
        ),
      ],
      child: ApplyBottomSheet(
        opportunityId: opportunityId,
        opportunityTitle: opportunityTitle,
      ),
    ),
  );
  return result ?? false;
}
