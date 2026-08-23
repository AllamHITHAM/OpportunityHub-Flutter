import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../providers/student_profile_provider.dart';

/// A real, backend-confirmed edit form for the student's own profile
/// (`PUT /api/student/profile`) — university, major, graduation year,
/// phone, and bio, the only fields this endpoint accepts. No GPA, city,
/// availability, hours/week, or profile photo field exists on the backend
/// record's editable surface, so none are offered here.
class StudentProfileEditScreen extends StatefulWidget {
  const StudentProfileEditScreen({super.key});

  @override
  State<StudentProfileEditScreen> createState() =>
      _StudentProfileEditScreenState();
}

class _StudentProfileEditScreenState extends State<StudentProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _universityController;
  late final TextEditingController _majorController;
  late final TextEditingController _phoneController;
  late final TextEditingController _bioController;
  int? _graduationYear;

  bool _justSaved = false;

  static const _phoneMaxLength = 20;
  static const _bioMaxLength = 2000;

  @override
  void initState() {
    super.initState();
    final profile = context.read<StudentProfileProvider>().profile;
    _universityController = TextEditingController(text: profile?.university);
    _majorController = TextEditingController(text: profile?.major);
    _phoneController = TextEditingController(text: profile?.phone);
    _bioController = TextEditingController(text: profile?.bio);
    _graduationYear = profile?.graduationYear;
  }

  @override
  void dispose() {
    _universityController.dispose();
    _majorController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  String? _backendFieldError(StudentProfileProvider provider, String field) {
    final messages = provider.fieldErrors[field];
    if (messages == null || messages.isEmpty) return null;
    return messages.first;
  }

  String? _validateUniversity(StudentProfileProvider provider, String? value) {
    final backendError = _backendFieldError(provider, 'university');
    if (backendError != null) return backendError;

    if ((value?.trim() ?? '').isEmpty) return 'University is required';
    return null;
  }

  String? _validateMajor(StudentProfileProvider provider, String? value) {
    final backendError = _backendFieldError(provider, 'major');
    if (backendError != null) return backendError;

    if ((value?.trim() ?? '').isEmpty) return 'Major is required';
    return null;
  }

  String? _validateGraduationYear(StudentProfileProvider provider) {
    final backendError = _backendFieldError(provider, 'graduation_year');
    if (backendError != null) return backendError;

    if (_graduationYear == null) return 'Expected graduation year is required';
    return null;
  }

  /// The previous year through the next eight years -- the same window
  /// `StudentProfileRegistrationScreen` offers -- widened to also include
  /// the profile's current value so an existing (possibly older) year
  /// never falls outside the dropdown's own item list.
  List<int> _graduationYearOptions() {
    final currentYear = DateTime.now().year;
    final options = List<int>.generate(10, (index) => currentYear - 1 + index);
    final existing = _graduationYear;
    if (existing != null && !options.contains(existing)) {
      options.add(existing);
      options.sort();
    }
    return options;
  }

  Future<void> _submit(StudentProfileProvider provider) async {
    FocusScope.of(context).unfocus();

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    final success = await provider.updateProfile(
      university: _universityController.text.trim(),
      major: _majorController.text.trim(),
      graduationYear: _graduationYear!,
      phone: _phoneController.text.trim().isEmpty
          ? null
          : _phoneController.text.trim(),
      bio: _bioController.text.trim().isEmpty ? null : _bioController.text.trim(),
    );
    if (!mounted) return;

    if (!success) {
      // Re-checks the form so any backend field error is surfaced
      // immediately, without waiting for the next field interaction. The
      // entered values are untouched -- nothing here clears a controller.
      _formKey.currentState?.validate();
      return;
    }

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
    final provider = context.watch<StudentProfileProvider>();
    final isSubmitting = provider.isSubmitting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: const [ThemeToggleButton(), SizedBox(width: AppSpacing.xs)],
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
              child: _FormEntrance(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SectionHeader(title: 'Academic Information'),
                            const SizedBox(height: AppSpacing.xs),
                            AppTextField(
                              controller: _universityController,
                              label: 'University',
                              hint: 'University name',
                              prefixIcon: Icons.account_balance_outlined,
                              textInputAction: TextInputAction.next,
                              enabled: !isSubmitting,
                              validator: (value) =>
                                  _validateUniversity(provider, value),
                            ),
                            const SizedBox(height: AppSpacing.inputSpacing),
                            AppTextField(
                              controller: _majorController,
                              label: 'Major',
                              hint: 'e.g. Computer Science',
                              prefixIcon: Icons.menu_book_outlined,
                              textInputAction: TextInputAction.next,
                              enabled: !isSubmitting,
                              validator: (value) => _validateMajor(provider, value),
                            ),
                            const SizedBox(height: AppSpacing.inputSpacing),
                            DropdownButtonFormField<int>(
                              initialValue: _graduationYear,
                              decoration: const InputDecoration(
                                labelText: 'Expected Graduation Year',
                                prefixIcon: Icon(Icons.event_outlined),
                              ),
                              items: [
                                for (final year in _graduationYearOptions())
                                  DropdownMenuItem(
                                    value: year,
                                    child: Text('$year'),
                                  ),
                              ],
                              onChanged: isSubmitting
                                  ? null
                                  : (value) =>
                                        setState(() => _graduationYear = value),
                              validator: (_) => _validateGraduationYear(provider),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SectionHeader(title: 'Contact & Bio'),
                            const SizedBox(height: AppSpacing.xs),
                            AppTextField(
                              controller: _phoneController,
                              label: 'Phone (optional)',
                              hint: 'e.g. 0791234567',
                              prefixIcon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              enabled: !isSubmitting,
                              maxLength: _phoneMaxLength,
                              validator: (_) =>
                                  _backendFieldError(provider, 'phone'),
                            ),
                            AppTextField(
                              controller: _bioController,
                              label: 'Bio (optional)',
                              hint: 'A short summary about yourself',
                              prefixIcon: Icons.person_outline,
                              textInputAction: TextInputAction.done,
                              enabled: !isSubmitting,
                              maxLines: 5,
                              minLines: 3,
                              maxLength: _bioMaxLength,
                              validator: (_) => _backendFieldError(provider, 'bio'),
                            ),
                          ],
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: AppMotion.reduced(context, AppMotion.fast),
                        child: provider.submitErrorMessage == null
                            ? const SizedBox(width: double.infinity)
                            : Padding(
                                key: ValueKey(provider.submitErrorMessage),
                                padding: const EdgeInsets.only(
                                  top: AppSpacing.xs,
                                ),
                                child: AppErrorView(
                                  title: 'Could Not Save Changes',
                                  message: provider.submitErrorMessage!,
                                  compact: true,
                                ),
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
                              icon: _justSaved ? Icons.check_circle_outline : null,
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
      ),
    );
  }
}

/// A one-shot fade + slide-up entrance for the whole form, matching the
/// rest of the app's entrance convention (see `AuthEntrance`) without
/// pulling in that widget's auth-specific per-child staggering -- this
/// screen has exactly one composed block (both cards + actions together).
class _FormEntrance extends StatefulWidget {
  const _FormEntrance({required this.child});

  final Widget child;

  @override
  State<_FormEntrance> createState() => _FormEntranceState();
}

class _FormEntranceState extends State<_FormEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    final reducedMotion = SchedulerBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    _controller = AnimationController(
      vsync: this,
      duration: reducedMotion ? const Duration(milliseconds: 1) : AppMotion.slow,
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: AppMotion.entrance);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}
