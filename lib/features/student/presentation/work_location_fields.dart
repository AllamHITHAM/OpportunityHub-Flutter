import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/location_model.dart';
import '../../../providers/location_catalog_provider.dart';

/// Shared "type to search, tap Add to create" building block
/// (Recommendation Accuracy Patch) behind both [CurrentLocationField] and
/// [AvailableLocationsField] -- a Student is never limited to only the
/// preset catalog chips any more. Renders its own bounded suggestion list
/// inline (never an overlay/portal), so it stays simple to drive from a
/// widget test with plain `enterText`/`tap`/`pump`.
///
/// Matching a typed query against [LocationModel.matchesQuery] (canonical
/// name or any known alias, e.g. "نابلس" resolving to "Nablus") is purely
/// local UI filtering over the already-loaded catalog -- it never touches
/// eligibility, which stays entirely backend-only.
class _LocationSearchField extends StatefulWidget {
  const _LocationSearchField({
    required this.locations,
    required this.excludedIds,
    required this.enabled,
    required this.onSelect,
    required this.provider,
    this.labelText,
  });

  final List<LocationModel> locations;

  /// Catalog IDs never offered as a suggestion -- for
  /// [AvailableLocationsField], the ones already selected.
  final Set<int> excludedIds;

  final bool enabled;
  final ValueChanged<LocationModel> onSelect;
  final LocationCatalogProvider provider;
  final String? labelText;

  @override
  State<_LocationSearchField> createState() => _LocationSearchFieldState();
}

class _LocationSearchFieldState extends State<_LocationSearchField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<LocationModel> get _matches {
    if (_query.trim().isEmpty) return const [];

    return widget.locations
        .where((l) => !widget.excludedIds.contains(l.id))
        .where((l) => l.matchesQuery(_query))
        .toList();
  }

  bool get _hasExactMatch {
    final needle = _query.trim().toLowerCase();

    return widget.locations.any((l) => l.canonicalName.toLowerCase() == needle);
  }

  void _select(LocationModel location) {
    widget.onSelect(location);
    _controller.clear();
    setState(() => _query = '');
    _focusNode.unfocus();
  }

  Future<void> _addTyped() async {
    final typed = _query.trim();
    if (typed.isEmpty) return;

    final created = await widget.provider.addLocation(typed);
    if (!mounted || created == null) return;

    _select(created);
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    final showAddOption =
        widget.enabled && _query.trim().isNotEmpty && !_hasExactMatch;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _controller,
          focusNode: _focusNode,
          enabled: widget.enabled,
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: 'Type to search a location',
            prefixIcon: const Icon(Icons.search),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        if (_query.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.secondaryLight),
                borderRadius: BorderRadius.circular(8),
              ),
              child: widget.provider.isAddingLocation
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.sm),
                      child: AppLoading(compact: true),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xxs,
                      ),
                      children: [
                        for (final location in matches)
                          ListTile(
                            dense: true,
                            title: Text(location.canonicalName),
                            onTap: () => _select(location),
                          ),
                        if (showAddOption)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.add, size: 18),
                            title: Text('Add "${_query.trim()}"'),
                            onTap: _addTyped,
                          ),
                        if (matches.isEmpty && !showAddOption)
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xs,
                            ),
                            child: Text('No matching location'),
                          ),
                      ],
                    ),
            ),
          ),
          if (widget.provider.addLocationErrorMessage != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              widget.provider.addLocationErrorMessage!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.error),
            ),
          ],
        ],
      ],
    );
  }
}

/// A single-select, searchable-and-creatable field over the canonical
/// Location Catalog (Student Location Profile Patch, upgraded by the
/// Recommendation Accuracy Patch) for a Student's own "Current Location" --
/// optional, and deliberately distinct from [AvailableLocationsField]
/// below (where a Student lives vs. where they'd work). Shared between
/// Student Profile Setup (onboarding) and Edit Profile so the same
/// loading/error/search/add handling isn't duplicated per screen.
class CurrentLocationField extends StatelessWidget {
  const CurrentLocationField({
    super.key,
    required this.selectedId,
    required this.enabled,
    required this.onChanged,
  });

  final int? selectedId;
  final bool enabled;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LocationCatalogProvider>();

    if (provider.isLoading && provider.locations.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: AppLoading(compact: true),
      );
    }

    if (provider.errorMessage != null && provider.locations.isEmpty) {
      return AppErrorView(
        message: provider.errorMessage!,
        compact: true,
        onRetry: () => provider.load(forceRefresh: true),
      );
    }

    final selected = selectedId == null
        ? null
        : provider.locations.where((l) => l.id == selectedId).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selected != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              children: [
                const Icon(Icons.home_outlined, size: 18),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    selected.canonicalName,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                if (enabled)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Clear current location',
                    onPressed: () => onChanged(null),
                  ),
              ],
            ),
          ),
        _LocationSearchField(
          locations: provider.locations,
          excludedIds: const {},
          enabled: enabled,
          provider: provider,
          labelText: 'Current Location (optional)',
          onSelect: (location) => onChanged(location.id),
        ),
      ],
    );
  }
}

/// A multi-select, searchable-and-creatable field over the canonical
/// Location Catalog (Phase O8.2, upgraded by the Recommendation Accuracy
/// Patch) for a Student's own "Available Work Locations" -- never free
/// text, never comma-separated. Already-selected locations render as
/// removable chips; typing searches the rest of the catalog (by canonical
/// name or any known alias) and can add a genuinely new one when nothing
/// matches. Shared between Student Profile Setup (onboarding) and Edit
/// Profile.
class AvailableLocationsField extends StatelessWidget {
  const AvailableLocationsField({
    super.key,
    required this.selectedIds,
    required this.enabled,
    required this.onToggle,
  });

  final Set<int> selectedIds;
  final bool enabled;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LocationCatalogProvider>();

    if (provider.isLoading && provider.locations.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: AppLoading(compact: true),
      );
    }

    if (provider.errorMessage != null && provider.locations.isEmpty) {
      return AppErrorView(
        message: provider.errorMessage!,
        compact: true,
        onRetry: () => provider.load(forceRefresh: true),
      );
    }

    final selected = provider.locations
        .where((l) => selectedIds.contains(l.id))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final location in selected)
                  FilterChip(
                    label: Text(location.canonicalName),
                    selected: true,
                    onSelected: enabled ? (_) => onToggle(location.id) : null,
                  ),
              ],
            ),
          ),
        _LocationSearchField(
          locations: provider.locations,
          excludedIds: selectedIds,
          enabled: enabled,
          provider: provider,
          labelText: 'Add a work location',
          onSelect: (location) => onToggle(location.id),
        ),
      ],
    );
  }
}
