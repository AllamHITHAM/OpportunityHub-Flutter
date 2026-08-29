import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/opportunity_model.dart';
import '../../../providers/location_catalog_provider.dart';
import '../../../providers/organization_opportunities_provider.dart';
import '../../../routes/app_routes.dart';
import 'opportunity_display.dart';

/// Below this width, every paired field (Opportunity Type/Employment Type,
/// Experience Level/Education Level, Salary Min/Salary Max) stacks into a
/// single column instead of sitting side by side — matches the tablet
/// baseline used elsewhere in this app (e.g. the Opportunities list grid).
const _twoColumnBreakpoint = 600.0;

/// An intentional centered width for the form itself on desktop — narrower
/// than the Dashboard/Opportunities-list containers, since a linear form
/// reads worse stretched wide than a card grid does.
const _maxFormWidth = 800.0;

/// Create or edit an opportunity — the same fields, validation, and layout
/// apply either way, since the backend's create/update request rules are
/// identical (aside from a relaxed deadline rule on update).
///
/// `opportunityId == null` means create; otherwise this loads the existing
/// opportunity by ID (never via GoRouter `extra`) and pre-fills the form.
///
/// **UI Phase O3**: purely a presentation polish — every field, validator,
/// and submit behavior below is byte-for-byte the same as before. What
/// changed is layout only: Recruitment Process now sits with the rest of
/// Opportunity configuration, *before* the single Create/Save action at the
/// very bottom (previously it rendered in its own card *after* that
/// button — a real hierarchy bug); the form is grouped into five titled
/// sections instead of two, with related compact fields paired into
/// two-column rows on wide viewports; and the page gained the same
/// centered max-width treatment and theme toggle every other Organization
/// screen already has.
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

  /// The canonical Location Catalog ID (Phase O8.2) -- `null` means no
  /// location chosen (always valid for Remote; see [_validateLocationId]
  /// for On-site/Hybrid). Never free text.
  int? _selectedLocationId;

  /// Phase 10A.4B — required on this form (a real, explicit choice), even
  /// though the backend field itself stays optional for backward
  /// compatibility with every other caller — see
  /// `StoreOpportunityRequest`'s own doc comment (backend).
  String? _recruitmentProcess;

  /// Eligible Majors (Phase 8B-3.2) — a plain text list managed entirely
  /// client-side until submit; deduplicated case/whitespace-insensitively
  /// on add, mirroring (not duplicating) the backend's own normalization
  /// rule closely enough for this purely local UX check.
  final List<String> _eligibleMajors = [];

  /// Required Skills (Phase O8.2) -- real canonical `skills.id` keys,
  /// never free text; the value is `true` for Required, `false` for
  /// Preferred (mirrors `OpportunitySkill.is_required`).
  final Map<int, bool> _skillSelections = {};
  int? _skillToAdd;

  /// Opportunity Requirements Integrity Patch: both Eligible Majors and
  /// Required Skills are checked client-side before submit -- neither is a
  /// standard `TextFormField`, so this can't hook into `_formKey`'s own
  /// validation and is checked as an explicit extra gate in [_submit]
  /// instead. The backend enforces the same rule independently (see
  /// `StoreOpportunityRequest`) -- this is a UX convenience, never the
  /// only guard.
  String? _requirementsValidationError;

  /// Guards against re-filling the form (and stomping on in-progress edits)
  /// every time the provider notifies while editing.
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<LocationCatalogProvider>().load();
      context.read<OrganizationOpportunitiesProvider>().loadSkillCatalog();
    });
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
    _selectedLocationId = opportunity.locationId;
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
    _recruitmentProcess = opportunity.recruitmentProcess;
    _applicationDeadline = opportunity.applicationDeadline;
    if (_applicationDeadline != null) {
      _deadlineDisplayController.text = formatDate(_applicationDeadline!);
    }
    _eligibleMajors
      ..clear()
      ..addAll(opportunity.eligibleMajors);
    _skillSelections
      ..clear()
      ..addEntries(
        opportunity.opportunitySkills.map(
          (s) => MapEntry(s.skill.id, s.isRequired),
        ),
      );
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
      _requirementsValidationError = null;
    });
  }

  void _removeEligibleMajor(String major) {
    setState(() => _eligibleMajors.remove(major));
  }

  void _addSkill() {
    final skillId = _skillToAdd;
    if (skillId == null || _skillSelections.containsKey(skillId)) return;
    setState(() {
      _skillSelections[skillId] = true;
      _skillToAdd = null;
      _requirementsValidationError = null;
    });
  }

  void _removeSkill(int skillId) {
    setState(() => _skillSelections.remove(skillId));
  }

  void _toggleSkillRequired(int skillId) {
    setState(
      () => _skillSelections[skillId] = !(_skillSelections[skillId] ?? true),
    );
  }

  /// Required only for On-site/Hybrid — a Remote opportunity never needs a
  /// location, matching how location eligibility ignores Remote entirely
  /// on the backend (see `OpportunityEligibilityService::isLocationEligible()`).
  String? _validateLocationId() {
    if (_workMode == 'remote') return null;
    if (_selectedLocationId == null) {
      return 'Select a location for an on-site or hybrid opportunity';
    }
    return null;
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

    if (_eligibleMajors.isEmpty) {
      setState(
        () => _requirementsValidationError =
            'Select at least one eligible major.',
      );
      return;
    }
    if (_skillSelections.isEmpty) {
      setState(
        () => _requirementsValidationError =
            'Select at least one required skill.',
      );
      return;
    }
    setState(() => _requirementsValidationError = null);

    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
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
        locationId: _selectedLocationId,
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
        skills: _skillSelections,
        recruitmentProcess: _recruitmentProcess,
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
        locationId: _selectedLocationId,
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
        skills: _skillSelections,
        recruitmentProcess: _recruitmentProcess,
      );
    }

    if (!mounted) return;
    if (result == null) return;

    // Phase 10A.4B: a freshly-created Opportunity that requires a shared
    // Quiz isn't assessment-ready yet — go straight to configuring it
    // rather than leaving the Organization to discover that on their own
    // from Opportunity Details. Editing an existing Opportunity, or
    // creating one that doesn't need a Quiz, still lands on Details as
    // before.
    if (!widget.isEditing && result.recruitmentProcess == 'quiz') {
      context.go(AppRoutes.organizationOpportunityQuiz(result.id));
      return;
    }

    // Whether created or edited, land on the same details screen —
    // replacing this form in the stack rather than leaving it underneath.
    context.go(AppRoutes.organizationOpportunityDetails(result.id));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationOpportunitiesProvider>();
    final title = widget.isEditing ? 'Edit Opportunity' : 'Create Opportunity';

    if (widget.isEditing) {
      if (provider.isLoadingDetails && provider.selectedOpportunity == null) {
        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: const [ThemeToggleSurface()],
          ),
          body: const AppLoading(),
        );
      }
      if (provider.detailsErrorMessage != null &&
          provider.selectedOpportunity == null) {
        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: const [ThemeToggleSurface()],
          ),
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
      appBar: AppBar(title: Text(title), actions: const [ThemeToggleSurface()]),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;

            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: width >= _twoColumnBreakpoint
                    ? AppSpacing.xl
                    : AppSpacing.screenHorizontal,
                vertical: AppSpacing.md,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxFormWidth),
                  child: _FormEntrance(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildOpportunityDetailsSection(isLoading, width),
                          const SizedBox(height: AppSpacing.lg),
                          _buildCandidateRequirementsSection(isLoading, width),
                          const SizedBox(height: AppSpacing.lg),
                          _buildLocationAndCompensationSection(
                            isLoading,
                            width,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _buildRecruitmentProcessSection(isLoading),
                          const SizedBox(height: AppSpacing.lg),
                          _buildPublishingSection(isLoading),
                          if (provider.formErrorMessage != null) ...[
                            const SizedBox(height: AppSpacing.sm),
                            AppErrorView(
                              title: 'Something Went Wrong',
                              message: provider.formErrorMessage!,
                              compact: true,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                          PrimaryButton(
                            label: widget.isEditing
                                ? 'Save Changes'
                                : 'Create Opportunity',
                            isLoading: isLoading,
                            onPressed: () => _submit(provider),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// A. Opportunity Details — Title, Description, Opportunity Type/
  /// Employment Type (paired on wide viewports), Work Mode.
  Widget _buildOpportunityDetailsSection(bool isLoading, double width) {
    return AppCard(
      // UI Phase O3.1: a slightly stronger, more visible border than
      // AppCard's own default (AppColors.border) — real section boundaries
      // instead of a card that nearly disappears into the page in Light
      // mode. Reuses an existing token (AppColors.secondaryLight), not a
      // new color. Default elevation (a soft AppShadows.card) is
      // unchanged — no heavy shadow added.
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
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
          _ResponsiveFieldRow(
            width: width,
            left: DropdownButtonFormField<String>(
              initialValue: _opportunityType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Opportunity Type'),
              items: [
                for (final entry in opportunityTypeLabels.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: isLoading
                  ? null
                  : (value) => setState(() => _opportunityType = value),
              validator: (v) => _requiredValidator(v, 'Opportunity type'),
            ),
            right: DropdownButtonFormField<String>(
              initialValue: _employmentType,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Employment Type'),
              items: [
                for (final entry in employmentTypeLabels.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: isLoading
                  ? null
                  : (value) => setState(() => _employmentType = value),
              validator: (v) => _requiredValidator(v, 'Employment type'),
            ),
          ),
          const SizedBox(height: AppSpacing.inputSpacing),
          DropdownButtonFormField<String>(
            initialValue: _workMode,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Work Mode'),
            items: [
              for (final entry in workModeLabels.entries)
                DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: isLoading
                ? null
                : (value) => setState(() => _workMode = value),
            validator: (v) => _requiredValidator(v, 'Work mode'),
          ),
        ],
      ),
    );
  }

  /// B. Candidate Requirements — Experience Level/Education Level (paired),
  /// Eligible Majors, Required Skills. Field of Study is deliberately
  /// absent (Opportunity Academic Matching Cleanup) — it is deprecated,
  /// legacy, free-text metadata that never belonged in active product
  /// logic; Eligible Majors is the sole authoritative academic input.
  Widget _buildCandidateRequirementsSection(bool isLoading, double width) {
    return AppCard(
      // UI Phase O3.1: a slightly stronger, more visible border than
      // AppCard's own default (AppColors.border) — real section boundaries
      // instead of a card that nearly disappears into the page in Light
      // mode. Reuses an existing token (AppColors.secondaryLight), not a
      // new color. Default elevation (a soft AppShadows.card) is
      // unchanged — no heavy shadow added.
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Candidate Requirements'),
          const SizedBox(height: AppSpacing.xs),
          _ResponsiveFieldRow(
            width: width,
            left: DropdownButtonFormField<String>(
              initialValue: _experienceLevel,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Experience Level'),
              items: [
                for (final entry in experienceLevelLabels.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: isLoading
                  ? null
                  : (value) => setState(() => _experienceLevel = value),
              validator: (v) => _requiredValidator(v, 'Experience level'),
            ),
            right: DropdownButtonFormField<String>(
              initialValue: _educationLevel,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Education Level (optional)',
              ),
              items: [
                for (final entry in educationLevelLabels.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: isLoading
                  ? null
                  : (value) => setState(() => _educationLevel = value),
            ),
          ),
          const SizedBox(height: AppSpacing.inputSpacing),
          Text(
            'Eligible Majors *',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Students outside these majors will not appear when '
            'inviting for this opportunity. At least one major is '
            'required.',
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
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          _RequiredSkillsSection(
            selections: _skillSelections,
            skillToAdd: _skillToAdd,
            enabled: !isLoading,
            onAdd: _addSkill,
            onRemove: _removeSkill,
            onToggleRequired: _toggleSkillRequired,
            onSkillToAddChanged: (value) => setState(() => _skillToAdd = value),
          ),
          if (_requirementsValidationError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _requirementsValidationError!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }

  /// C. Location & Compensation — Location, Salary Min/Max (paired),
  /// Application Deadline, Positions Available.
  Widget _buildLocationAndCompensationSection(bool isLoading, double width) {
    return AppCard(
      // UI Phase O3.1: a slightly stronger, more visible border than
      // AppCard's own default (AppColors.border) — real section boundaries
      // instead of a card that nearly disappears into the page in Light
      // mode. Reuses an existing token (AppColors.secondaryLight), not a
      // new color. Default elevation (a soft AppShadows.card) is
      // unchanged — no heavy shadow added.
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Location & Compensation'),
          const SizedBox(height: AppSpacing.xs),
          _LocationField(
            selectedLocationId: _selectedLocationId,
            enabled: !isLoading,
            workMode: _workMode,
            onChanged: (value) => setState(() => _selectedLocationId = value),
            validator: (_) => _validateLocationId(),
          ),
          const SizedBox(height: AppSpacing.inputSpacing),
          _ResponsiveFieldRow(
            width: width,
            left: AppTextField(
              controller: _salaryMinController,
              label: 'Salary Min (optional)',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              enabled: !isLoading,
              textInputAction: TextInputAction.next,
              validator: _numericValidator,
            ),
            right: AppTextField(
              controller: _salaryMaxController,
              label: 'Salary Max (optional)',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              enabled: !isLoading,
              textInputAction: TextInputAction.next,
              validator: _salaryMaxValidator,
            ),
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
                suffixIcon: const Icon(Icons.calendar_today_outlined),
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
        ],
      ),
    );
  }

  /// D. Recruitment Process — moved here, clearly part of Opportunity
  /// configuration and *before* the single Create/Save action, fixing the
  /// old hierarchy bug where it rendered in its own card after the button.
  Widget _buildRecruitmentProcessSection(bool isLoading) {
    return AppCard(
      // UI Phase O3.1: a slightly stronger, more visible border than
      // AppCard's own default (AppColors.border) — real section boundaries
      // instead of a card that nearly disappears into the page in Light
      // mode. Reuses an existing token (AppColors.secondaryLight), not a
      // new color. Default elevation (a soft AppShadows.card) is
      // unchanged — no heavy shadow added.
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Recruitment Process'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'How shortlisted candidates are evaluated before a '
            'hiring decision.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          DropdownButtonFormField<String>(
            initialValue: _recruitmentProcess,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Recruitment Process'),
            items: [
              for (final entry in recruitmentProcessLabels.entries)
                DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: isLoading
                ? null
                : (value) => setState(() => _recruitmentProcess = value),
            validator: (v) => _requiredValidator(v, 'Recruitment process'),
          ),
          if (_recruitmentProcess != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              recruitmentProcessDescriptions[_recruitmentProcess]!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_recruitmentProcess == 'quiz') ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.isEditing
                  ? 'Manage the shared quiz from Opportunity Details.'
                  : 'The quiz can be configured after the opportunity is '
                        'created.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  /// E. Publishing — Status.
  Widget _buildPublishingSection(bool isLoading) {
    return AppCard(
      // UI Phase O3.1: a slightly stronger, more visible border than
      // AppCard's own default (AppColors.border) — real section boundaries
      // instead of a card that nearly disappears into the page in Light
      // mode. Reuses an existing token (AppColors.secondaryLight), not a
      // new color. Default elevation (a soft AppShadows.card) is
      // unchanged — no heavy shadow added.
      borderColor: AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Publishing'),
          const SizedBox(height: AppSpacing.xs),
          DropdownButtonFormField<String>(
            initialValue: _status,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Status'),
            items: [
              for (final entry in statusLabels.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: isLoading
                ? null
                : (value) => setState(() => _status = value),
          ),
        ],
      ),
    );
  }
}

/// A single-select over the real canonical Location Catalog (Phase O8.2)
/// — never free text. Disabled (with a real explanation, not just a
/// greyed-out control) for a Remote opportunity, since location is never
/// relevant there — mirrors how location eligibility on Recommended
/// Candidates ignores Remote entirely.
class _LocationField extends StatelessWidget {
  const _LocationField({
    required this.selectedLocationId,
    required this.enabled,
    required this.workMode,
    required this.onChanged,
    required this.validator,
  });

  final int? selectedLocationId;
  final bool enabled;
  final String? workMode;
  final ValueChanged<int?> onChanged;
  final FormFieldValidator<int?> validator;

  @override
  Widget build(BuildContext context) {
    final isRemote = workMode == 'remote';
    final provider = context.watch<LocationCatalogProvider>();

    if (isRemote) {
      return Text(
        'Not applicable for a Remote opportunity.',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
      );
    }

    if (provider.isLoading && provider.locations.isEmpty) {
      return const AppLoading(compact: true);
    }

    if (provider.errorMessage != null && provider.locations.isEmpty) {
      return AppErrorView(
        message: provider.errorMessage!,
        compact: true,
        onRetry: () => provider.load(forceRefresh: true),
      );
    }

    return DropdownButtonFormField<int>(
      initialValue: selectedLocationId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Location'),
      items: [
        for (final location in provider.locations)
          DropdownMenuItem(
            value: location.id,
            child: Text(
              location.canonicalName,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: enabled ? onChanged : null,
      validator: validator,
    );
  }
}

/// Required Skills (Phase O8.2) — real canonical Skill Catalog IDs only,
/// each marked Required or Preferred (mirrors `OpportunitySkill.is_required`,
/// which `MatchingService` already weights differently — required skills
/// count double). Selected skills render as toggleable chips; tapping one
/// (not its delete `x`) flips Required/Preferred, matching how a Filter
/// chip's own selected state already reads as tappable elsewhere in this
/// app.
class _RequiredSkillsSection extends StatelessWidget {
  const _RequiredSkillsSection({
    required this.selections,
    required this.skillToAdd,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
    required this.onToggleRequired,
    required this.onSkillToAddChanged,
  });

  final Map<int, bool> selections;
  final int? skillToAdd;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final ValueChanged<int> onToggleRequired;
  final ValueChanged<int?> onSkillToAddChanged;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationOpportunitiesProvider>();
    final catalog = {
      for (final skill in provider.catalogSkills) skill.id: skill,
    };
    final available = provider.catalogSkills
        .where((skill) => !selections.containsKey(skill.id))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Required Skills *',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'At least one skill is required. Tap a selected skill to toggle '
          'Required/Preferred. Ranking on Recommended Candidates weighs '
          'Required skills more heavily.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        if (selections.isNotEmpty) ...[
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: [
              for (final entry in selections.entries)
                if (catalog[entry.key] != null)
                  InputChip(
                    label: Text(
                      '${catalog[entry.key]!.name} '
                      '(${entry.value ? 'Required' : 'Preferred'})',
                    ),
                    onPressed: enabled
                        ? () => onToggleRequired(entry.key)
                        : null,
                    onDeleted: enabled ? () => onRemove(entry.key) : null,
                  ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        if (provider.isLoadingCatalog && provider.catalogSkills.isEmpty)
          const AppLoading(compact: true)
        else if (provider.catalogErrorMessage != null &&
            provider.catalogSkills.isEmpty)
          AppErrorView(
            message: provider.catalogErrorMessage!,
            compact: true,
            onRetry: () => provider.loadSkillCatalog(forceRefresh: true),
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: skillToAdd,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Add a skill'),
                  items: [
                    for (final skill in available)
                      DropdownMenuItem(
                        value: skill.id,
                        child: Text(
                          skill.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: enabled ? onSkillToAddChanged : null,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                onPressed: enabled && skillToAdd != null ? onAdd : null,
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Add skill',
              ),
            ],
          ),
      ],
    );
  }
}

/// A subtle, one-time fade/slide entrance for the whole form — respects
/// reduced motion via [AppMotion.reduced] (a near-zero duration collapses
/// this to an instant appearance). Deliberately a single shared entrance
/// for the whole scrollable content rather than staggering each section
/// individually — enough to feel intentional without becoming a
/// distraction on a form the Organization may fill out repeatedly.
class _FormEntrance extends StatelessWidget {
  const _FormEntrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.reduced(context, AppMotion.slow);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: AppMotion.entrance,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 8),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Lays [left]/[right] side by side once [width] reaches
/// [_twoColumnBreakpoint], otherwise stacks them — the one shared technique
/// behind every "compact field pair" this form uses (Opportunity Type/
/// Employment Type, Experience Level/Education Level, Salary Min/Max).
/// Long fields (Description, Eligible Majors, Required Skills) never go
/// through this widget — they always stay full width regardless of screen
/// size.
class _ResponsiveFieldRow extends StatelessWidget {
  const _ResponsiveFieldRow({
    required this.width,
    required this.left,
    required this.right,
  });

  final double width;
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    if (width < _twoColumnBreakpoint) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          left,
          const SizedBox(height: AppSpacing.inputSpacing),
          right,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: right),
      ],
    );
  }
}
