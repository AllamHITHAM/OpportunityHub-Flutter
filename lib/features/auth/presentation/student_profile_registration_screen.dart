import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_error_view.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/section_header.dart';
import '../../../providers/student_profile_provider.dart';
import '../../../routes/app_routes.dart';
import 'registration_step_progress.dart';

/// Step 2 of student registration: collects student-profile information
/// and submits it via `POST /api/student/profile`.
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
    if (!isValid) return;

    final success = await profileProvider.createProfile(
      university: _universityController.text.trim(),
      major: _majorController.text.trim(),
      graduationYear: _graduationYear!,
    );

    if (!mounted) return;
    // On failure, errorMessage is already set and shown reactively below —
    // the entered values stay exactly as they are, so retrying only
    // resubmits the profile, never the account.
    if (!success) return;

    context.go(AppRoutes.studentHome);
  }

  @override
  Widget build(BuildContext context) {
    final profileProvider = context.watch<StudentProfileProvider>();
    final textTheme = Theme.of(context).textTheme;
    final isLoading = profileProvider.isLoading;

    return Scaffold(
      // No back action: this screen is reached with `context.go` (nothing
      // to pop to), and there's nowhere safe to send an already
      // authenticated student back to — Step 1 is off-limits once signed
      // in.
      appBar: AppBar(),
      body: SafeArea(
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
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
                            onFieldSubmitted: (_) => _finish(profileProvider),
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
                          if (profileProvider.errorMessage != null) ...[
                            const SizedBox(height: AppSpacing.xs),
                            AppErrorView(
                              title: 'Something Went Wrong',
                              message: profileProvider.errorMessage!,
                              compact: true,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                          PrimaryButton(
                            label: 'Finish',
                            isLoading: isLoading,
                            onPressed: () => _finish(profileProvider),
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
        ),
      ),
    );
  }
}
