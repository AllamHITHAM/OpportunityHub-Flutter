import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/cv_model.dart';
import '../../../providers/student_cv_provider.dart';
import '../data/picked_cv_file.dart';

/// Opens the platform file picker restricted to a single PDF and returns
/// the picked bytes, or `null` if the user cancelled or the platform
/// couldn't provide bytes. The real, default implementation of
/// [StudentCvScreen.pickCvFile] — overridable in tests so the Add CV flow
/// can be exercised without a real platform file-picker channel.
Future<PickedCvFile?> pickCvFileFromDevice() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;

  final picked = result.files.single;
  final bytes = picked.bytes;
  if (bytes == null) return null;

  return PickedCvFile(filename: picked.name, bytes: bytes);
}

/// Lists the authenticated student's CVs, with add/set-default/delete/view
/// actions. No apply/CV-selection UI belongs here yet — this phase covers
/// CV management (now with a real PDF upload, Phase 8A-4) only.
class StudentCvScreen extends StatefulWidget {
  const StudentCvScreen({super.key, this.pickCvFile = pickCvFileFromDevice});

  /// Defaults to the real platform file picker ([pickCvFileFromDevice]) —
  /// overridable so widget tests can simulate a file selection without a
  /// real platform channel.
  final Future<PickedCvFile?> Function() pickCvFile;

  @override
  State<StudentCvScreen> createState() => _StudentCvScreenState();
}

class _StudentCvScreenState extends State<StudentCvScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred to the post-frame callback: the provider's first action is
    // a synchronous notifyListeners() (setting isLoadingList), and calling
    // that directly from initState would try to rebuild this screen's own
    // ancestor Provider while the widget tree is still being built for the
    // first time — a real Flutter build-phase constraint.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StudentCvProvider>().loadCvs();
    });
  }

  Future<void> _openAddCvSheet() async {
    final provider = context.read<StudentCvProvider>();
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: provider,
        child: _AddCvSheet(pickFile: widget.pickCvFile),
      ),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('CV added successfully')));
    }
  }

  Future<void> _confirmDelete(CvModel cv) async {
    final provider = context.read<StudentCvProvider>();

    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Delete CV',
      message:
          'Are you sure you want to delete "${cv.title}"? '
          'This cannot be undone.',
      confirmLabel: 'Delete',
      type: AppConfirmationType.danger,
    );
    if (!confirmed) return;

    final success = await provider.deleteCv(cv.id);
    if (!mounted) return;

    if (!success && provider.actionErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
    }
  }

  Future<void> _setDefault(CvModel cv) async {
    final provider = context.read<StudentCvProvider>();

    final success = await provider.setDefaultCv(cv.id);
    if (!mounted) return;

    if (!success && provider.actionErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
    }
  }

  /// Downloads the CV via the secure backend endpoint and confirms success
  /// — v1 stops at fetching the (already ownership-checked, private) bytes
  /// rather than attempting OS-level PDF viewing/saving, which would need
  /// platform file-opening dependencies beyond this phase's scope.
  Future<void> _viewCv(CvModel cv) async {
    final provider = context.read<StudentCvProvider>();

    final bytes = await provider.downloadCv(cv.id);
    if (!mounted) return;

    if (bytes != null) {
      final kb = (bytes.length / 1024).toStringAsFixed(0);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('CV downloaded ($kb KB)')));
    } else if (provider.downloadErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.downloadErrorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentCvProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My CVs'),
        actions: [
          IconButton(
            onPressed: _openAddCvSheet,
            icon: const Icon(Icons.add),
            tooltip: 'Add CV',
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(provider)),
    );
  }

  Widget _buildBody(StudentCvProvider provider) {
    if (provider.isLoadingList && provider.cvs.isEmpty) {
      return const AppSkeletonList();
    }

    if (provider.listErrorMessage != null && provider.cvs.isEmpty) {
      return AppErrorView(
        message: provider.listErrorMessage!,
        onRetry: () => provider.loadCvs(forceRefresh: true),
      );
    }

    if (provider.cvs.isEmpty) {
      return AppEmptyView(
        title: 'No CVs Yet',
        message: 'Add your first CV to get ready to apply for opportunities.',
        icon: Icons.description_outlined,
        actionLabel: 'Add CV',
        onAction: _openAddCvSheet,
      );
    }

    return RefreshIndicator(
      onRefresh: () => provider.loadCvs(forceRefresh: true),
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
        itemCount: provider.cvs.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final cv = provider.cvs[index];
          return _CvCard(
            cv: cv,
            isBusy: provider.isBusy(cv.id),
            isDownloading: provider.isDownloading(cv.id),
            onSetDefault: () => _setDefault(cv),
            onDelete: () => _confirmDelete(cv),
            onView: () => _viewCv(cv),
          );
        },
      ),
    );
  }
}

class _CvCard extends StatelessWidget {
  const _CvCard({
    required this.cv,
    required this.isBusy,
    required this.isDownloading,
    required this.onSetDefault,
    required this.onDelete,
    required this.onView,
  });

  final CvModel cv;
  final bool isBusy;
  final bool isDownloading;
  final VoidCallback onSetDefault;
  final VoidCallback onDelete;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(cv.title, style: textTheme.titleMedium)),
              if (cv.isDefault) ...[
                const SizedBox(width: AppSpacing.xs),
                const StatusChip(
                  label: 'Default',
                  type: AppStatusType.success,
                  compact: true,
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: [
              const StatusChip(label: 'PDF', compact: true),
              StatusChip(label: 'Version ${cv.version}', compact: true),
              if (cv.createdByAi)
                const StatusChip(
                  label: 'AI Generated',
                  type: AppStatusType.info,
                  compact: true,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'View CV',
                  isLoading: isDownloading,
                  onPressed: isDownloading ? null : onView,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (!cv.isDefault) ...[
                Expanded(
                  child: SecondaryButton(
                    label: 'Set as Default',
                    isLoading: isBusy,
                    onPressed: isBusy ? null : onSetDefault,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              IconButton(
                onPressed: isBusy ? null : onDelete,
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A modal bottom sheet to add a CV: a title field plus a real PDF file
/// picker (Phase 8A-4) — replaces the old manual `file_path` text field.
class _AddCvSheet extends StatefulWidget {
  const _AddCvSheet({required this.pickFile});

  final Future<PickedCvFile?> Function() pickFile;

  @override
  State<_AddCvSheet> createState() => _AddCvSheetState();
}

class _AddCvSheetState extends State<_AddCvSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();

  PickedCvFile? _selectedFile;
  String? _fileErrorMessage;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  // Matches the backend's own limits (StoreCVRequest: title max:255,
  // file max:5120 KB) so an over-length/oversized value is rejected
  // locally instead of round-tripping to a 422.
  static const _titleMaxLength = 255;
  static const _maxFileSizeBytes = 5 * 1024 * 1024;

  String? _validateTitle(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Title is required';
    }
    if (trimmed.length > _titleMaxLength) {
      return 'Title must be $_titleMaxLength characters or fewer';
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

  Future<void> _submit(StudentCvProvider provider) async {
    FocusScope.of(context).unfocus();

    final isValid = _formKey.currentState?.validate() ?? false;
    final file = _selectedFile;

    if (file == null) {
      setState(() => _fileErrorMessage ??= 'Please select a PDF file.');
    }
    if (!isValid || file == null) return;

    final created = await provider.createCv(
      title: _titleController.text.trim(),
      file: file,
    );
    if (!mounted) return;
    if (created == null) return;

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentCvProvider>();
    final isLoading = provider.isSubmitting;
    final textTheme = Theme.of(context).textTheme;

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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SectionHeader(title: 'Add CV'),
              const SizedBox(height: AppSpacing.xs),
              AppTextField(
                controller: _titleController,
                label: 'Title',
                hint: 'e.g. Software Engineer CV',
                enabled: !isLoading,
                textInputAction: TextInputAction.done,
                validator: _validateTitle,
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
                label: 'Add CV',
                isLoading: isLoading,
                onPressed: () => _submit(provider),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
