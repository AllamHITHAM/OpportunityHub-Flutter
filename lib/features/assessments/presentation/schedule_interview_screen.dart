import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../providers/organization_applications_provider.dart';
import '../../../providers/organization_assessment_provider.dart';
import '../data/interview_create_input.dart';
import 'assessment_display.dart';

final _emailRegExp = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// The Interview detail form reached from
/// `ChooseAssessmentTypeSheet` — the second half of the "organization
/// chooses an assessment type" flow. Reached by application ID alone (a
/// route parameter, never GoRouter `extra`), matching every other
/// organization-application route in this app.
class ScheduleInterviewScreen extends StatefulWidget {
  const ScheduleInterviewScreen({super.key, required this.applicationId});

  final int applicationId;

  @override
  State<ScheduleInterviewScreen> createState() =>
      _ScheduleInterviewScreenState();
}

class _ScheduleInterviewScreenState extends State<ScheduleInterviewScreen> {
  final _formKey = GlobalKey<FormState>();

  final _durationController = TextEditingController(text: '60');
  final _meetingLinkController = TextEditingController();
  final _locationController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _interviewerNameController = TextEditingController();
  final _interviewerEmailController = TextEditingController();
  final _notesController = TextEditingController();
  final _dateDisplayController = TextEditingController();
  final _timeDisplayController = TextEditingController();

  String _interviewType = 'online';
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;

  /// Set once a 409 ("assessment already exists") response is received —
  /// permanently disables further submission for this form instance, so
  /// the organization can't blindly resubmit a conflict a targeted
  /// background refresh is already resolving.
  bool _conflictDetected = false;

  @override
  void initState() {
    super.initState();
    // A previous, unrelated failed attempt on this same provider instance
    // (from a form the organization opened earlier and navigated away
    // from) must never bleed into a freshly-opened form — see
    // ApplyBottomSheet's identical `_hasSubmitted`-adjacent reasoning.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<OrganizationAssessmentProvider>();
      provider.clearActionError();
      provider.clearFieldErrors();
    });
  }

  @override
  void dispose() {
    _durationController.dispose();
    _meetingLinkController.dispose();
    _locationController.dispose();
    _contactPhoneController.dispose();
    _interviewerNameController.dispose();
    _interviewerEmailController.dispose();
    _notesController.dispose();
    _dateDisplayController.dispose();
    _timeDisplayController.dispose();
    super.dispose();
  }

  DateTime? get _combinedScheduledAt {
    final date = _scheduledDate;
    final time = _scheduledTime;
    if (date == null || time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  /// No `isLoading` guard here deliberately: `fieldErrors` is already
  /// cleared to `{}` at the start of every `createAssessment` call (see
  /// the provider), so this naturally returns `null` while a request is
  /// genuinely in flight without needing a separate check — a check based
  /// on a captured `isLoading` snapshot would be stale by the time
  /// `_formKey.currentState?.validate()` re-runs immediately after the
  /// `await` in `_submit`, since that happens before the next build.
  String? _fieldError(String field) {
    final provider = context.read<OrganizationAssessmentProvider>();
    final messages =
        provider.fieldErrors['interview.$field'] ?? provider.fieldErrors[field];
    if (messages == null || messages.isEmpty) return null;
    return messages.first;
  }

  Future<void> _pickDate(bool isLoading) async {
    if (isLoading) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialDate =
        _scheduledDate != null && !_scheduledDate!.isBefore(today)
        ? _scheduledDate!
        : today;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: DateTime(today.year + 5),
    );
    if (picked == null) return;
    setState(() {
      _scheduledDate = picked;
      _dateDisplayController.text = formatDate(picked);
    });
  }

  Future<void> _pickTime(bool isLoading) async {
    if (isLoading) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: _scheduledTime ?? TimeOfDay.now(),
      // Input mode lets an organization type an exact time directly,
      // rather than dragging a dial — faster for picking a precise
      // interview time.
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (picked == null) return;
    setState(() {
      _scheduledTime = picked;
      _timeDisplayController.text = picked.format(context);
    });
  }

  String? _dateValidator(String? value) {
    if (_scheduledDate == null) return 'Scheduled date is required';
    return null;
  }

  String? _timeValidator(String? value) {
    if (_scheduledTime == null) return 'Scheduled time is required';
    final combined = _combinedScheduledAt;
    if (combined != null && !combined.isAfter(DateTime.now())) {
      return 'Scheduled date and time must be in the future';
    }
    return null;
  }

  String? _durationValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = int.tryParse(text);
    if (parsed == null || parsed < 1) {
      return 'Enter a whole number of at least 1';
    }
    return null;
  }

  String? _meetingLinkValidator(String? value) {
    final backendError = _fieldError('meeting_link');
    if (backendError != null) return backendError;
    if (_interviewType != 'online') return null;
    if (value == null || value.trim().isEmpty) {
      return 'Meeting link is required for online interviews';
    }
    if (value.trim().length > 2048) {
      return 'Meeting link must be 2048 characters or fewer';
    }
    return null;
  }

  String? _locationValidator(String? value) {
    final backendError = _fieldError('location');
    if (backendError != null) return backendError;
    if (_interviewType != 'onsite') return null;
    if (value == null || value.trim().isEmpty) {
      return 'Location is required for onsite interviews';
    }
    if (value.trim().length > 255) {
      return 'Location must be 255 characters or fewer';
    }
    return null;
  }

  String? _contactPhoneValidator(String? value) {
    final backendError = _fieldError('contact_phone');
    if (backendError != null) return backendError;
    if (_interviewType != 'phone') return null;
    if (value == null || value.trim().isEmpty) {
      return 'Contact phone number is required for phone interviews';
    }
    if (value.trim().length > 30) {
      return 'Contact phone number must be 30 characters or fewer';
    }
    return null;
  }

  String? _interviewerEmailValidator(String? value) {
    final backendError = _fieldError('interviewer_email');
    if (backendError != null) return backendError;
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    if (!_emailRegExp.hasMatch(text)) return 'Enter a valid email address';
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

    final scheduledAt = _combinedScheduledAt;
    if (scheduledAt == null) return;

    String? orNull(TextEditingController controller) {
      final value = controller.text.trim();
      return value.isEmpty ? null : value;
    }

    final input = InterviewCreateInput(
      interviewType: _interviewType,
      scheduledAt: scheduledAt,
      durationMinutes: int.tryParse(_durationController.text.trim()),
      meetingLink: _interviewType == 'online'
          ? orNull(_meetingLinkController)
          : null,
      location: _interviewType == 'onsite' ? orNull(_locationController) : null,
      contactPhone: _interviewType == 'phone'
          ? orNull(_contactPhoneController)
          : null,
      interviewerName: orNull(_interviewerNameController),
      interviewerEmail: orNull(_interviewerEmailController),
      notes: orNull(_notesController),
    );

    final success = await provider.createAssessment(
      applicationId: widget.applicationId,
      type: 'interview',
      interviewInput: input,
    );
    if (!mounted) return;

    if (!success) {
      // Re-run validation so any backend field errors surface inline
      // immediately, without waiting for the next field interaction.
      _formKey.currentState?.validate();

      if (_isDuplicateConflict(provider)) {
        setState(() => _conflictDetected = true);
        // Recover: refresh the real assessment in the background so the
        // details screen (and this screen's own read of it, if the
        // organization navigates back) reflects what actually exists.
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

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Assessment created successfully')),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationAssessmentProvider>();
    final isLoading = provider.isCreatingFor(widget.applicationId);
    final hasFieldErrors = provider.fieldErrors.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Schedule Interview')),
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
                      const SectionHeader(title: 'Interview Details'),
                      const SizedBox(height: AppSpacing.xs),
                      DropdownButtonFormField<String>(
                        initialValue: _interviewType,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Interview Type',
                        ),
                        items: [
                          for (final entry in interviewTypeLabels.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                        ],
                        onChanged: isLoading
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() {
                                  _interviewType = value;
                                  if (value != 'online') {
                                    _meetingLinkController.clear();
                                  }
                                  if (value != 'onsite') {
                                    _locationController.clear();
                                  }
                                  if (value != 'phone') {
                                    _contactPhoneController.clear();
                                  }
                                });
                              },
                      ),
                      const SizedBox(height: AppSpacing.inputSpacing),
                      GestureDetector(
                        key: const Key('scheduledDateField'),
                        onTap: () => _pickDate(isLoading),
                        child: AbsorbPointer(
                          child: AppTextField(
                            controller: _dateDisplayController,
                            label: 'Scheduled Date',
                            hint: 'Select a date',
                            readOnly: true,
                            enabled: !isLoading,
                            suffixIcon: const Icon(
                              Icons.calendar_today_outlined,
                            ),
                            validator: _dateValidator,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.inputSpacing),
                      GestureDetector(
                        key: const Key('scheduledTimeField'),
                        onTap: () => _pickTime(isLoading),
                        child: AbsorbPointer(
                          child: AppTextField(
                            controller: _timeDisplayController,
                            label: 'Scheduled Time',
                            hint: 'Select a time',
                            readOnly: true,
                            enabled: !isLoading,
                            suffixIcon: const Icon(Icons.access_time_outlined),
                            validator: _timeValidator,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.inputSpacing),
                      AppTextField(
                        controller: _durationController,
                        label: 'Duration Minutes',
                        keyboardType: TextInputType.number,
                        enabled: !isLoading,
                        textInputAction: TextInputAction.next,
                        validator: _durationValidator,
                      ),
                      if (_interviewType == 'online') ...[
                        const SizedBox(height: AppSpacing.inputSpacing),
                        AppTextField(
                          controller: _meetingLinkController,
                          label: 'Meeting Link',
                          hint: 'https://...',
                          keyboardType: TextInputType.url,
                          maxLength: 2048,
                          enabled: !isLoading,
                          textInputAction: TextInputAction.next,
                          validator: _meetingLinkValidator,
                        ),
                      ],
                      if (_interviewType == 'onsite') ...[
                        const SizedBox(height: AppSpacing.inputSpacing),
                        AppTextField(
                          controller: _locationController,
                          label: 'Location',
                          maxLength: 255,
                          enabled: !isLoading,
                          textInputAction: TextInputAction.next,
                          validator: _locationValidator,
                        ),
                      ],
                      if (_interviewType == 'phone') ...[
                        const SizedBox(height: AppSpacing.inputSpacing),
                        AppTextField(
                          controller: _contactPhoneController,
                          label: 'Contact Phone Number',
                          hint: '+1 555-0100',
                          keyboardType: TextInputType.phone,
                          maxLength: 30,
                          enabled: !isLoading,
                          textInputAction: TextInputAction.next,
                          validator: _contactPhoneValidator,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.inputSpacing),
                      AppTextField(
                        controller: _interviewerNameController,
                        label: 'Interviewer Name (optional)',
                        maxLength: 255,
                        enabled: !isLoading,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: AppSpacing.inputSpacing),
                      AppTextField(
                        controller: _interviewerEmailController,
                        label: 'Interviewer Email (optional)',
                        keyboardType: TextInputType.emailAddress,
                        maxLength: 255,
                        enabled: !isLoading,
                        textInputAction: TextInputAction.next,
                        validator: _interviewerEmailValidator,
                      ),
                      const SizedBox(height: AppSpacing.inputSpacing),
                      AppTextField(
                        controller: _notesController,
                        label: 'Notes (optional)',
                        maxLines: 4,
                        maxLength: 2000,
                        enabled: !isLoading,
                        textInputAction: TextInputAction.newline,
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
                        label: 'Schedule Interview',
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
