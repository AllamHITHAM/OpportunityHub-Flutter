import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/education_verification_model.dart';
import '../../../providers/student_education_verification_provider.dart';
import '../../cv/data/picked_cv_file.dart';
import '../../opportunities/presentation/opportunity_display.dart';
import '../../cv/presentation/student_cv_screen.dart' show pickCvFileFromDevice;

/// The Student's own education-verification submission and status (Phase
/// 8B-1). "Verified" means an Admin reviewed the uploaded document and
/// approved it -- not a direct university/government check; see
/// docs/BUSINESS_RULES.md. Renders one of four states entirely from
/// [EducationVerificationModel.status]: not-submitted (a form), pending
/// (read-only + a status message), verified (read-only), or rejected
/// (the reason, plus a resubmission form).
class StudentEducationVerificationScreen extends StatefulWidget {
  const StudentEducationVerificationScreen({
    super.key,
    this.pickDocumentFile = pickCvFileFromDevice,
  });

  /// Defaults to the same real platform file picker `StudentCvScreen`
  /// uses -- overridable so widget tests can simulate a file selection
  /// without a real platform channel.
  final Future<PickedCvFile?> Function() pickDocumentFile;

  @override
  State<StudentEducationVerificationScreen> createState() =>
      _StudentEducationVerificationScreenState();
}

class _StudentEducationVerificationScreenState
    extends State<StudentEducationVerificationScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred to the post-frame callback — see
    // StudentOpportunitiesScreen.initState for why calling this directly
    // here would violate Flutter's build-phase constraints.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StudentEducationVerificationProvider>().load();
    });
  }

  Future<void> _viewDocument() async {
    final provider = context.read<StudentEducationVerificationProvider>();

    final bytes = await provider.downloadDocument();
    if (!mounted) return;

    if (bytes != null) {
      final kb = (bytes.length / 1024).toStringAsFixed(0);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Document downloaded ($kb KB)')));
    } else if (provider.downloadErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.downloadErrorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentEducationVerificationProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Education Verification')),
      body: SafeArea(child: _buildBody(provider)),
    );
  }

  Widget _buildBody(StudentEducationVerificationProvider provider) {
    final verification = provider.verification;

    if (provider.isLoading && verification == null) {
      return const AppSkeletonList();
    }

    if (provider.errorMessage != null && verification == null) {
      return AppErrorView(
        message: provider.errorMessage!,
        onRetry: () => provider.load(forceRefresh: true),
      );
    }

    if (verification == null) {
      // Neither loading, nor an error, nor a result yet -- the load
      // hasn't been kicked off (e.g. the very first frame).
      return const AppLoading();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
      child: verification.isNotSubmitted || verification.isRejected
          ? _SubmissionForm(
              pickFile: widget.pickDocumentFile,
              // Only actually a "rejected" resubmission when the current
              // verification really is rejected -- passing it
              // unconditionally here would make the not-submitted, first-
              // time form incorrectly render as a resubmission (wrong
              // header text, a spurious "Rejected" banner).
              rejected: verification.isRejected ? verification : null,
            )
          : _SubmittedDetails(
              verification: verification,
              isDownloading: provider.isDownloading,
              onViewDocument: _viewDocument,
            ),
    );
  }
}

/// The not-submitted / rejected-resubmission form. [rejected] is the
/// current verification when resubmitting after a rejection (its reason
/// is shown, and its institution/degree pre-fill the fields) -- `null`
/// (the default) means a brand-new, first-time submission.
class _SubmissionForm extends StatefulWidget {
  const _SubmissionForm({required this.pickFile, this.rejected});

  final Future<PickedCvFile?> Function() pickFile;
  final EducationVerificationModel? rejected;

  @override
  State<_SubmissionForm> createState() => _SubmissionFormState();
}

class _SubmissionFormState extends State<_SubmissionForm> {
  final _formKey = GlobalKey<FormState>();
  late final _institutionController = TextEditingController(
    text: widget.rejected?.institutionName ?? '',
  );
  late final _degreeController = TextEditingController(
    text: widget.rejected?.degreeOrProgram ?? '',
  );

  PickedCvFile? _selectedFile;
  String? _fileErrorMessage;

  // Matches the backend's own limits (StoreEducationVerificationRequest:
  // both text fields max:255, file max:5120 KB).
  static const _fieldMaxLength = 255;
  static const _maxFileSizeBytes = 5 * 1024 * 1024;

  @override
  void dispose() {
    _institutionController.dispose();
    _degreeController.dispose();
    super.dispose();
  }

  String? _validateRequired(String? value, String label) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return '$label is required';
    if (trimmed.length > _fieldMaxLength) {
      return '$label must be $_fieldMaxLength characters or fewer';
    }
    return null;
  }

  Future<void> _pickFile() async {
    final picked = await widget.pickFile();
    if (picked == null) return;

    setState(() {
      if (!picked.filename.toLowerCase().endsWith('.pdf')) {
        _selectedFile = null;
        _fileErrorMessage = 'Only PDF files are supported.';
      } else if (picked.sizeInBytes > _maxFileSizeBytes) {
        _selectedFile = null;
        _fileErrorMessage = 'File must be 5 MB or smaller.';
      } else {
        _selectedFile = picked;
        _fileErrorMessage = null;
      }
    });
  }

  Future<void> _submit(StudentEducationVerificationProvider provider) async {
    FocusScope.of(context).unfocus();

    final isValid = _formKey.currentState?.validate() ?? false;
    final file = _selectedFile;

    if (file == null) {
      setState(() => _fileErrorMessage ??= 'Please select a PDF file.');
    }
    if (!isValid || file == null) return;

    final success = await provider.submit(
      institutionName: _institutionController.text.trim(),
      degreeOrProgram: _degreeController.text.trim(),
      file: file,
    );
    if (!mounted || !success) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Education verification submitted successfully'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentEducationVerificationProvider>();
    final isLoading = provider.isSubmitting;
    final textTheme = Theme.of(context).textTheme;
    final rejected = widget.rejected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rejected != null) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(
                  children: [
                    StatusChip(label: 'Rejected', type: AppStatusType.error),
                  ],
                ),
                if (rejected.rejectionReason != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(rejected.rejectionReason!, style: textTheme.bodyMedium),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: rejected != null
                    ? 'Resubmit Document'
                    : 'Submit Education Proof',
              ),
              const SizedBox(height: AppSpacing.xs),
              AppTextField(
                controller: _institutionController,
                label: 'Institution',
                hint: 'e.g. State University',
                enabled: !isLoading,
                validator: (value) => _validateRequired(value, 'Institution'),
              ),
              const SizedBox(height: AppSpacing.inputSpacing),
              AppTextField(
                controller: _degreeController,
                label: 'Degree / Program',
                hint: 'e.g. BSc Computer Science',
                enabled: !isLoading,
                textInputAction: TextInputAction.done,
                validator: (value) =>
                    _validateRequired(value, 'Degree / Program'),
              ),
              const SizedBox(height: AppSpacing.inputSpacing),
              SecondaryButton(
                label: _selectedFile == null ? 'Select PDF' : 'Change PDF',
                icon: Icons.attach_file,
                onPressed: isLoading ? null : _pickFile,
              ),
              if (_selectedFile != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Row(
                  children: [
                    const Icon(
                      Icons.picture_as_pdf_outlined,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Expanded(
                      child: Text(
                        _selectedFile!.filename,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (_fileErrorMessage != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  _fileErrorMessage!,
                  style: textTheme.bodySmall?.copyWith(color: AppColors.error),
                ),
              ],
              if (provider.formErrorMessage != null) ...[
                const SizedBox(height: AppSpacing.xs),
                AppErrorView(
                  title: 'Something Went Wrong',
                  message: provider.formErrorMessage!,
                  compact: true,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: rejected != null ? 'Resubmit' : 'Submit',
                isLoading: isLoading,
                onPressed: () => _submit(provider),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Read-only display for `pending` and `verified` states.
class _SubmittedDetails extends StatelessWidget {
  const _SubmittedDetails({
    required this.verification,
    required this.isDownloading,
    required this.onViewDocument,
  });

  final EducationVerificationModel verification;
  final bool isDownloading;
  final VoidCallback onViewDocument;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      verification.institutionName ?? '',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  StatusChip(
                    label: verification.isVerified ? 'Verified' : 'Pending',
                    type: verification.isVerified
                        ? AppStatusType.success
                        : AppStatusType.warning,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              OpportunityDetailRow(
                label: 'Degree / Program',
                value: verification.degreeOrProgram ?? 'Not specified',
              ),
              if (verification.submittedAt != null)
                OpportunityDetailRow(
                  label: 'Submitted',
                  value: formatDate(verification.submittedAt!),
                ),
              if (verification.isVerified && verification.reviewedAt != null)
                OpportunityDetailRow(
                  label: 'Reviewed',
                  value: formatDate(verification.reviewedAt!),
                ),
            ],
          ),
        ),
        if (verification.isPending) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Awaiting Admin review.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        SecondaryButton(
          label: 'View Document',
          isLoading: isDownloading,
          onPressed: isDownloading ? null : onViewDocument,
        ),
      ],
    );
  }
}
