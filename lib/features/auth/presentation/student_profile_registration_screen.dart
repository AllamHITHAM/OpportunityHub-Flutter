import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/location_catalog_provider.dart';
import '../../../providers/student_profile_provider.dart';
import '../../../routes/app_routes.dart';
import '../../student/presentation/interested_in_field.dart';
import '../../student/presentation/work_location_fields.dart';
import 'registration_step_progress.dart';

/// Step 2 of student registration: collects student-profile information,
/// including optional Work Location Preferences (Student Location Profile
/// Patch), and submits it via `POST /api/student/profile`.
///
/// Location fields are deliberately kept out of the minimal Step 1 account
/// form and only ever offered here, in Profile Setup, and again later in
/// Edit Profile — never cluttering basic authentication.
///
/// Depends only on the authenticated session created by Step 1 — not on
/// anything passed through navigation. The route that builds this screen
/// (`/register/student/profile`) requires authentication and never needs
/// GoRouter `extra`, so this screen renders correctly even after a direct
/// URL visit or a browser refresh.
class StudentProfileRegistrationScreen extends StatefulWidget {
  const StudentProfileRegistrationScreen({super.key});

  @override
  State<StudentProfileRegistrationScreen> createState() =>
      _StudentProfileRegistrationScreenState();
}

class _StudentProfileRegistrationScreenState
    extends State<StudentProfileRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();

  final _universityController = TextEditingController();
  final _majorController = TextEditingController();

  int? _graduationYear;
  int? _currentLocationId;
  final Set<int> _selectedLocationIds = {};
  final Set<String> _interestedIn = {};
  String? _interestedInError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<LocationCatalogProvider>().load();
    });
  }

  @override
  void dispose() {
    _universityController.dispose();
    _majorController.dispose();
    super.dispose();
  }

  String? _validateUniversity(String? value) {
    final university = value?.trim() ?? '';
    if (university.isEmpty) return 'University is required';
    return null;
  }

  String? _validateMajor(String? value) {
    final major = value?.trim() ?? '';
    if (major.isEmpty) return 'Major is required';
    return null;
  }

  String? _validateGraduationYear(int? value) {
    if (value == null) return 'Expected graduation year is required';
    return null;
  }

  /// The previous year through the next eight years, generated from the
  /// current date rather than a hardcoded list.
  List<int> _graduationYearOptions() {
    final currentYear = DateTime.now().year;
    return List<int>.generate(10, (index) => currentYear - 1 + index);
  }

  Future<void> _finish(StudentProfileProvider profileProvider) async {
    // Dismiss the keyboard as soon as a submission attempt starts.
    FocusScope.of(context).unfocus();

    final isValid = _formKey.currentState?.validate() ?? false;
    setState(() {
      _interestedInError = _interestedIn.isEmpty
          ? 'Select at least one opportunity type you\'re interested in'
          : null;
    });
    if (!isValid || _interestedInError != null) return;

    final success = await profileProvider.createProfile(
      university: _universityController.text.trim(),
      major: _majorController.text.trim(),
      graduationYear: _graduationYear!,
      interestedIn: _interestedIn.toList(),
      currentLocationId: _currentLocationId,
      availableLocationIds: _selectedLocationIds.toList(),
    );

    if (!mounted) return;
    // On failure, errorMessage is already set and shown reactively below —
    // the entered values stay exactly as they are, so retrying only
    // resubmits the profile, never the account.
    if (!success) return;

    context.go(AppRoutes.studentHome);
  }

  /// The only safe way out of this screen (UI Phase 1.4). There is
  /// deliberately no "Back to Step 1" — the account already exists, Step 1
  /// can't be resubmitted, and `AppRouter` would immediately bounce an
  /// authenticated-but-incomplete student straight back here anyway (see
  /// `_redirectForStudent`'s `profileIncomplete` fallthrough), making a
  /// fake Back path pointless. Signing out is the one real exit: it does
  /// not delete the account or its data, and logging back in correctly
  /// resumes here via that same router logic.
  Future<void> _confirmSignOut() async {
    final authProvider = context.read<AuthProvider>();
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave setup?'),
        content: const Text(
          'Your account has been created, but your profile setup is not '
          'complete.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Continue Setup'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (shouldSignOut == true) {
      await authProvider.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileProvider = context.watch<StudentProfileProvider>();
    final textTheme = Theme.of(context).textTheme;
    final isLoading = profileProvider.isLoading;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _confirmSignOut,
          icon: const Icon(Icons.close),
          tooltip: 'Leave setup',
        ),
        actions: const [ThemeToggleButton()],
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: AuthAnimatedBackground()),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenHorizontal,
                vertical: AppSpacing.screenVertical,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Form(
                    key: _formKey,
                    child: AuthEntrance(
                      children: [
                        Text(
                          'Complete Your Student Profile',
                          textAlign: TextAlign.center,
                          style: textTheme.displaySmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Tell us about your education so we can personalise '
                          'opportunities for you.',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const RegistrationStepProgress(
                          progress: 1,
                          stepText: 'Step 2 of 2',
                          label: 'Student Information',
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SectionHeader(title: 'Student Information'),
                              const SizedBox(height: AppSpacing.xs),
                              AppTextField(
                                controller: _universityController,
                                label: 'University',
                                hint: 'University name',
                                prefixIcon: Icons.school_outlined,
                                textInputAction: TextInputAction.next,
                                enabled: !isLoading,
                                validator: _validateUniversity,
                              ),
                              const SizedBox(height: AppSpacing.inputSpacing),
                              AppTextField(
                                controller: _majorController,
                                label: 'Major',
                                hint: 'e.g. Computer Science',
                                prefixIcon: Icons.menu_book_outlined,
                                textInputAction: TextInputAction.done,
                                enabled: !isLoading,
                                validator: _validateMajor,
                                onFieldSubmitted: (_) =>
                                    _finish(profileProvider),
                              ),
                              const SizedBox(height: AppSpacing.inputSpacing),
                              DropdownButtonFormField<int>(
                                initialValue: _graduationYear,
                                decoration: const InputDecoration(
                                  labelText: 'Expected Graduation Year',
                                ),
                                items: [
                                  for (final year in _graduationYearOptions())
                                    DropdownMenuItem(
                                      value: year,
                                      child: Text('$year'),
                                    ),
                                ],
                                onChanged: isLoading
                                    ? null
                                    : (value) {
                                        setState(() => _graduationYear = value);
                                      },
                                validator: _validateGraduationYear,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SectionHeader(title: 'Career Interests'),
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                'Which types of opportunities are you '
                                'interested in? Select at least one — you '
                                'can choose more than one.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: AppColors.textSecondary),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              InterestedInField(
                                selected: _interestedIn,
                                enabled: !isLoading,
                                onToggle: (type) => setState(() {
                                  if (_interestedIn.contains(type)) {
                                    _interestedIn.remove(type);
                                  } else {
                                    _interestedIn.add(type);
                                  }
                                  if (_interestedIn.isNotEmpty) {
                                    _interestedInError = null;
                                  }
                                }),
                              ),
                              if (_interestedInError != null) ...[
                                const SizedBox(height: AppSpacing.xxs),
                                Text(
                                  _interestedInError!,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppColors.error),
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
                              const SectionHeader(
                                title: 'Work Location Preferences',
                              ),
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                'Choose the locations where you are '
                                'available to work. You can select more '
                                'than one.',
                                style: textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                'Remote opportunities are not restricted '
                                'by these locations.',
                                style: textTheme.bodySmall?.copyWith(
                                  color: AppColors.textMuted,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              CurrentLocationField(
                                selectedId: _currentLocationId,
                                enabled: !isLoading,
                                onChanged: (value) => setState(
                                  () => _currentLocationId = value,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.inputSpacing),
                              Text(
                                'Available Work Locations',
                                style: textTheme.labelLarge,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              AvailableLocationsField(
                                selectedIds: _selectedLocationIds,
                                enabled: !isLoading,
                                onToggle: (id) => setState(() {
                                  if (_selectedLocationIds.contains(id)) {
                                    _selectedLocationIds.remove(id);
                                  } else {
                                    _selectedLocationIds.add(id);
                                  }
                                }),
                              ),
                            ],
                          ),
                        ),
                        AnimatedSwitcher(
                          duration: AppMotion.reduced(context, AppMotion.fast),
                          child: profileProvider.errorMessage == null
                              ? const SizedBox(width: double.infinity)
                              : Padding(
                                  key: ValueKey(profileProvider.errorMessage),
                                  padding: const EdgeInsets.only(
                                    top: AppSpacing.xs,
                                  ),
                                  child: AppErrorView(
                                    title: 'Something Went Wrong',
                                    message: profileProvider.errorMessage!,
                                    compact: true,
                                  ),
                                ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        PrimaryButton(
                          label: 'Finish',
                          isLoading: isLoading,
                          onPressed: () => _finish(profileProvider),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
