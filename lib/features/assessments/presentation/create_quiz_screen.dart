import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../providers/organization_applications_provider.dart';
import '../../../providers/organization_assessment_provider.dart';
import '../../../routes/app_routes.dart';
import '../data/quiz_create_input.dart';

/// The Quiz draft-creation form reached from `ChooseAssessmentTypeSheet` —
/// the Quiz counterpart to `ScheduleInterviewScreen`. This screen creates
/// only the Quiz *draft* (title/instructions/time limit/passing score) --
/// questions are added afterward on `OrganizationQuizEditorScreen`, which
/// this screen navigates straight to on success. Reached by application ID
/// alone (a route parameter, never GoRouter `extra`), matching every other
/// organization-application route in this app.
class CreateQuizScreen extends StatefulWidget {
  const CreateQuizScreen({super.key, required this.applicationId});

  final int applicationId;

  @override
  State<CreateQuizScreen> createState() => _CreateQuizScreenState();
}

class _CreateQuizScreenState extends State<CreateQuizScreen> {
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _instructionsController = TextEditingController();
  final _timeLimitController = TextEditingController();
  final _passingScoreController = TextEditingController();

  /// Set once a 409 ("assessment already exists") response is received —
  /// permanently disables further submission for this form instance, the
  /// same guard `ScheduleInterviewScreen` uses for the identical conflict.
  bool _conflictDetected = false;

  @override
  void initState() {
    super.initState();
    // A previous, unrelated failed attempt on this same provider instance
    // must never bleed into a freshly-opened form — see
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
    _titleController.dispose();
    _instructionsController.dispose();
    _timeLimitController.dispose();
    _passingScoreController.dispose();
    super.dispose();
  }

  String? _fieldError(String field) {
    final provider = context.read<OrganizationAssessmentProvider>();
    final messages =
        provider.fieldErrors['quiz.$field'] ?? provider.fieldErrors[field];
    if (messages == null || messages.isEmpty) return null;
    return messages.first;
  }

  String? _titleValidator(String? value) {
    final backendError = _fieldError('title');
    if (backendError != null) return backendError;
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Title is required';
    if (text.length > 255) return 'Title must be 255 characters or fewer';
    return null;
  }

  String? _timeLimitValidator(String? value) {
    final backendError = _fieldError('time_limit_minutes');
    if (backendError != null) return backendError;
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = int.tryParse(text);
    if (parsed == null || parsed < 1) {
      return 'Enter a whole number of at least 1';
    }
    return null;
  }

  String? _passingScoreValidator(String? value) {
    final backendError = _fieldError('passing_score');
    if (backendError != null) return backendError;
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Passing score is required';
    final parsed = int.tryParse(text);
    if (parsed == null || parsed < 0 || parsed > 100) {
      return 'Enter a whole number between 0 and 100';
    }
    return null;
  }

  bool _isDuplicateConflict(OrganizationAssessmentProvider provider) {
    return provider.actionErrorMessage?.contains('already exists') ?? false;
  }

  Future<void> _submit(OrganizationAssessmentProvider provider) async {
    if (_conflictDetected) return;
    FocusScope.of(context).unfocus();

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    String? orNull(TextEditingController controller) {
      final value = controller.text.trim();
      return value.isEmpty ? null : value;
    }

    final input = QuizCreateInput(
      title: _titleController.text.trim(),
      instructions: orNull(_instructionsController),
      timeLimitMinutes: int.tryParse(_timeLimitController.text.trim()),
      passingScore: int.parse(_passingScoreController.text.trim()),
    );

    final success = await provider.createAssessment(
      applicationId: widget.applicationId,
      type: 'quiz',
      quizInput: input,
    );
    if (!mounted) return;

    if (!success) {
      // Re-run validation so any backend field errors surface inline
      // immediately, without waiting for the next field interaction.
      _formKey.currentState?.validate();

      if (_isDuplicateConflict(provider)) {
        setState(() => _conflictDetected = true);
        provider.loadForApplication(widget.applicationId, forceRefresh: true);
      }
      return;
    }

    final created = provider.assessment;
    final updatedApplication = created?.application;
    final applicationsProvider = context
        .read<OrganizationApplicationsProvider>();

    if (updatedApplication != null) {
      applicationsProvider.patchApplication(updatedApplication);
    } else {
      // The Assessment was still created successfully — only the response
      // didn't carry the application back. Don't lose the success; make
      // sure the details screen picks up the status change on its own.
      applicationsProvider.loadApplicationDetails(
        widget.applicationId,
        forceRefresh: true,
      );
    }

    final assessmentId = created?.id;
    if (assessmentId == null) return;

    // Immediately hand off to the Quiz editor — this create step is done,
    // so it's replaced rather than left in the back stack (going "back"
    // into a stale draft-creation form for an already-created quiz would
    // make no sense).
    context.pushReplacement(AppRoutes.organizationQuizEditor(assessmentId));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationAssessmentProvider>();
    final isLoading = provider.isCreatingFor(widget.applicationId);
    final hasFieldErrors = provider.fieldErrors.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Create Quiz')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionHeader(title: 'Quiz Details'),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Questions are added after the quiz draft is '
                        'created.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.inputSpacing),
                      AppTextField(
                        controller: _titleController,
                        label: 'Title',
                        maxLength: 255,
                        enabled: !isLoading,
                        textInputAction: TextInputAction.next,
                        validator: _titleValidator,
                      ),
                      const SizedBox(height: AppSpacing.inputSpacing),
                      AppTextField(
                        controller: _instructionsController,
                        label: 'Instructions (optional)',
                        maxLines: 4,
                        enabled: !isLoading,
                        textInputAction: TextInputAction.newline,
                      ),
                      const SizedBox(height: AppSpacing.inputSpacing),
                      AppTextField(
                        controller: _timeLimitController,
                        label: 'Time Limit Minutes (optional)',
                        keyboardType: TextInputType.number,
                        enabled: !isLoading,
                        textInputAction: TextInputAction.next,
                        validator: _timeLimitValidator,
                      ),
                      const SizedBox(height: AppSpacing.inputSpacing),
                      AppTextField(
                        controller: _passingScoreController,
                        label: 'Passing Score (%)',
                        hint: '0-100',
                        keyboardType: TextInputType.number,
                        enabled: !isLoading,
                        textInputAction: TextInputAction.done,
                        validator: _passingScoreValidator,
                      ),
                      if (!hasFieldErrors &&
                          provider.actionErrorMessage != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        AppErrorView(
                          title: 'Something Went Wrong',
                          message: provider.actionErrorMessage!,
                          compact: true,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      PrimaryButton(
                        label: 'Create Quiz',
                        isLoading: isLoading,
                        onPressed: _conflictDetected
                            ? null
                            : () => _submit(provider),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
