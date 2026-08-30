import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button_content.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../providers/auth_provider.dart';
import '../../opportunities/presentation/opportunity_display.dart';
import '../../../providers/student_cv_provider.dart';
import '../../../providers/student_education_verification_provider.dart';
import '../../../providers/student_profile_provider.dart';
import '../../../providers/student_skill_provider.dart';
import '../../../routes/app_routes.dart';
import '../../auth/presentation/email_verification_banner.dart';

/// Viewport width above which the Profile shows a two-column desktop
/// composition (main info + a sticky readiness/CV/account side panel).
/// Matches `StudentOpportunityDetailsScreen`'s own breakpoints for
/// consistency across the Student experience.
const _desktopBreakpoint = 900.0;
const _tabletBreakpoint = 600.0;

enum _ScreenTier { mobile, tablet, desktop }

_ScreenTier _tierFor(double width) {
  if (width >= _desktopBreakpoint) return _ScreenTier.desktop;
  if (width >= _tabletBreakpoint) return _ScreenTier.tablet;
  return _ScreenTier.mobile;
}

/// The Student's own profile — a premium candidate-profile presentation
/// over entirely real data (UI Phase 3/3.1): the authenticated [UserModel],
/// [StudentProfileModel] (university/major/graduation year/phone/bio --
/// every field the backend's `student_profile` record actually exposes,
/// except `profile_image`, which has no real upload endpoint anywhere in
/// this app), plus summaries of the student's real CVs, skills, and
/// education-verification state. No job title, match score, profile
/// views, followers, or endorsements exist anywhere in this app -- none
/// are fabricated here.
///
/// "Edit Profile" (in the hero) pushes [AppRoutes.studentProfileEdit], a
/// real form backed by `PUT /api/student/profile` -- see
/// `StudentProfileEditScreen`.
class StudentProfileScreen extends StatefulWidget {
  const StudentProfileScreen({super.key});

  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final bool _reducedMotion;

  @override
  void initState() {
    super.initState();
    // The student may land here straight from Discover's avatar button,
    // without ever having opened My CVs/Skills/Education Verification —
    // so their data isn't guaranteed loaded yet. Deferred to the
    // post-frame callback for the same reason as every other screen in
    // this app that does this (see StudentOpportunitiesScreen.initState):
    // calling these directly here would violate Flutter's build-phase
    // constraints. Each load is reentrancy-safe and cheap if already
    // loaded, so this is harmless if the student *did* visit one first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StudentCvProvider>().loadCvs();
      context.read<StudentSkillProvider>().load();
      context.read<StudentEducationVerificationProvider>().load();
    });

    _reducedMotion = SchedulerBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    _entranceController = AnimationController(
      vsync: this,
      duration: _reducedMotion
          ? const Duration(milliseconds: 1)
          : const Duration(milliseconds: 700),
    )..forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tier = _tierFor(MediaQuery.sizeOf(context).width);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: const [ThemeToggleButton(), SizedBox(width: AppSpacing.xs)],
      ),
      body: SafeArea(
        child: _ProfileContent(tier: tier, entranceController: _entranceController),
      ),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({required this.tier, required this.entranceController});

  final _ScreenTier tier;
  final AnimationController entranceController;

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final studentProfile = context.watch<StudentProfileProvider>().profile;
    final user = authProvider.user;
    final isDesktop = tier == _ScreenTier.desktop;

    final mainSections = <Widget>[
      _PersonalInfoSection(studentProfile: studentProfile),
      _CareerInterestsSection(studentProfile: studentProfile),
      _ContactSection(studentProfile: studentProfile),
      _WorkPreferencesSection(studentProfile: studentProfile),
      const SizedBox(height: AppSpacing.md),
      const _SkillsPreviewSection(),
      const SizedBox(height: AppSpacing.md),
      const _EducationVerificationSection(),
    ];

    final sideSections = <Widget>[
      _ReadinessPanel(user: user, studentProfile: studentProfile),
      const SizedBox(height: AppSpacing.md),
      const _CvSummaryCard(),
      const SizedBox(height: AppSpacing.md),
      const _AccountSection(),
    ];

    if (!isDesktop) {
      final horizontalPadding = tier == _ScreenTier.tablet
          ? AppSpacing.xl
          : AppSpacing.screenHorizontal;

      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ProfileHero(
              user: user,
              studentProfile: studentProfile,
              isWide: false,
              entranceController: entranceController,
            ),
            _Stagger(
              controller: entranceController,
              index: 1,
              count: 2,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  AppSpacing.md,
                  horizontalPadding,
                  AppSpacing.xxl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [...sideSections, const SizedBox(height: AppSpacing.md), ...mainSections],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Desktop: an independently-scrolling main column beside a side panel
    // that never scrolls with it -- the exact same layout mechanism
    // `StudentOpportunityDetailsScreen` uses for its own sticky side
    // panel, and for the same reason (`SizedBox.expand` gives the Row a
    // real, bounded height to divide between the two independent
    // `SingleChildScrollView`s).
    return SizedBox.expand(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 7,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ProfileHero(
                    user: user,
                    studentProfile: studentProfile,
                    isWide: true,
                    entranceController: entranceController,
                  ),
                  _Stagger(
                    controller: entranceController,
                    index: 1,
                    count: 2,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.xxl,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 840),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: mainSections,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 340,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.xxl,
              ),
              child: _Stagger(
                controller: entranceController,
                index: 1,
                count: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: sideSections,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fades and slides a section in as part of the staged entrance — [index]
/// of [count] total staggered sections, driven by the shared [controller]
/// rather than one controller per section. Mirrors
/// `StudentOpportunityDetailsScreen`'s own private `_Stagger` (kept
/// separate rather than shared, since neither is part of this app's
/// public design-system API yet).
class _Stagger extends StatelessWidget {
  const _Stagger({
    required this.controller,
    required this.index,
    required this.count,
    required this.child,
  });

  final AnimationController controller;
  final int index;
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = count <= 1 ? 0.0 : index / count;
    final end = count <= 1 ? 1.0 : ((index + 1.4) / count).clamp(start, 1.0);
    final curved = CurvedAnimation(
      parent: controller,
      curve: Interval(start, end, curve: AppMotion.entrance),
    );

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// The premium profile header — answers "who is this student, what do
/// they study, where, what stage" at a glance. A gradient in the app's own
/// primary-blue identity (the same dominant treatment
/// `StudentOpportunityDetailsScreen`'s Apply panel uses), [AppAvatar]
/// showing the student's uploaded profile photo when one exists (Student
/// Profile Photo phase) or its initials fallback otherwise, and only
/// real fields.
class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.user,
    required this.studentProfile,
    required this.isWide,
    required this.entranceController,
  });

  final dynamic user;
  final dynamic studentProfile;
  final bool isWide;
  final AnimationController entranceController;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final name = (user?.name as String?)?.trim();
    final displayName = name != null && name.isNotEmpty ? name : 'Student';
    final email = user?.email as String?;
    final major = studentProfile?.major as String?;
    final university = studentProfile?.university as String?;
    final graduationYear = studentProfile?.graduationYear as int?;
    final horizontalPadding = isWide ? AppSpacing.xl : AppSpacing.screenHorizontal;
    final nameSize = isWide ? 40.0 : 26.0;

    final academicLine = [major, university].nonNulls.join(' · ');

    final identityColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          displayName,
          style: textTheme.displayLarge?.copyWith(
            fontSize: nameSize,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (academicLine.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxs),
          AnimatedSwitcher(
            duration: AppMotion.reduced(context, AppMotion.normal),
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: Text(
              academicLine,
              key: ValueKey(academicLine),
              style: textTheme.titleMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.92),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (graduationYear != null)
              AnimatedSwitcher(
                duration: AppMotion.reduced(context, AppMotion.normal),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: _HeroMetaChip(
                  key: ValueKey(graduationYear),
                  icon: Icons.school_outlined,
                  label: 'Class of $graduationYear',
                ),
              ),
            if (email != null)
              _HeroMetaChip(icon: Icons.mail_outline_rounded, label: email),
          ],
        ),
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          AppSpacing.xl,
          horizontalPadding,
          AppSpacing.xl,
        ),
        child: _Stagger(
          controller: entranceController,
          index: 0,
          count: 2,
          child: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _HeroAvatar(
                      displayName: displayName,
                      photoUrl: studentProfile?.photoUrl as String?,
                      size: 84,
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: identityColumn),
                    const SizedBox(width: AppSpacing.lg),
                    const _EditProfileButton(compact: false),
                  ],
                )
              : Stack(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _HeroAvatar(
                          displayName: displayName,
                          photoUrl: studentProfile?.photoUrl as String?,
                          size: 64,
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(child: identityColumn),
                      ],
                    ),
                    const Positioned(
                      top: 0,
                      right: 0,
                      child: _EditProfileButton(compact: true),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _HeroAvatar extends StatelessWidget {
  const _HeroAvatar({
    required this.displayName,
    required this.size,
    this.photoUrl,
  });

  final String displayName;
  final double size;

  /// Student Profile Photo: the student's own uploaded photo, if any --
  /// `null` keeps the existing initials fallback rendering exactly as
  /// before this phase.
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        boxShadow: AppShadows.card,
      ),
      child: AppAvatar(
        imageUrl: photoUrl,
        name: displayName,
        size: size,
        backgroundColor: AppColors.primaryContainer,
        foregroundColor: AppColors.primaryDark,
      ),
    );
  }
}

/// The premium hero's real, working entry point into
/// `StudentProfileEditScreen` (`PUT /api/student/profile`) -- a translucent
/// pill (with label) on wide layouts where the hero has room to spare, or
/// a compact circular icon button on narrow ones, both hover/press-
/// responsive via [ButtonInteractionSurface].
class _EditProfileButton extends StatelessWidget {
  const _EditProfileButton({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    void onTap() => context.push(AppRoutes.studentProfileEdit);

    if (compact) {
      return ButtonInteractionSurface(
        child: Material(
          color: Colors.white.withValues(alpha: 0.16),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(Icons.edit_outlined, size: 20, color: Colors.white),
            ),
          ),
        ),
      );
    }

    return ButtonInteractionSurface(
      child: Material(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: AppRadius.pillRadius,
        child: InkWell(
          borderRadius: AppRadius.pillRadius,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              borderRadius: AppRadius.pillRadius,
              border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit_outlined, size: 18, color: Colors.white),
                SizedBox(width: AppSpacing.xs),
                Text(
                  'Edit Profile',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroMetaChip extends StatelessWidget {
  const _HeroMetaChip({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: AppRadius.pillRadius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single truthful readiness signal — never a fabricated percentage (no
/// such rule exists anywhere in this app's provider/backend contract).
class _ReadinessItem {
  const _ReadinessItem({
    required this.icon,
    required this.label,
    required this.state,
  });

  final IconData icon;
  final String label;
  final _ReadinessState state;
}

enum _ReadinessState { done, pending, attention }

/// A checklist of real account/profile states — email verification, CV/
/// skills/education-verification presence -- with an animated icon/color
/// per row instead of a fabricated completion percentage.
class _ReadinessPanel extends StatelessWidget {
  const _ReadinessPanel({required this.user, required this.studentProfile});

  final dynamic user;
  final dynamic studentProfile;

  @override
  Widget build(BuildContext context) {
    final cvProvider = context.watch<StudentCvProvider>();
    final skillProvider = context.watch<StudentSkillProvider>();
    final verificationProvider = context
        .watch<StudentEducationVerificationProvider>();
    final verification = verificationProvider.verification;

    final items = [
      _ReadinessItem(
        icon: Icons.mark_email_read_outlined,
        label: 'Email verified',
        state: (user?.emailVerified as bool? ?? false)
            ? _ReadinessState.done
            : _ReadinessState.attention,
      ),
      _ReadinessItem(
        icon: Icons.badge_outlined,
        label: 'Profile completed',
        state: studentProfile != null
            ? _ReadinessState.done
            : _ReadinessState.attention,
      ),
      _ReadinessItem(
        icon: Icons.description_outlined,
        label: 'CV uploaded',
        state: cvProvider.cvs.isNotEmpty
            ? _ReadinessState.done
            : _ReadinessState.attention,
      ),
      _ReadinessItem(
        icon: Icons.psychology_outlined,
        label: 'Skills added',
        state: skillProvider.skills.isNotEmpty
            ? _ReadinessState.done
            : _ReadinessState.pending,
      ),
      _ReadinessItem(
        icon: Icons.pin_drop_outlined,
        label: 'Work locations added',
        state: (studentProfile?.availableLocations as List?)?.isNotEmpty ?? false
            ? _ReadinessState.done
            : _ReadinessState.pending,
      ),
      _ReadinessItem(
        icon: Icons.verified_outlined,
        label: 'Education verification',
        state: verification == null
            ? _ReadinessState.pending
            : verification.isVerified
            ? _ReadinessState.done
            : verification.isPending
            ? _ReadinessState.pending
            : _ReadinessState.attention,
      ),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Profile Readiness'),
          const SizedBox(height: AppSpacing.xs),
          for (final item in items) _ReadinessRow(item: item),
        ],
      ),
    );
  }
}

class _ReadinessRow extends StatelessWidget {
  const _ReadinessRow({required this.item});

  final _ReadinessItem item;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final (color, statusIcon) = switch (item.state) {
      _ReadinessState.done => (AppColors.success, Icons.check_circle_rounded),
      _ReadinessState.pending => (AppColors.textMuted, Icons.radio_button_unchecked),
      _ReadinessState.attention => (AppColors.warning, Icons.error_outline_rounded),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Icon(item.icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(item.label, style: textTheme.bodyMedium)),
          AnimatedSwitcher(
            duration: AppMotion.reduced(context, AppMotion.fast),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Icon(statusIcon, key: ValueKey(item.state), size: 20, color: color),
          ),
        ],
      ),
    );
  }
}

/// University / Major / Graduation Year — the only real
/// `StudentProfileModel` fields this app reads (no GPA, phone, or bio yet).
/// Renders nothing for a field that isn't set, rather than a blank/`N/A`
/// row.
class _PersonalInfoSection extends StatelessWidget {
  const _PersonalInfoSection({required this.studentProfile});

  final dynamic studentProfile;

  @override
  Widget build(BuildContext context) {
    final university = studentProfile?.university as String?;
    final major = studentProfile?.major as String?;
    final graduationYear = studentProfile?.graduationYear as int?;

    final facts = [
      if (university != null && university.trim().isNotEmpty)
        (Icons.account_balance_outlined, 'University', university),
      if (major != null && major.trim().isNotEmpty)
        (Icons.menu_book_outlined, 'Major', major),
      if (graduationYear != null)
        (Icons.event_outlined, 'Graduation Year', '$graduationYear'),
    ];

    if (facts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Academic Information', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 480 ? 2 : 1;
            const spacing = AppSpacing.sm;
            final tileWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final (icon, label, value) in facts)
                  SizedBox(
                    width: tileWidth,
                    child: _InfoTile(icon: icon, label: label, value: value),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _InfoTile extends StatefulWidget {
  const _InfoTile({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  State<_InfoTile> createState() => _InfoTileState();
}

class _InfoTileState extends State<_InfoTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppMotion.reduced(context, AppMotion.normal),
        curve: AppMotion.standard,
        transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: AppRadius.mediumRadius,
          border: Border.all(
            color: _hovered ? AppColors.primary.withValues(alpha: 0.4) : AppColors.border,
          ),
          boxShadow: _hovered ? AppShadows.card : const [],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: AppRadius.mediumRadius,
              ),
              child: Icon(widget.icon, size: 18, color: AppColors.primaryDark),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.label.toUpperCase(),
                    style: textTheme.labelSmall?.copyWith(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: AppMotion.reduced(context, AppMotion.normal),
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: Text(
                      widget.value,
                      key: ValueKey(widget.value),
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Interested In" — the canonical Opportunity Type(s) this Student wants
/// to be recommended for (Candidate Opportunity Preferences patch). Always
/// renders (mirrors [_WorkPreferencesSection]'s own "always show, even
/// when empty" convention) so the Student can see this preference exists
/// and is configurable via Edit Profile, rather than the section silently
/// vanishing for a profile from before this patch shipped.
class _CareerInterestsSection extends StatelessWidget {
  const _CareerInterestsSection({required this.studentProfile});

  final dynamic studentProfile;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final interestedIn =
        (studentProfile?.interestedIn as List<String>?) ?? const <String>[];

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Career Interests', style: textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'INTERESTED IN',
            style: textTheme.labelSmall?.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (interestedIn.isEmpty)
            Text(
              'Not added yet',
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            )
          else
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xxs,
              children: [
                for (final type in interestedIn)
                  StatusChip(
                    label: opportunityTypeLabels[type] ?? type,
                    type: AppStatusType.info,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Phone and bio -- real `StudentProfileModel` fields, now editable via
/// `StudentProfileEditScreen` (UI Phase 3.1). Kept as its own section
/// rather than folded into "Academic Information" since neither is an
/// academic fact; renders nothing at all when both are unset, never an
/// empty "Contact" card.
class _ContactSection extends StatelessWidget {
  const _ContactSection({required this.studentProfile});

  final dynamic studentProfile;

  @override
  Widget build(BuildContext context) {
    final phone = (studentProfile?.phone as String?)?.trim();
    final bio = (studentProfile?.bio as String?)?.trim();
    final hasPhone = phone != null && phone.isNotEmpty;
    final hasBio = bio != null && bio.isNotEmpty;

    if (!hasPhone && !hasBio) return const SizedBox.shrink();

    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Contact', style: textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          if (hasPhone)
            _InfoTile(icon: Icons.phone_outlined, label: 'Phone', value: phone),
          if (hasPhone && hasBio) const SizedBox(height: AppSpacing.sm),
          if (hasBio)
            AnimatedSwitcher(
              duration: AppMotion.reduced(context, AppMotion.normal),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: Container(
                key: ValueKey(bio),
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: AppRadius.mediumRadius,
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  bio,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Current Location + Available Work Locations (Student Location Profile
/// Patch) — deliberately two distinct facts, never conflated: a Student
/// may live in one city but be willing to work in several others. Unlike
/// [_ContactSection], this always renders (never disappears when both are
/// unset) — showing a truthful "not added yet" state is the point, so the
/// Student knows this data exists and can be configured via Edit Profile.
class _WorkPreferencesSection extends StatelessWidget {
  const _WorkPreferencesSection({required this.studentProfile});

  final dynamic studentProfile;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final currentLocationName =
        studentProfile?.currentLocation?.canonicalName as String?;
    final availableLocations =
        (studentProfile?.availableLocations as List?) ?? const [];

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Work Preferences', style: textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          _InfoTile(
            icon: Icons.home_outlined,
            label: 'Current Location',
            value: currentLocationName ?? 'Not specified',
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'AVAILABLE WORK LOCATIONS',
            style: textTheme.labelSmall?.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (availableLocations.isEmpty)
            Text(
              'Work locations not added',
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            )
          else
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xxs,
              children: [
                for (final location in availableLocations)
                  StatusChip(
                    label: location.canonicalName as String,
                    type: AppStatusType.info,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A compact CV summary/entry point — real count, real default CV title,
/// no duplicated CV management UI (that stays on the real My CVs screen).
class _CvSummaryCard extends StatelessWidget {
  const _CvSummaryCard();

  @override
  Widget build(BuildContext context) {
    final cvProvider = context.watch<StudentCvProvider>();
    final textTheme = Theme.of(context).textTheme;
    final count = cvProvider.cvs.length;
    final defaultCv = cvProvider.defaultCv;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'CV'),
          const SizedBox(height: AppSpacing.sm),
          if (cvProvider.isLoadingList && cvProvider.cvs.isEmpty)
            const AppSkeleton(height: 40)
          else if (count == 0)
            Text(
              'No CV uploaded yet.',
              style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            )
          else ...[
            Row(
              children: [
                Icon(Icons.description_rounded, size: 20, color: AppColors.primary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    '$count CV${count == 1 ? '' : 's'} on file',
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (defaultCv != null) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Default: ${defaultCv.title}',
                style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (defaultCv.createdByAi) ...[
                const SizedBox(height: AppSpacing.xxs),
                const StatusChip(
                  compact: true,
                  icon: Icons.auto_awesome_outlined,
                  label: 'AI-assisted',
                  type: AppStatusType.info,
                ),
              ],
            ],
          ],
          const SizedBox(height: AppSpacing.sm),
          SecondaryButton(
            label: count == 0 ? 'Add Your First CV' : 'View My CVs',
            onPressed: () => context.push(AppRoutes.studentCvs),
          ),
        ],
      ),
    );
  }
}

/// A compact skills preview — real skills only, each carrying its real
/// evidence source ("CV-supported" / "Self-declared") rather than an
/// invented endorsement or skill-match score.
class _SkillsPreviewSection extends StatelessWidget {
  const _SkillsPreviewSection();

  static const _previewCount = 6;

  @override
  Widget build(BuildContext context) {
    final skillProvider = context.watch<StudentSkillProvider>();
    final textTheme = Theme.of(context).textTheme;
    final skills = skillProvider.skills;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: AppRadius.largeRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Skills', style: textTheme.headlineSmall),
              ),
              if (skills.isNotEmpty)
                Text(
                  '${skills.length}',
                  style: textTheme.titleMedium?.copyWith(color: AppColors.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (skillProvider.isLoading && skills.isEmpty)
            const AppSkeleton(height: 32)
          else if (skills.isEmpty)
            Text(
              'No skills added yet.',
              style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            )
          else
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xxs,
              children: [
                for (final skill in skills.take(_previewCount))
                  StatusChip(
                    label: skill.skillName,
                    type: skill.isCvSupported
                        ? AppStatusType.info
                        : AppStatusType.neutral,
                    icon: skill.isCvSupported
                        ? Icons.auto_awesome_outlined
                        : null,
                  ),
                if (skills.length > _previewCount)
                  StatusChip(label: '+${skills.length - _previewCount} more'),
              ],
            ),
          const SizedBox(height: AppSpacing.md),
          SecondaryButton(
            label: 'View All Skills',
            onPressed: () => context.push(AppRoutes.studentSkills),
          ),
        ],
      ),
    );
  }
}

/// The education-verification status summary — the exact real
/// `not_submitted` / `pending` / `verified` / `rejected` states, phrased
/// as this app's own Admin-review model (never implying a direct
/// university/government check).
class _EducationVerificationSection extends StatelessWidget {
  const _EducationVerificationSection();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentEducationVerificationProvider>();
    final textTheme = Theme.of(context).textTheme;
    final verification = provider.verification;

    final (statusType, statusIcon, statusLabel, ctaLabel) = switch (verification) {
      null => (
        AppStatusType.neutral,
        Icons.school_outlined,
        'Not Submitted',
        'Submit Verification',
      ),
      final v when v.isPending => (
        AppStatusType.warning,
        Icons.hourglass_top_rounded,
        'Pending Review',
        'View Verification',
      ),
      final v when v.isVerified => (
        AppStatusType.success,
        Icons.verified_rounded,
        'Verified',
        'View Verification',
      ),
      final v when v.isRejected => (
        AppStatusType.error,
        Icons.cancel_outlined,
        'Rejected',
        'Resubmit Verification',
      ),
      _ => (
        AppStatusType.neutral,
        Icons.school_outlined,
        'Not Submitted',
        'Submit Verification',
      ),
    };

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Education Verification'),
          const SizedBox(height: AppSpacing.sm),
          if (provider.isLoading && verification == null)
            const AppSkeleton(height: 28)
          else ...[
            AnimatedSwitcher(
              duration: AppMotion.reduced(context, AppMotion.normal),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: StatusChip(
                key: ValueKey(statusLabel),
                type: statusType,
                icon: statusIcon,
                label: statusLabel,
              ),
            ),
            if (verification != null &&
                verification.institutionName != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                [
                  verification.institutionName,
                  if (verification.degreeOrProgram != null)
                    verification.degreeOrProgram,
                ].whereType<String>().join(' · '),
                style: textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ],
          const SizedBox(height: AppSpacing.sm),
          SecondaryButton(
            label: ctaLabel,
            onPressed: () => context.push(AppRoutes.studentEducationVerification),
          ),
        ],
      ),
    );
  }
}

/// Account-level trust + the one real destructive action (Logout), grouped
/// into a single intentional "Account" card rather than leaving Logout as
/// a large isolated button. Reuses the existing shared
/// [EmailVerificationBanner] rather than rebuilding its resend logic here
/// — it already renders nothing when the account is verified, so it sits
/// above the card only when it actually has something to say.
class _AccountSection extends StatelessWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EmailVerificationBanner(),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.xs,
                ),
                child: SectionHeader(title: 'Account'),
              ),
              const _LogoutRow(),
            ],
          ),
        ),
      ],
    );
  }
}

class _LogoutRow extends StatefulWidget {
  const _LogoutRow();

  @override
  State<_LogoutRow> createState() => _LogoutRowState();
}

class _LogoutRowState extends State<_LogoutRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final textTheme = Theme.of(context).textTheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: _hovered
            ? AppColors.error.withValues(alpha: 0.06)
            : Colors.transparent,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(AppRadius.medium),
        ),
        child: InkWell(
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(AppRadius.medium),
          ),
          onTap: authProvider.logout,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(Icons.logout, size: 20, color: AppColors.error),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Logout',
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
