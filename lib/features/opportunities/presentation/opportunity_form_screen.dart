import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/opportunity_model.dart';
import '../../../providers/organization_opportunities_provider.dart';
import '../../../routes/app_routes.dart';
import 'opportunity_display.dart';

/// Create or edit an opportunity — the same fields, validation, and layout
/// apply either way, since the backend's create/update request rules are
/// identical (aside from a relaxed deadline rule on update).
///
/// `opportunityId == null` means create; otherwise this loads the existing
/// opportunity by ID (never via GoRouter `extra`) and pre-fills the form.
class OpportunityFormScreen extends StatefulWidget {
  const OpportunityFormScreen({super.key, this.opportunityId});

  final int? opportunityId;

  bool get isEditing => opportunityId != null;

  @override
  State<OpportunityFormScreen> createState() => _OpportunityFormScreenState();
}

class _OpportunityFormScreenState extends State<OpportunityFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _fieldOfStudyController = TextEditingController();
  final _locationController = TextEditingController();
  final _salaryMinController = TextEditingController();
  final _salaryMaxController = TextEditingController();
  final _positionsAvailableController = TextEditingController();
  final _deadlineDisplayController = TextEditingController();
  final _eligibleMajorController = TextEditingController();

  String? _opportunityType;
  String? _employmentType;
  String? _workMode;
  String? _experienceLevel;
  String? _educationLevel;
  String? _status = 'open';
  DateTime? _applicationDeadline;

  /// Eligible Majors (Phase 8B-3.2) — a plain text list managed entirely
  /// client-side until submit; deduplicated case/whitespace-insensitively
  /// on add, mirroring (not duplicating) the backend's own normalization
  /// rule closely enough for this purely local UX check.
  final List<String> _eligibleMajors = [];

  /// Guards against re-filling the form (and stomping on in-progress edits)
  /// every time the provider notifies while editing.
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) {
      // Deferred to the post-frame callback — see
      // OrganizationOpportunitiesScreen.initState for why calling this
      // directly here would violate Flutter's build-phase constraints.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context
            .read<OrganizationOpportunitiesProvider>()
            .loadOpportunityDetails(widget.opportunityId!);
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _fieldOfStudyController.dispose();
    _locationController.dispose();
    _salaryMinController.dispose();
    _salaryMaxController.dispose();
    _positionsAvailableController.dispose();
    _deadlineDisplayController.dispose();
    _eligibleMajorController.dispose();
    super.dispose();
  }

  void _prefillFrom(OpportunityModel opportunity) {
    _titleController.text = opportunity.title;
    _descriptionController.text = opportunity.description;
    _fieldOfStudyController.text = opportunity.fieldOfStudy ?? '';
    _locationController.text = opportunity.location ?? '';
    _salaryMinController.text = opportunity.salaryMin?.toString() ?? '';
    _salaryMaxController.text = opportunity.salaryMax?.toString() ?? '';
    _positionsAvailableController.text = opportunity.positionsAvailable
        .toString();
    _opportunityType = opportunity.opportunityType;
    _employmentType = opportunity.employmentType;
    _workMode = opportunity.workMode;
    _experienceLevel = opportunity.experienceLevel;
    _educationLevel = opportunity.educationLevel;
    _status = opportunity.status;
    _applicationDeadline = opportunity.applicationDeadline;
    if (_applicationDeadline != null) {
      _deadlineDisplayController.text = formatDate(_applicationDeadline!);
    }
    _eligibleMajors
      ..clear()
      ..addAll(opportunity.eligibleMajors);
  }

  void _addEligibleMajor() {
    final value = _eligibleMajorController.text.trim();
    if (value.isEmpty) return;
    final alreadyAdded = _eligibleMajors.any(
      (existing) => existing.trim().toLowerCase() == value.toLowerCase(),
    );
    if (alreadyAdded) {
      _eligibleMajorController.clear();
      return;
    }
    setState(() {
      _eligibleMajors.add(value);
      _eligibleMajorController.clear();
    });
  }

  void _removeEligibleMajor(String major) {
    setState(() => _eligibleMajors.remove(major));
  }

  String? _requiredValidator(String? value, String fieldLabel) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldLabel is required';
    }
    return null;
  }

  String? _numericValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text);
    if (parsed == null || parsed < 0) {
      return 'Enter a valid non-negative number';
    }
    return null;
  }

  String? _salaryMaxValidator(String? value) {
    final basic = _numericValidator(value);
    if (basic != null) return basic;
    final text = value?.trim() ?? '';
    final minText = _salaryMinController.text.trim();
    if (text.isEmpty || minText.isEmpty) return null;
    final max = double.tryParse(text);
    final min = double.tryParse(minText);
    if (max != null && min != null && max < min) {
      return 'Must be greater than or equal to minimum salary';
    }
    return null;
  }

  String? _positionsAvailableValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = int.tryParse(text);
    if (parsed == null || parsed < 1) {
      return 'Enter a whole number of at least 1';
    }
    return null;
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // A new opportunity's deadline must be today or later (matching the
    // backend's create-only validation rule); an existing one may already
    // have a passed deadline, which editing must not force forward.
    final firstDate = widget.isEditing ? DateTime(today.year - 5) : today;
    final initialDate =
        _applicationDeadline != null &&
            !_applicationDeadline!.isBefore(firstDate)
        ? _applicationDeadline!
        : firstDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: DateTime(today.year + 10),
    );
    if (picked == null) return;
    setState(() {
      _applicationDeadline = picked;
      _deadlineDisplayController.text = formatDate(picked);
    });
  }

  Future<void> _submit(OrganizationOpportunitiesProvider provider) async {
    FocusScope.of(context).unfocus();

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    String? orNull(TextEditingController controller) {
      final value = controller.text.trim();
      return value.isEmpty ? null : value;
    }

    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final fieldOfStudy = orNull(_fieldOfStudyController);
    final location = orNull(_locationController);
    final salaryMinText = _salaryMinController.text.trim();
    final salaryMaxText = _salaryMaxController.text.trim();
    final positionsText = _positionsAvailableController.text.trim();

    final OpportunityModel? result;
    if (widget.isEditing) {
      result = await provider.updateOpportunity(
        id: widget.opportunityId!,
        title: title,
        description: description,
        opportunityType: _opportunityType!,
        employmentType: _employmentType!,
        workMode: _workMode!,
        experienceLevel: _experienceLevel!,
        educationLevel: _educationLevel,
        fieldOfStudy: fieldOfStudy,
        location: location,
        salaryMin: salaryMinText.isEmpty
            ? null
            : double.tryParse(salaryMinText),
        salaryMax: salaryMaxText.isEmpty
            ? null
            : double.tryParse(salaryMaxText),
        applicationDeadline: _applicationDeadline,
        positionsAvailable: positionsText.isEmpty
            ? null
            : int.tryParse(positionsText),
        status: _status,
        eligibleMajors: _eligibleMajors,
      );
    } else {
      result = await provider.createOpportunity(
        title: title,
        description: description,
        opportunityType: _opportunityType!,
        employmentType: _employmentType!,
        workMode: _workMode!,
        experienceLevel: _experienceLevel!,
        educationLevel: _educationLevel,
        fieldOfStudy: fieldOfStudy,
        location: location,
        salaryMin: salaryMinText.isEmpty
            ? null
            : double.tryParse(salaryMinText),
        salaryMax: salaryMaxText.isEmpty
            ? null
            : double.tryParse(salaryMaxText),
        applicationDeadline: _applicationDeadline,
        positionsAvailable: positionsText.isEmpty
            ? null
            : int.tryParse(positionsText),
        status: _status,
        eligibleMajors: _eligibleMajors,
      );
    }

    if (!mounted) return;
    if (result == null) return;

    // Whether created or edited, land on the same details screen —
    // replacing this form in the stack rather than leaving it underneath.
    context.go(AppRoutes.organizationOpportunityDetails(result.id));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationOpportunitiesProvider>();

    if (widget.isEditing) {
      if (provider.isLoadingDetails && provider.selectedOpportunity == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Edit Opportunity')),
          body: const AppLoading(),
        );
      }
      if (provider.detailsErrorMessage != null &&
          provider.selectedOpportunity == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Edit Opportunity')),
          body: AppErrorView(
            message: provider.detailsErrorMessage!,
            onRetry: () => provider.loadOpportunityDetails(
              widget.opportunityId!,
              forceRefresh: true,
            ),
          ),
        );
      }
      final opportunity = provider.selectedOpportunity;
      if (opportunity != null && !_prefilled) {
        _prefillFrom(opportunity);
        _prefilled = true;
      }
    }

    final isLoading = provider.isSubmitting;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEditing ? 'Edit Opportunity' : 'Create Opportunity',
        ),
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
                      const SectionHeader(title: 'Opportunity Details'),
                      const SizedBox(height: AppSpacing.xs),
                      AppTextField(
                        controller: _titleController,
                        label: 'Title',
                        hint: 'e.g. Software Engineer',
                        enabled: !isLoading,
                        textInputAction: TextInputAction.next,
                        validator: (v) => _requiredValidator(v, 'Title'),
                      ),
                      const SizedBox(height: AppSpacing.inputSpacing),
                      AppTextField(
                        controller: _descriptionController,
                        label: 'Description',
                        hint: 'Describe the role and responsibilities',
                        enabled: !isLoading,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        validator: (v) => _requiredValidator(v, 'Description'),
                      ),
                      const SizedBox(height: AppSpacing.inputSpacing),
                      DropdownButtonFormField<String>(
                        initialValue: _opportunityType,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Opportunity Type',
                        ),
                        items: [
                          for (final entry in opportunityTypeLabels.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(
                                entry.value,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: isLoading
                            ? null
                            : (value) =>
                                  setState(() => _opportunityType = value),
                        validator: (v) =>
                            _requiredValidator(v, 'Opportunity type'),
                      ),
                      const SizedBox(height: AppSpacing.inputSpacing),
                      DropdownButtonFormField<String>(
                        initialValue: _employmentType,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Employment Type',
                        ),
                        items: [
                          for (final entry in employmentTypeLabels.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(
                                entry.value,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: isLoading
                            ? null
                            : (value) =>
                                  setState(() => _employmentType = value),
                        validator: (v) =>
                            _requiredValidator(v, 'Employment type'),
                      ),
                      const SizedBox(height: AppSpacing.inputSpacing),
                      DropdownButtonFormField<String>(
                        initialValue: _workMode,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Work Mode',
                        ),
                        items: [
                          for (final entry in workModeLabels.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(
                                entry.value,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: isLoading
                            ? null
                            : (value) => setState(() => _workMode = value),
                        validator: (v) => _requiredValidator(v, 'Work mode'),
                      ),
                      const SizedBox(height: AppSpacing.inputSpacing),
                      DropdownButtonFormField<String>(
                        initialValue: _experienceLevel,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Experience Level',
                        ),
                        items: [
                          for (final entry in experienceLevelLabels.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(
                                entry.value,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: isLoading
                            ? null
                            : (value) =>
                                  setState(() => _experienceLevel = value),
                        validator: (v) =>
                            _requiredValidator(v, 'Experience level'),
                      ),
                      const SizedBox(height: AppSpacing.inputSpacing),
                      DropdownButtonFormField<String>(
                        initialValue: _educationLevel,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Education Level (optional)',
                        ),
                        items: [
                          for (final entry in educationLevelLabels.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(
                                entry.value,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: isLoading
                            ? null
                            : (value) =>
                                  setState(() => _educationLevel = value),
                      ),
                      const SizedBox(height: AppSpacing.inputSpacing),
                      AppTextField(
                        controller: _fieldOfStudyController,
                        label: 'Field of Study (optional)',
                        hint: 'e.g. Computer Science',
                        enabled: !isLoading,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: AppSpacing.inputSpacing),
                      Text(
                        'Eligible Majors (optional)',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        'Students outside these majors will not appear when '
                        'inviting for this opportunity. Leave empty to '
                        'accept any major.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      if (_eligibleMajors.isNotEmpty) ...[
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xxs,
                          children: [
                            for (final major in _eligibleMajors)
                              Chip(
                                label: Text(major),
                                onDeleted: isLoading
                                    ? null
                                    : () => _removeEligibleMajor(major),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: _eligibleMajorController,
                              label: 'Add a major',
                              hint: 'e.g. Computer Science',
                              enabled: !isLoading,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: isLoading
                                  ? null
                                  : (_) => _addEligibleMajor(),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          IconButton(
                            onPressed: isLoading ? null : _addEligibleMajor,
                            icon: const Icon(Icons.add_circle_outline),
                            tooltip: 'Add major',
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.inputSpacing),
                      AppTextField(
                        controller: _locationController,
                        label: 'Location (optional)',
                        hint: 'e.g. Amman, Jordan',
                        enabled: !isLoading,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: AppSpacing.inputSpacing),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: _salaryMinController,
                              label: 'Salary Min (optional)',
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              enabled: !isLoading,
                              textInputAction: TextInputAction.next,
                              validator: _numericValidator,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: AppTextField(
                              controller: _salaryMaxController,
                              label: 'Salary Max (optional)',
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              enabled: !isLoading,
                              textInputAction: TextInputAction.next,
                              validator: _salaryMaxValidator,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.inputSpacing),
                      GestureDetector(
                        onTap: isLoading ? null : _pickDeadline,
                        child: AbsorbPointer(
                          child: AppTextField(
                            controller: _deadlineDisplayController,
                            label: 'Application Deadline (optional)',
                            hint: 'Select a date',
                            readOnly: true,
                            enabled: !isLoading,
                            suffixIcon: const Icon(
                              Icons.calendar_today_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.inputSpacing),
                      AppTextField(
                        controller: _positionsAvailableController,
                        label: 'Positions Available (optional)',
                        hint: 'Defaults to 1',
                        keyboardType: TextInputType.number,
                        enabled: !isLoading,
                        textInputAction: TextInputAction.next,
                        validator: _positionsAvailableValidator,
                      ),
                      const SizedBox(height: AppSpacing.inputSpacing),
                      DropdownButtonFormField<String>(
                        initialValue: _status,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: [
                          for (final entry in statusLabels.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                        ],
                        onChanged: isLoading
                            ? null
                            : (value) => setState(() => _status = value),
                      ),
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
                        label: widget.isEditing ? 'Save Changes' : 'Create',
                        isLoading: isLoading,
                        onPressed: () => _submit(provider),
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
