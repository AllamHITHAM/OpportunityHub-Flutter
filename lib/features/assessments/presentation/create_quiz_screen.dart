import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../providers/organization_applications_provider.dart';
import '../../../providers/organization_assessment_provider.dart';
import '../../../providers/organization_quiz_provider.dart';
import '../../../routes/app_routes.dart';
import '../data/quiz_create_input.dart';

/// The Quiz draft-creation form reached from `ChooseAssessmentTypeSheet` —
/// the Quiz counterpart to `ScheduleInterviewScreen`. This screen creates
/// only the Quiz *draft* (title/instructions/time limit/passing score,
/// question display mode, result release mode — Phase 10A.2) -- questions
/// are added afterward on `OrganizationQuizEditorScreen`, which this
/// screen navigates straight to on success. Reached by application ID
/// alone (a route parameter, never GoRouter `extra`), matching every other
/// organization-application route in this app.
///
/// **Phase 10A.4B**: the exact same form also creates the *shared*
/// Opportunity Quiz template when [opportunityId] is given instead of
/// [applicationId] — the validated field set is identical
/// ([QuizCreateInput]), only which provider/endpoint receives it differs
/// (see [_isTemplateMode]). Exactly one of the two constructor params is
/// ever set.
class CreateQuizScreen extends StatefulWidget {
  const CreateQuizScreen({super.key, this.applicationId, this.opportunityId})
    : assert(
        (applicationId == null) != (opportunityId == null),
        'Exactly one of applicationId/opportunityId must be set',
      );

  final int? applicationId;
  final int? opportunityId;

  @override
  State<CreateQuizScreen> createState() => _CreateQuizScreenState();
}

class _CreateQuizScreenState extends State<CreateQuizScreen> {
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _instructionsController = TextEditingController();
  final _timeLimitController = TextEditingController();
  final _passingScoreController = TextEditingController();
  final _questionsPerPageController = TextEditingController();
  final _releaseDateDisplayController = TextEditingController();
  final _releaseTimeDisplayController = TextEditingController();
  final _availabilityDelayDaysController = TextEditingController(text: '0');
  final _availabilityTimeDisplayController = TextEditingController();
  final _submissionWindowHoursController = TextEditingController();

  /// Phase 10A.4B addendum — the shared availability policy's time-of-day
  /// component, template mode only.
  TimeOfDay? _availabilityTime;

  /// One of: single, paginated, all (Phase 10A.2).
  String _displayMode = 'all';

  /// One of: manual, immediate, scheduled (Phase 10A.2).
  String _resultReleaseMode = 'immediate';

  DateTime? _releaseDate;
  TimeOfDay? _releaseTime;

  /// Set once a 409 ("assessment already exists") response is received —
  /// permanently disables further submission for this form instance, the
  /// same guard `ScheduleInterviewScreen` uses for the identical conflict.
  /// Only ever reachable in the ad-hoc (non-template) path.
  bool _conflictDetected = false;

  bool get _isTemplateMode => widget.opportunityId != null;

  @override
  void initState() {
    super.initState();
    // A previous, unrelated failed attempt on this same provider instance
    // must never bleed into a freshly-opened form — see
    // ScheduleInterviewScreen's identical reasoning.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isTemplateMode) {
        final provider = context.read<OrganizationQuizProvider>();
        provider.clearActionErrors();
        // Establishes `loadedOpportunityId` (template mode) before
        // `_submit()` can call `createOrUpdateSettings()` — this screen is
        // only ever reached when no template exists yet, so the resulting
        // `quiz == null` correctly makes that call *create*, not update.
        provider.loadQuizForOpportunity(widget.opportunityId!);
      } else {
        final provider = context.read<OrganizationAssessmentProvider>();
        provider.clearActionError();
        provider.clearFieldErrors();
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _instructionsController.dispose();
    _timeLimitController.dispose();
    _passingScoreController.dispose();
    _questionsPerPageController.dispose();
    _releaseDateDisplayController.dispose();
    _releaseTimeDisplayController.dispose();
    _availabilityDelayDaysController.dispose();
    _availabilityTimeDisplayController.dispose();
    _submissionWindowHoursController.dispose();
    super.dispose();
  }

  DateTime? get _combinedReleaseAt {
    final date = _releaseDate;
    final time = _releaseTime;
    if (date == null || time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String? _fieldError(String field) {
    // The Opportunity-template endpoint's fields are flat (`title`, never
    // `quiz.title`) -- the ad-hoc endpoint nests them under `quiz.`. Both
    // providers keep whatever key the backend actually sent, unmodified.
    final fieldErrors = _isTemplateMode
        ? context.read<OrganizationQuizProvider>().fieldErrors
        : context.read<OrganizationAssessmentProvider>().fieldErrors;
    final messages = fieldErrors['quiz.$field'] ?? fieldErrors[field];
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

  String? _questionsPerPageValidator(String? value) {
    final backendError = _fieldError('questions_per_page');
    if (backendError != null) return backendError;
    if (_displayMode != 'paginated') return null;
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Questions per page is required';
    final parsed = int.tryParse(text);
    if (parsed == null || parsed < 1) {
      return 'Enter a whole number of at least 1';
    }
    return null;
  }

  String? _releaseDateValidator(String? value) {
    if (_resultReleaseMode != 'scheduled') return null;
    if (_releaseDate == null) return 'Release date is required';
    return null;
  }

  String? _releaseTimeValidator(String? value) {
    if (_resultReleaseMode != 'scheduled') return null;
    if (_releaseTime == null) return 'Release time is required';
    final combined = _combinedReleaseAt;
    if (combined != null && !combined.isAfter(DateTime.now())) {
      return 'Release date and time must be in the future';
    }
    return null;
  }

  Future<void> _pickReleaseDate(bool isLoading) async {
    if (isLoading) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialDate = _releaseDate != null && !_releaseDate!.isBefore(today)
        ? _releaseDate!
        : today;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: DateTime(today.year + 5),
    );
    if (picked == null) return;
    setState(() {
      _releaseDate = picked;
      _releaseDateDisplayController.text = formatDate(picked);
    });
  }

  String? _availabilityDelayDaysValidator(String? value) {
    if (!_isTemplateMode) return null;
    final backendError = _fieldError('availability_delay_days');
    if (backendError != null) return backendError;
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Required';
    final parsed = int.tryParse(text);
    if (parsed == null || parsed < 0) return 'Enter 0 or a positive whole number';
    return null;
  }

  String? _availabilityTimeValidator(String? value) {
    if (!_isTemplateMode) return null;
    final backendError = _fieldError('availability_time');
    if (backendError != null) return backendError;
    if (_availabilityTime == null) return 'Time is required';
    return null;
  }

  String? _submissionWindowHoursValidator(String? value) {
    if (!_isTemplateMode) return null;
    final backendError = _fieldError('submission_window_hours');
    if (backendError != null) return backendError;
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Required';
    final parsed = int.tryParse(text);
    if (parsed == null || parsed < 1) {
      return 'Enter a whole number of at least 1';
    }
    return null;
  }

  Future<void> _pickAvailabilityTime(bool isLoading) async {
    if (isLoading) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: _availabilityTime ?? const TimeOfDay(hour: 9, minute: 0),
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (picked == null) return;
    setState(() {
      _availabilityTime = picked;
      _availabilityTimeDisplayController.text = picked.format(context);
    });
  }

  Future<void> _pickReleaseTime(bool isLoading) async {
    if (isLoading) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: _releaseTime ?? TimeOfDay.now(),
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (picked == null) return;
    setState(() {
      _releaseTime = picked;
      _releaseTimeDisplayController.text = picked.format(context);
    });
  }

  bool _isDuplicateConflict(OrganizationAssessmentProvider provider) {
    return provider.actionErrorMessage?.contains('already exists') ?? false;
  }

  QuizCreateInput get _input {
    String? orNull(TextEditingController controller) {
      final value = controller.text.trim();
      return value.isEmpty ? null : value;
    }

    return QuizCreateInput(
      title: _titleController.text.trim(),
      instructions: orNull(_instructionsController),
      timeLimitMinutes: int.tryParse(_timeLimitController.text.trim()),
      passingScore: int.parse(_passingScoreController.text.trim()),
      displayMode: _displayMode,
      questionsPerPage: _displayMode == 'paginated'
          ? int.tryParse(_questionsPerPageController.text.trim())
          : null,
      resultReleaseMode: _resultReleaseMode,
      resultReleaseAt: _resultReleaseMode == 'scheduled'
          ? _combinedReleaseAt
          : null,
      availabilityDelayDays: _isTemplateMode
          ? int.tryParse(_availabilityDelayDaysController.text.trim())
          : null,
      availabilityTime: _isTemplateMode && _availabilityTime != null
          ? '${_availabilityTime!.hour.toString().padLeft(2, '0')}:'
                '${_availabilityTime!.minute.toString().padLeft(2, '0')}'
          : null,
      submissionWindowHours: _isTemplateMode
          ? int.tryParse(_submissionWindowHoursController.text.trim())
          : null,
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    if (_isTemplateMode) {
      await _submitTemplate();
    } else {
      await _submitAdHoc();
    }
  }

  /// Phase 10A.4B: creates the shared Opportunity Quiz template. On
  /// success, replaces this screen with the real Quiz editor (now in
  /// template mode) so the Organization continues straight into adding
  /// questions — no separate Application/status side effect exists here at
  /// all (no candidate has been advanced to anything yet).
  Future<void> _submitTemplate() async {
    final provider = context.read<OrganizationQuizProvider>();
    final success = await provider.createOrUpdateSettings(_input);
    if (!mounted) return;

    if (!success) {
      _formKey.currentState?.validate();
      return;
    }

    context.pushReplacement(
      AppRoutes.organizationOpportunityQuiz(widget.opportunityId!),
    );
  }

  Future<void> _submitAdHoc() async {
    if (_conflictDetected) return;
    final provider = context.read<OrganizationAssessmentProvider>();

    final success = await provider.createAssessment(
      applicationId: widget.applicationId!,
      type: 'quiz',
      quizInput: _input,
    );
    if (!mounted) return;

    if (!success) {
      // Re-run validation so any backend field errors surface inline
      // immediately, without waiting for the next field interaction.
      _formKey.currentState?.validate();

      if (_isDuplicateConflict(provider)) {
        setState(() => _conflictDetected = true);
        provider.loadForApplication(
          widget.applicationId!,
          forceRefresh: true,
        );
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
      // The Assessment was still created successfully — only the response
      // didn't carry the application back. Don't lose the success; make
      // sure the details screen picks up the status change on its own.
      applicationsProvider.loadApplicationDetails(
        widget.applicationId!,
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
    final bool isLoading;
    final bool hasFieldErrors;
    final String? actionErrorMessage;
    if (_isTemplateMode) {
      final provider = context.watch<OrganizationQuizProvider>();
      isLoading = provider.isSavingSettings;
      hasFieldErrors = provider.fieldErrors.isNotEmpty;
      actionErrorMessage = provider.actionErrorMessage;
    } else {
      final provider = context.watch<OrganizationAssessmentProvider>();
      isLoading = provider.isCreatingFor(widget.applicationId!);
      hasFieldErrors = provider.fieldErrors.isNotEmpty;
      actionErrorMessage = provider.actionErrorMessage;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isTemplateMode ? 'Configure Quiz' : 'Create Quiz'),
      ),
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
                          actionErrorMessage != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        AppErrorView(
                          title: 'Something Went Wrong',
                          message: actionErrorMessage,
                          compact: true,
                        ),
                      ],
                    ],
                  ),
                ),
                if (_isTemplateMode) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SectionHeader(title: 'Candidate Availability'),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'How each candidate\'s own quiz window is '
                          'calculated once they are advanced to this quiz. '
                          'Every candidate gets their own dates, computed '
                          'at that moment.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: AppSpacing.inputSpacing),
                        AppTextField(
                          controller: _availabilityDelayDaysController,
                          label: 'Days After Assignment',
                          hint: 'e.g. 2',
                          keyboardType: TextInputType.number,
                          enabled: !isLoading,
                          textInputAction: TextInputAction.next,
                          validator: _availabilityDelayDaysValidator,
                        ),
                        const SizedBox(height: AppSpacing.inputSpacing),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _pickAvailabilityTime(isLoading),
                          child: AbsorbPointer(
                            child: AppTextField(
                              controller: _availabilityTimeDisplayController,
                              label: 'Opens At',
                              hint: 'Select a time',
                              readOnly: true,
                              enabled: !isLoading,
                              suffixIcon: const Icon(
                                Icons.access_time_outlined,
                              ),
                              validator: _availabilityTimeValidator,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.inputSpacing),
                        AppTextField(
                          controller: _submissionWindowHoursController,
                          label: 'Submission Window (Hours)',
                          hint: 'e.g. 48',
                          keyboardType: TextInputType.number,
                          enabled: !isLoading,
                          textInputAction: TextInputAction.done,
                          validator: _submissionWindowHoursValidator,
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionHeader(title: 'Question Display'),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'How the Student sees questions while taking the '
                        'quiz.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      RadioGroup<String>(
                        groupValue: _displayMode,
                        onChanged: (value) {
                          if (isLoading || value == null) return;
                          setState(() => _displayMode = value);
                        },
                        child: Column(
                          children: const [
                            RadioListTile<String>(
                              contentPadding: EdgeInsets.zero,
                              value: 'all',
                              title: Text('All questions on one page'),
                            ),
                            RadioListTile<String>(
                              contentPadding: EdgeInsets.zero,
                              value: 'single',
                              title: Text('One question at a time'),
                            ),
                            RadioListTile<String>(
                              contentPadding: EdgeInsets.zero,
                              value: 'paginated',
                              title: Text('Several questions per page'),
                            ),
                          ],
                        ),
                      ),
                      if (_displayMode == 'paginated') ...[
                        const SizedBox(height: AppSpacing.xs),
                        AppTextField(
                          controller: _questionsPerPageController,
                          label: 'Questions Per Page',
                          keyboardType: TextInputType.number,
                          enabled: !isLoading,
                          textInputAction: TextInputAction.done,
                          validator: _questionsPerPageValidator,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionHeader(title: 'Result Release'),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'When the graded result becomes visible to the '
                        'Student. The score is always calculated '
                        'immediately, whether or not it is visible yet.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      RadioGroup<String>(
                        groupValue: _resultReleaseMode,
                        onChanged: (value) {
                          if (isLoading || value == null) return;
                          setState(() => _resultReleaseMode = value);
                        },
                        child: Column(
                          children: const [
                            RadioListTile<String>(
                              contentPadding: EdgeInsets.zero,
                              value: 'immediate',
                              title: Text('Release immediately'),
                              subtitle: Text(
                                'The Student sees their result as soon as '
                                'they submit.',
                              ),
                            ),
                            RadioListTile<String>(
                              contentPadding: EdgeInsets.zero,
                              value: 'manual',
                              title: Text('Release manually'),
                              subtitle: Text(
                                'You choose when to release it, after '
                                'reviewing the result.',
                              ),
                            ),
                            RadioListTile<String>(
                              contentPadding: EdgeInsets.zero,
                              value: 'scheduled',
                              title: Text('Schedule a release time'),
                              subtitle: Text(
                                'The result is released automatically at a '
                                'date/time you choose.',
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_resultReleaseMode == 'scheduled') ...[
                        const SizedBox(height: AppSpacing.xs),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _pickReleaseDate(isLoading),
                          child: AbsorbPointer(
                            child: AppTextField(
                              controller: _releaseDateDisplayController,
                              label: 'Release Date',
                              hint: 'Select a date',
                              readOnly: true,
                              enabled: !isLoading,
                              suffixIcon: const Icon(
                                Icons.calendar_today_outlined,
                              ),
                              validator: _releaseDateValidator,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.inputSpacing),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _pickReleaseTime(isLoading),
                          child: AbsorbPointer(
                            child: AppTextField(
                              controller: _releaseTimeDisplayController,
                              label: 'Release Time',
                              hint: 'Select a time',
                              readOnly: true,
                              enabled: !isLoading,
                              suffixIcon: const Icon(Icons.access_time_outlined),
                              validator: _releaseTimeValidator,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                PrimaryButton(
                  label: _isTemplateMode ? 'Save Quiz' : 'Create Quiz',
                  isLoading: isLoading,
                  onPressed: _conflictDetected ? null : _submit,
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
