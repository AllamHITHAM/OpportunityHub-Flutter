import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../providers/location_catalog_provider.dart';
import '../../../providers/organization_profile_provider.dart';
import '../data/picked_image_file.dart';

const _organizationTypeOptions = {
  'company': 'Company',
  'university': 'University',
  'ngo': 'NGO',
  'training_center': 'Training Center',
  'government': 'Government',
  'other': 'Other',
};

/// A real, backend-confirmed edit form for the organization's own profile
/// (`PUT /api/organization/profile`, Organization Public Profile phase) —
/// name, type, industry, description, website, phone, and canonical
/// location, the only fields that endpoint accepts. The Company Logo
/// (Company Profile Polish phase) is a separate, self-contained action
/// (`_LogoSection`, below) hitting its own dedicated
/// `POST/DELETE /organization/profile/logo` endpoints immediately on
/// Save/Remove — it is never bundled into this form's own "Save Changes"
/// submit, matching the backend's own separate-endpoint shape.
class OrganizationProfileEditScreen extends StatefulWidget {
  const OrganizationProfileEditScreen({
    super.key,
    this.pickLogoImage = pickImageFileFromDevice,
  });

  /// Defaults to the real platform file picker
  /// ([pickImageFileFromDevice]) — overridable in tests, mirroring
  /// [EditPostSheet]'s own injectable-picker convention. Threaded down to
  /// [_LogoSection].
  final Future<PickedImageFile?> Function() pickLogoImage;

  @override
  State<OrganizationProfileEditScreen> createState() =>
      _OrganizationProfileEditScreenState();
}

class _OrganizationProfileEditScreenState
    extends State<OrganizationProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _industryController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _websiteController;
  late final TextEditingController _phoneController;
  String? _organizationType;
  int? _locationId;

  bool _justSaved = false;

  static const _descriptionMaxLength = 3000;

  @override
  void initState() {
    super.initState();
    final profile = context.read<OrganizationProfileProvider>().profile;
    _nameController = TextEditingController(text: profile?.organizationName);
    _industryController = TextEditingController(text: profile?.industry);
    _descriptionController = TextEditingController(text: profile?.description);
    _websiteController = TextEditingController(text: profile?.website);
    _phoneController = TextEditingController(text: profile?.phone);
    _organizationType = profile?.organizationType;
    _locationId = profile?.location?.id;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<LocationCatalogProvider>().load();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _industryController.dispose();
    _descriptionController.dispose();
    _websiteController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    if ((value?.trim() ?? '').isEmpty) return 'Company name is required';
    return null;
  }

  String? _validateWebsite(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return 'Enter a full URL, e.g. https://example.com';
    }
    return null;
  }

  Future<void> _submit(OrganizationProfileProvider provider) async {
    FocusScope.of(context).unfocus();

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid || _organizationType == null) {
      setState(() {});
      return;
    }

    final success = await provider.updateProfile(
      organizationName: _nameController.text.trim(),
      organizationType: _organizationType!,
      industry: _industryController.text.trim().isEmpty
          ? null
          : _industryController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      website: _websiteController.text.trim().isEmpty
          ? null
          : _websiteController.text.trim(),
      phone: _phoneController.text.trim().isEmpty
          ? null
          : _phoneController.text.trim(),
      locationId: _locationId,
    );
    if (!mounted) return;

    if (!success) return;

    final reducedMotion = SchedulerBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    setState(() => _justSaved = true);
    await Future<void>.delayed(
      reducedMotion ? Duration.zero : const Duration(milliseconds: 450),
    );
    if (!mounted) return;
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationProfileProvider>();
    final isSubmitting = provider.isUpdating;
    final locationProvider = context.watch<LocationCatalogProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Company Profile'),
        actions: const [
          ThemeToggleButton(),
          SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
            vertical: AppSpacing.screenVertical,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LogoSection(pickImage: widget.pickLogoImage),
                    const SizedBox(height: AppSpacing.md),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SectionHeader(title: 'Company Identity'),
                          const SizedBox(height: AppSpacing.xs),
                          AppTextField(
                            controller: _nameController,
                            label: 'Company Name',
                            hint: 'Your organization\'s name',
                            prefixIcon: Icons.apartment_outlined,
                            textInputAction: TextInputAction.next,
                            enabled: !isSubmitting,
                            validator: _validateName,
                          ),
                          const SizedBox(height: AppSpacing.inputSpacing),
                          DropdownButtonFormField<String>(
                            initialValue: _organizationType,
                            decoration: const InputDecoration(
                              labelText: 'Organization Type',
                              prefixIcon: Icon(Icons.category_outlined),
                            ),
                            items: [
                              for (final entry
                                  in _organizationTypeOptions.entries)
                                DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ),
                            ],
                            onChanged: isSubmitting
                                ? null
                                : (value) =>
                                      setState(() => _organizationType = value),
                            validator: (value) => value == null
                                ? 'Organization type is required'
                                : null,
                          ),
                          const SizedBox(height: AppSpacing.inputSpacing),
                          AppTextField(
                            controller: _industryController,
                            label: 'Industry (optional)',
                            hint: 'e.g. Software, Education, Healthcare',
                            prefixIcon: Icons.business_center_outlined,
                            textInputAction: TextInputAction.next,
                            enabled: !isSubmitting,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SectionHeader(title: 'About'),
                          const SizedBox(height: AppSpacing.xs),
                          AppTextField(
                            controller: _descriptionController,
                            label: 'Company Description (optional)',
                            hint: 'Tell candidates what your organization does',
                            textInputAction: TextInputAction.newline,
                            enabled: !isSubmitting,
                            maxLines: 6,
                            minLines: 3,
                            maxLength: _descriptionMaxLength,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SectionHeader(title: 'Contact & Location'),
                          const SizedBox(height: AppSpacing.xs),
                          AppTextField(
                            controller: _websiteController,
                            label: 'Website (optional)',
                            hint: 'https://example.com',
                            prefixIcon: Icons.link_outlined,
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.next,
                            enabled: !isSubmitting,
                            validator: _validateWebsite,
                          ),
                          const SizedBox(height: AppSpacing.inputSpacing),
                          AppTextField(
                            controller: _phoneController,
                            label: 'Phone (optional)',
                            hint: 'e.g. 0791234567',
                            prefixIcon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            enabled: !isSubmitting,
                            maxLength: 30,
                          ),
                          const SizedBox(height: AppSpacing.inputSpacing),
                          if (locationProvider.isLoading &&
                              locationProvider.locations.isEmpty)
                            const AppLoading(compact: true)
                          else if (locationProvider.errorMessage != null &&
                              locationProvider.locations.isEmpty)
                            AppErrorView(
                              message: locationProvider.errorMessage!,
                              compact: true,
                              onRetry: () =>
                                  locationProvider.load(forceRefresh: true),
                            )
                          else
                            DropdownButtonFormField<int>(
                              initialValue: _locationId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Location (optional)',
                                prefixIcon: Icon(Icons.place_outlined),
                              ),
                              items: [
                                const DropdownMenuItem<int>(
                                  value: null,
                                  child: Text('Not specified'),
                                ),
                                for (final location
                                    in locationProvider.locations)
                                  DropdownMenuItem(
                                    value: location.id,
                                    child: Text(
                                      location.canonicalName,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: isSubmitting
                                  ? null
                                  : (value) =>
                                        setState(() => _locationId = value),
                            ),
                        ],
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: AppMotion.reduced(context, AppMotion.fast),
                      child: provider.updateErrorMessage == null
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              key: ValueKey(provider.updateErrorMessage),
                              padding: const EdgeInsets.only(
                                top: AppSpacing.xs,
                              ),
                              child: AppErrorView(
                                title: 'Could Not Save Changes',
                                message: provider.updateErrorMessage!,
                                compact: true,
                              ),
                            ),
                    ),
                    if (_organizationType == null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          'Organization type is required',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.error),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: SecondaryButton(
                            label: 'Cancel',
                            onPressed: isSubmitting
                                ? null
                                : () => context.pop(),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          flex: 2,
                          child: PrimaryButton(
                            label: _justSaved ? 'Saved' : 'Save Changes',
                            icon: _justSaved
                                ? Icons.check_circle_outline
                                : null,
                            isLoading: isSubmitting,
                            onPressed: () => _submit(provider),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Company Logo — Choose Image → preview → Save (Company Profile Polish
/// phase). A self-contained action, separate from the surrounding form's
/// own "Save Changes" submit, hitting the dedicated
/// `POST/DELETE /organization/profile/logo` endpoints immediately. Keeps
/// the existing clean initials fallback (via [AppAvatar]) whenever no
/// logo is set — never a fabricated stock image.
class _LogoSection extends StatefulWidget {
  const _LogoSection({this.pickImage = pickImageFileFromDevice});

  /// Defaults to the real platform file picker
  /// ([pickImageFileFromDevice]) — overridable in tests, mirroring
  /// [EditPostSheet]'s own injectable-picker convention.
  final Future<PickedImageFile?> Function() pickImage;

  @override
  State<_LogoSection> createState() => _LogoSectionState();
}

class _LogoSectionState extends State<_LogoSection> {
  /// A freshly-picked logo not yet uploaded -- `null` until the user
  /// chooses one, and cleared again once a save/cancel resolves.
  PickedImageFile? _picked;

  Future<void> _choose() async {
    final picked = await widget.pickImage();
    if (!mounted || picked == null) return;
    setState(() => _picked = picked);
  }

  void _cancelPreview() {
    setState(() => _picked = null);
  }

  Future<void> _save(OrganizationProfileProvider provider) async {
    final picked = _picked;
    if (picked == null) return;

    final success = await provider.uploadLogo(picked);
    if (!mounted) return;

    if (success) {
      setState(() => _picked = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Company logo updated')));
    } else if (provider.logoErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.logoErrorMessage!)));
    }
  }

  Future<void> _remove(OrganizationProfileProvider provider) async {
    final success = await provider.removeLogo();
    if (!mounted) return;

    if (!success && provider.logoErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.logoErrorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrganizationProfileProvider>();
    final isBusy = provider.isUploadingLogo;
    final existingUrl = provider.profile?.logoUrl;
    final hasPreview = _picked != null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Company Logo'),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: hasPreview
                ? ClipOval(
                    child: Image.memory(
                      _picked!.bytes,
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                    ),
                  )
                : AppAvatar(
                    imageUrl: existingUrl,
                    name: provider.profile?.organizationName,
                    size: 96,
                    fallbackIcon: Icons.apartment_outlined,
                  ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (hasPreview)
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: 'Cancel',
                    onPressed: isBusy ? null : _cancelPreview,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: PrimaryButton(
                    label: 'Save Logo',
                    isLoading: isBusy,
                    onPressed: () => _save(provider),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: 'Choose Image',
                    icon: Icons.image_outlined,
                    onPressed: isBusy ? null : _choose,
                  ),
                ),
                if (existingUrl != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: SecondaryButton(
                      label: 'Remove',
                      icon: Icons.delete_outline_rounded,
                      isLoading: isBusy,
                      onPressed: () => _remove(provider),
                    ),
                  ),
                ],
              ],
            ),
          if (!hasPreview && provider.logoErrorMessage != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              provider.logoErrorMessage!,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }
}
