import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../providers/student_opportunities_provider.dart';
import 'opportunity_display.dart';

/// A modal bottom sheet for selecting the backend-documented public
/// opportunity filters. Local, unsaved selections live in this widget's own
/// state until "Apply Filters" commits them to the provider (and triggers a
/// refetch) — cancelling (dismissing the sheet) discards them.
///
/// Shared between [StudentOpportunitiesScreen] and the Student Home/Explore
/// screen, both of which browse the same [StudentOpportunitiesProvider] —
/// extracted here (originally private to the opportunities screen) so the
/// filter form exists in exactly one place rather than being duplicated.
///
/// Callers are responsible for wrapping this in `showModalBottomSheet` with
/// the relevant [StudentOpportunitiesProvider] available above it in the
/// tree (typically via `ChangeNotifierProvider.value`).
class OpportunityFilterSheet extends StatefulWidget {
  const OpportunityFilterSheet({super.key});

  @override
  State<OpportunityFilterSheet> createState() =>
      _OpportunityFilterSheetState();
}

class _OpportunityFilterSheetState extends State<OpportunityFilterSheet> {
  String? _opportunityType;
  String? _employmentType;
  String? _workMode;
  String? _experienceLevel;
  final _locationController = TextEditingController();
  final _fieldOfStudyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final provider = context.read<StudentOpportunitiesProvider>();
    _opportunityType = provider.opportunityType;
    _employmentType = provider.employmentType;
    _workMode = provider.workMode;
    _experienceLevel = provider.experienceLevel;
    _locationController.text = provider.location ?? '';
    _fieldOfStudyController.text = provider.fieldOfStudy ?? '';
  }

  @override
  void dispose() {
    _locationController.dispose();
    _fieldOfStudyController.dispose();
    super.dispose();
  }

  Widget _dropdown({
    required String label,
    required String? value,
    required Map<String, String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem<String>(value: null, child: Text('Any')),
        for (final entry in options.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: onChanged,
    );
  }

  void _apply() {
    context.read<StudentOpportunitiesProvider>().applyFilters(
      opportunityType: _opportunityType,
      employmentType: _employmentType,
      workMode: _workMode,
      experienceLevel: _experienceLevel,
      location: _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim(),
      fieldOfStudy: _fieldOfStudyController.text.trim().isEmpty
          ? null
          : _fieldOfStudyController.text.trim(),
    );
    Navigator.of(context).pop();
  }

  void _clear() {
    context.read<StudentOpportunitiesProvider>().clearFilters();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
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
            const SectionHeader(title: 'Filters'),
            const SizedBox(height: AppSpacing.xs),
            _dropdown(
              label: 'Opportunity Type',
              value: _opportunityType,
              options: opportunityTypeLabels,
              onChanged: (value) => setState(() => _opportunityType = value),
            ),
            const SizedBox(height: AppSpacing.inputSpacing),
            _dropdown(
              label: 'Employment Type',
              value: _employmentType,
              options: employmentTypeLabels,
              onChanged: (value) => setState(() => _employmentType = value),
            ),
            const SizedBox(height: AppSpacing.inputSpacing),
            _dropdown(
              label: 'Work Mode',
              value: _workMode,
              options: workModeLabels,
              onChanged: (value) => setState(() => _workMode = value),
            ),
            const SizedBox(height: AppSpacing.inputSpacing),
            _dropdown(
              label: 'Experience Level',
              value: _experienceLevel,
              options: experienceLevelLabels,
              onChanged: (value) => setState(() => _experienceLevel = value),
            ),
            const SizedBox(height: AppSpacing.inputSpacing),
            AppTextField(
              controller: _locationController,
              label: 'Location (optional)',
              hint: 'e.g. Amman',
            ),
            const SizedBox(height: AppSpacing.inputSpacing),
            AppTextField(
              controller: _fieldOfStudyController,
              label: 'Field of Study (optional)',
              hint: 'e.g. Computer Science',
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(label: 'Clear', onPressed: _clear),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: PrimaryButton(
                    label: 'Apply Filters',
                    onPressed: _apply,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens [OpportunityFilterSheet] as a modal bottom sheet, wiring up the
/// given [provider] as its ancestor. Shared helper so both call sites open
/// the sheet identically.
Future<void> showOpportunityFilterSheet(
  BuildContext context,
  StudentOpportunitiesProvider provider,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ChangeNotifierProvider.value(
      value: provider,
      child: const OpportunityFilterSheet(),
    ),
  );
}
