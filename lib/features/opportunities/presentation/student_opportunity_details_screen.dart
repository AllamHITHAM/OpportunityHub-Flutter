import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/major_eligibility.dart';
import '../../../core/widgets/app_button_content.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/opportunity_model.dart';
import '../../../models/organization_profile_model.dart';
import '../../../providers/student_applications_provider.dart';
import '../../../providers/student_cv_provider.dart';
import '../../../providers/student_opportunities_provider.dart';
import '../../../providers/student_profile_provider.dart';
import '../../../routes/app_routes.dart';
import '../../applications/presentation/apply_bottom_sheet.dart';
import 'opportunity_card_palette.dart';
import 'opportunity_display.dart';

/// Viewport width above which Opportunity Details shows a two-column
/// desktop layout (main content + a sticky Apply/organization side panel).
/// Matches `LoginScreen`'s own wide breakpoint for consistency.
const _desktopBreakpoint = 900.0;

/// Below this width, the Apply panel becomes a bottom sheet-style sticky
/// bar (thumb-reachable) instead of an in-flow block — phone-sized
/// viewports only. Between this and [_desktopBreakpoint] is the tablet
/// tier: single column, but Apply stays in the normal content flow rather
/// than pinned, so it never squeezes a desktop-style two-column layout
/// into a width that can't comfortably hold it.
const _tabletBreakpoint = 600.0;

enum _ScreenTier { mobile, tablet, desktop }

_ScreenTier _tierFor(double width) {
  if (width >= _desktopBreakpoint) return _ScreenTier.desktop;
  if (width >= _tabletBreakpoint) return _ScreenTier.tablet;
  return _ScreenTier.mobile;
}

/// Why Apply is currently blocked, purely derived from real data already
/// on [OpportunityModel] / the student's own profile -- never a new rule.
/// Checked in this priority order: a closed posting or a passed deadline
/// blocks regardless of major (the same way the backend would reject
/// either), then major eligibility (see [isMajorEligibleForOpportunity],
/// the existing client-side mirror of the backend rule already used by
/// the organization's Invite flow -- the backend remains the actual
/// authority; this only predicts what it would say).
enum _ApplyBlockedReason { none, closed, deadlinePassed, ineligibleMajor }

_ApplyBlockedReason _applyBlockedReasonFor(
  OpportunityModel opportunity,
  String? studentMajor,
) {
  if (opportunity.status == 'closed') return _ApplyBlockedReason.closed;
  if (deadlineUrgencyFor(opportunity.applicationDeadline) ==
      DeadlineUrgency.passed) {
    return _ApplyBlockedReason.deadlinePassed;
  }
  if (!isMajorEligibleForOpportunity(studentMajor, opportunity)) {
    return _ApplyBlockedReason.ineligibleMajor;
  }
  return _ApplyBlockedReason.none;
}

/// Opportunity details for students. Reached by ID alone (a route
/// parameter, never GoRouter `extra`), so a direct URL visit or a browser
/// refresh renders correctly instead of crashing.
///
/// The only student action here is Apply — no save/quiz/interview controls
/// belong here yet.
class StudentOpportunityDetailsScreen extends StatefulWidget {
  const StudentOpportunityDetailsScreen({
    super.key,
    required this.opportunityId,
  });

  final int opportunityId;

  @override
  State<StudentOpportunityDetailsScreen> createState() =>
      _StudentOpportunityDetailsScreenState();
}

class _StudentOpportunityDetailsScreenState
    extends State<StudentOpportunityDetailsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final bool _reducedMotion;
  bool _hasPlayedEntrance = false;

  @override
  void initState() {
    super.initState();
    // Deferred to the post-frame callback — see
    // StudentOpportunitiesScreen.initState for why calling this directly
    // here would violate Flutter's build-phase constraints.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StudentOpportunitiesProvider>().loadOpportunityDetails(
        widget.opportunityId,
      );
      // Loaded proactively so "Already Applied" is accurate as soon as
      // this screen opens, and so CVs are ready by the time Apply is
      // tapped — both calls are reentrancy-safe and cheap if already
      // loaded.
      context.read<StudentApplicationsProvider>().loadApplications();
      context.read<StudentCvProvider>().loadCvs();
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
    );
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  /// Starts the staged entrance the first time real content is on screen —
  /// never replayed on a later rebuild (e.g. once Apply flips this screen
  /// to "Already Applied"), and never delays interactivity: every field of
  /// the already-built content is hit-testable throughout, only
  /// opacity/position animate.
  void _maybePlayEntrance() {
    if (_hasPlayedEntrance) return;
    _hasPlayedEntrance = true;
    _entranceController.forward();
  }

  Future<void> _openApplySheet(OpportunityModel opportunity) async {
    final applied = await showApplyBottomSheet(
      context,
      opportunityId: opportunity.id,
      opportunityTitle: opportunity.title,
    );
    if (applied && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Application submitted successfully')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentOpportunitiesProvider>();
    final opportunity = provider.selectedOpportunity;
    final isThisOne = opportunity?.id == widget.opportunityId;
    final tier = _tierFor(MediaQuery.sizeOf(context).width);

    final applied = opportunity != null
        ? context.select<StudentApplicationsProvider, bool>(
            (p) => p.hasAppliedTo(opportunity.id),
          )
        : false;

    // A student can only ever reach this screen with a complete profile
    // (the router already blocks anything else) — read-only here, this
    // screen never creates/edits a profile.
    final studentMajor = context.select<StudentProfileProvider, String?>(
      (p) => p.profile?.major,
    );
    final blockedReason = opportunity != null
        ? _applyBlockedReasonFor(opportunity, studentMajor)
        : _ApplyBlockedReason.none;

    final showStickyBar =
        opportunity != null && isThisOne && tier == _ScreenTier.mobile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Opportunity Details'),
        actions: const [ThemeToggleButton()],
      ),
      body: SafeArea(
        child: _buildBody(
          provider,
          opportunity,
          isThisOne,
          tier,
          applied,
          blockedReason,
        ),
      ),
      bottomNavigationBar: showStickyBar
          ? _StickyApplyBar(
              applied: applied,
              blockedReason: blockedReason,
              onApply: () => _openApplySheet(opportunity),
            )
          : null,
    );
  }

  Widget _buildBody(
    StudentOpportunitiesProvider provider,
    OpportunityModel? opportunity,
    bool isThisOne,
    _ScreenTier tier,
    bool applied,
    _ApplyBlockedReason blockedReason,
  ) {
    if (provider.isLoadingDetails && !isThisOne) {
      return const _DetailsSkeleton();
    }

    if (provider.detailsErrorMessage != null && !isThisOne) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
          child: AppErrorView(
            message: provider.detailsErrorMessage!,
            onRetry: () => provider.loadOpportunityDetails(
              widget.opportunityId,
              forceRefresh: true,
            ),
          ),
        ),
      );
    }

    if (opportunity == null || !isThisOne) {
      return const _DetailsSkeleton();
    }

    _maybePlayEntrance();

    return _DetailsContent(
      opportunity: opportunity,
      tier: tier,
      applied: applied,
      blockedReason: blockedReason,
      entranceController: _entranceController,
      onApply: () => _openApplySheet(opportunity),
    );
  }
}

/// The loaded-content layout — hero, then a two-column desktop split (main
/// content + sticky side panel), a single tablet column with the Apply
/// panel in-flow, or a single mobile column whose Apply CTA lives outside
/// this widget entirely, anchored in the screen's own
/// `Scaffold.bottomNavigationBar` ([_StickyApplyBar]) — depending on
/// [tier].
class _DetailsContent extends StatelessWidget {
  const _DetailsContent({
    required this.opportunity,
    required this.tier,
    required this.applied,
    required this.blockedReason,
    required this.entranceController,
    required this.onApply,
  });

  final OpportunityModel opportunity;
  final _ScreenTier tier;
  final bool applied;
  final _ApplyBlockedReason blockedReason;
  final AnimationController entranceController;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final tone = opportunityCardTone(opportunity.id);
    final isDesktop = tier == _ScreenTier.desktop;
    final eligibleMajors = opportunity.eligibleMajors;

    // On mobile, Apply itself lives in the sticky bottom bar (dense, no
    // room for an explanation) -- so the same status line
    // `_ApplyPanelCard` would otherwise show next to the button is
    // surfaced here instead, once, near the top of the content a student
    // is about to read. Tablet/desktop don't need this: their
    // `_ApplyPanelCard` (in-flow or side-panel) already carries it right
    // next to the button. `_ApplyStatusLine` itself decides whether
    // there's anything to say at all (nothing when applied, or when the
    // opportunity is unrestricted and open).
    final showMobileStatusLine =
        tier == _ScreenTier.mobile &&
        !applied &&
        (blockedReason != _ApplyBlockedReason.none ||
            eligibleMajors.isNotEmpty);

    final mainSections = [
      if (showMobileStatusLine) ...[
        _ApplyStatusLine(
          opportunity: opportunity,
          applied: applied,
          blockedReason: blockedReason,
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      _DescriptionSection(opportunity: opportunity),
      if (eligibleMajors.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        _EligibleMajorsSection(majors: eligibleMajors),
      ],
      if (opportunity.opportunitySkills.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        _SkillsSection(opportunity: opportunity),
      ],
      const SizedBox(height: AppSpacing.md),
      _FactsSection(
        opportunity: opportunity,
        entranceController: entranceController,
      ),
      if (tier == _ScreenTier.tablet) ...[
        const SizedBox(height: AppSpacing.md),
        _ApplyPanelCard(
          opportunity: opportunity,
          applied: applied,
          blockedReason: blockedReason,
          onApply: onApply,
        ),
      ],
      if (!isDesktop) ...[
        const SizedBox(height: AppSpacing.md),
        _OrganizationCard(organization: opportunity.organizationProfile),
      ],
      SizedBox(height: isDesktop ? AppSpacing.xl : AppSpacing.section),
    ];

    if (!isDesktop) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _BackToDiscoverBar(),
            _OpportunityHero(
              opportunity: opportunity,
              tone: tone,
              isWide: false,
              entranceController: entranceController,
            ),
            _Stagger(
              controller: entranceController,
              index: 1,
              count: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenHorizontal,
                  AppSpacing.md,
                  AppSpacing.screenHorizontal,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: mainSections,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Desktop: an independently-scrolling main column beside a side panel
    // that never scrolls with it, so the Apply CTA/organization identity
    // stay on screen the whole time the student is reading -- see this
    // file's own layout note below on why `SizedBox.expand` is needed for
    // that to work at all.
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
                  const _BackToDiscoverBar(isWide: true),
                  _OpportunityHero(
                    opportunity: opportunity,
                    tone: tone,
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
                        0,
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
                AppSpacing.xl,
              ),
              child: _Stagger(
                controller: entranceController,
                index: 1,
                count: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ApplyPanelCard(
                      opportunity: opportunity,
                      applied: applied,
                      blockedReason: blockedReason,
                      onApply: onApply,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _OrganizationCard(
                      organization: opportunity.organizationProfile,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small "Back to Discover" breadcrumb above the hero — purely a labeled
/// [Navigator.maybePop] (the exact same pop the AppBar's own default back
/// button already performs), so it changes nothing about how the route
/// stack or its guards behave.
class _BackToDiscoverBar extends StatefulWidget {
  const _BackToDiscoverBar({this.isWide = false});

  final bool isWide;

  @override
  State<_BackToDiscoverBar> createState() => _BackToDiscoverBarState();
}

class _BackToDiscoverBarState extends State<_BackToDiscoverBar> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.isWide ? AppSpacing.xl : AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.xs,
        0,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: TextButton.icon(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: AnimatedSlide(
              offset: _hovered ? const Offset(-0.15, 0) : Offset.zero,
              duration: AppMotion.reduced(context, AppMotion.fast),
              curve: AppMotion.standard,
              child: const Icon(Icons.arrow_back_rounded, size: 18),
            ),
            label: const Text('Back to Discover'),
          ),
        ),
      ),
    );
  }
}

/// Fades and slides a section in as part of the staged entrance — [index]
/// of [count] total staggered sections, driven by the shared
/// [controller] rather than one controller per section.
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

/// The rich header: a full-bleed band in the same deterministic
/// [OpportunityCardTone] the student's Explore card used, so the details
/// screen feels like a continuation of the card they tapped rather than a
/// disconnected page. No cover-image field exists on [OpportunityModel]
/// (same audit note as [OpportunityCard]), so the organization's identity
/// is [AppAvatar]'s initials fallback, never a fabricated logo/photo.
///
/// UI Phase 2.1: the title is now the strongest element on the page (an
/// explicit large size, well above anything in the shared `TextTheme`,
/// since nothing in that scale goes past 32px) with its own internal
/// entrance stagger — title, then organization identity, then the
/// metadata row each settle in slightly after the last, all still driven
/// by the single shared [entranceController] rather than a controller per
/// element.
class _OpportunityHero extends StatelessWidget {
  const _OpportunityHero({
    required this.opportunity,
    required this.tone,
    required this.isWide,
    required this.entranceController,
  });

  final OpportunityModel opportunity;
  final OpportunityCardTone tone;
  final bool isWide;
  final AnimationController entranceController;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final organization = opportunity.organizationProfile;
    final horizontalPadding = isWide
        ? AppSpacing.xl
        : AppSpacing.screenHorizontal;
    final titleSize = isWide ? 48.0 : 30.0;

    return ClipRect(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tone.background, tone.border],
          ),
        ),
        child: Stack(
          children: [
            // Layered decorative shapes -- soft, low-opacity, purely
            // ambient (never covering text, never intercepting taps).
            const Positioned.fill(child: _HeroDecoration()),
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                AppSpacing.xl,
                horizontalPadding,
                AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _HeroStagger(
                    controller: entranceController,
                    start: 0.0,
                    end: 0.55,
                    child: StatusChip(
                      type: AppStatusType.primary,
                      label:
                          opportunityTypeLabels[opportunity.opportunityType] ??
                          opportunity.opportunityType,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _HeroStagger(
                    controller: entranceController,
                    start: 0.1,
                    end: 0.65,
                    child: Text(
                      opportunity.title,
                      style: textTheme.displayLarge?.copyWith(
                        fontSize: titleSize,
                        fontWeight: FontWeight.w800,
                        height: 1.08,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _HeroStagger(
                    controller: entranceController,
                    start: 0.25,
                    end: 0.8,
                    // Organization Public Profile phase: tappable when a
                    // real organization is known -- navigates to its
                    // public Company Profile, the same destination
                    // `_OrganizationCard` further down the page links to.
                    // A plain `GestureDetector` (not `InkWell`) since this
                    // sits over a gradient hero, not a `Material` surface.
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: organization == null
                          ? null
                          : () => context.push(
                              AppRoutes.companyProfile(organization.id),
                            ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              shape: BoxShape.circle,
                              boxShadow: AppShadows.card,
                            ),
                            child: AppAvatar(
                              name: organization?.organizationName,
                              size: isWide ? 48 : 40,
                              fallbackIcon: Icons.apartment_outlined,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          if (organization != null)
                            Flexible(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      organization.organizationName,
                                      style: textTheme.titleMedium,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  // "Approved" is the organization's real,
                                  // literal backend `approvalStatus` (only
                                  // admin-approved organizations can publish
                                  // publicly) -- not a fabricated
                                  // "verified" claim, just labeled plainly.
                                  if (organization.approvalStatus == 'approved')
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: AppSpacing.xxs,
                                      ),
                                      child: Tooltip(
                                        message:
                                            'Approved organization on OpportunityHub',
                                        child: Icon(
                                          Icons.verified_rounded,
                                          size: 18,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (opportunity.location != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    _HeroStagger(
                      controller: entranceController,
                      start: 0.3,
                      end: 0.85,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                          Text(
                            opportunity.location!,
                            style: textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  _HeroStagger(
                    controller: entranceController,
                    start: 0.4,
                    end: 1.0,
                    child: Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xxs,
                      children: [
                        _HoverChip(
                          label:
                              employmentTypeLabels[opportunity
                                  .employmentType] ??
                              opportunity.employmentType,
                        ),
                        _HoverChip(
                          label:
                              workModeLabels[opportunity.workMode] ??
                              opportunity.workMode,
                        ),
                        _HoverChip(
                          label:
                              experienceLevelLabels[opportunity
                                  .experienceLevel] ??
                              opportunity.experienceLevel,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _HeroStagger(
                    controller: entranceController,
                    start: 0.4,
                    end: 1.0,
                    child: _DeadlineBadge(
                      deadline: opportunity.applicationDeadline,
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

/// Two large, softly blurred circles anchored to opposite corners of the
/// hero -- purely decorative, static (a one-shot ambient look rather than
/// a perpetual animation loop; see `AuthAnimatedBackground`'s own doc
/// comment on why this codebase avoids repeating decorative animations),
/// and low-opacity enough to never fight the text sitting on top.
class _HeroDecoration extends StatelessWidget {
  const _HeroDecoration();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -60,
            right: -40,
            child: _blob(220, AppColors.surface.withValues(alpha: 0.18)),
          ),
          Positioned(
            bottom: -80,
            left: -60,
            child: _blob(260, AppColors.textPrimary.withValues(alpha: 0.06)),
          ),
        ],
      ),
    );
  }

  Widget _blob(double diameter, Color color) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}

/// A finer-grained entrance than [_Stagger] for elements *inside* the
/// hero -- [start]/[end] are fractions of the same shared
/// [entranceController]'s already-allotted hero interval (see
/// `_DetailsContent`'s outer `_Stagger(index: 0, ...)`), so title, org
/// identity, and metadata settle in one after another within that single
/// window rather than all at once.
class _HeroStagger extends StatelessWidget {
  const _HeroStagger({
    required this.controller,
    required this.start,
    required this.end,
    required this.child,
  });

  final AnimationController controller;
  final double start;
  final double end;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: controller,
      curve: Interval(start, end, curve: AppMotion.entrance),
    );

    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// A [StatusChip] with a very subtle hover response (a hairline border
/// tint, no cursor change) -- these chips are informational, not tappable,
/// so hover feedback here is deliberately restrained enough not to imply
/// interactivity that isn't real.
class _HoverChip extends StatefulWidget {
  const _HoverChip({required this.label});

  final String label;

  @override
  State<_HoverChip> createState() => _HoverChipState();
}

class _HoverChipState extends State<_HoverChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.05 : 1.0,
        duration: AppMotion.reduced(context, AppMotion.fast),
        curve: AppMotion.standard,
        child: StatusChip(label: widget.label),
      ),
    );
  }
}

/// A real (never fabricated) urgency signal, purely a function of
/// [OpportunityModel.applicationDeadline] vs. now — see
/// [deadlineUrgencyFor]. Renders nothing when there's no deadline at all,
/// rather than implying one exists.
class _DeadlineBadge extends StatelessWidget {
  const _DeadlineBadge({required this.deadline});

  final DateTime? deadline;

  @override
  Widget build(BuildContext context) {
    final urgency = deadlineUrgencyFor(deadline);
    if (urgency == DeadlineUrgency.none) return const SizedBox.shrink();

    final (type, icon, label) = switch (urgency) {
      DeadlineUrgency.passed => (
        AppStatusType.neutral,
        Icons.event_busy_outlined,
        'Application deadline has passed',
      ),
      DeadlineUrgency.soon => (
        AppStatusType.warning,
        Icons.timer_outlined,
        'Apply by ${formatDate(deadline!)} — closing soon',
      ),
      DeadlineUrgency.normal => (
        AppStatusType.info,
        Icons.event_outlined,
        'Apply by ${formatDate(deadline!)}',
      ),
      DeadlineUrgency.none => (AppStatusType.neutral, Icons.event_outlined, ''),
    };

    return StatusChip(type: type, icon: icon, label: label);
  }
}

/// The description, given a soft tinted surface with generous padding and
/// no border — deliberately distinct from [_SkillsSection]'s bordered card
/// and [_FactsSection]'s tile grid, so the page doesn't read as a stack of
/// identical rounded rectangles.
class _DescriptionSection extends StatelessWidget {
  const _DescriptionSection({required this.opportunity});

  final OpportunityModel opportunity;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: AppRadius.largeRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('About This Opportunity', style: textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          Text(
            opportunity.description,
            style: textTheme.bodyLarge?.copyWith(height: 1.7),
          ),
        ],
      ),
    );
  }
}

/// Real eligible majors as polished chips (Phase 8B-3.2's
/// [OpportunityModel.eligibleMajors]) — the sole authoritative academic
/// requirement (the legacy free-text `field_of_study` is deprecated as of
/// the Opportunity Academic Matching Cleanup and is no longer modeled or
/// displayed anywhere in this app). Only ever built when [majors] is non-empty —
/// an unrestricted opportunity renders nothing here, rather than a
/// fabricated "Open to all majors".
class _EligibleMajorsSection extends StatelessWidget {
  const _EligibleMajorsSection({required this.majors});

  final List<String> majors;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Eligible Majors'),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: [
              for (final major in majors)
                StatusChip(type: AppStatusType.info, label: major),
            ],
          ),
        ],
      ),
    );
  }
}

class _SkillsSection extends StatelessWidget {
  const _SkillsSection({required this.opportunity});

  final OpportunityModel opportunity;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Skills'),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: [
              for (final opportunitySkill in opportunity.opportunitySkills)
                StatusChip(
                  label: opportunitySkill.isRequired
                      ? '${opportunitySkill.skill.name} (Required)'
                      : opportunitySkill.skill.name,
                  // `info`, not `primary` -- same dark-mode contrast fix
                  // already applied to the Organization-side Required
                  // Skills chips and the Eligible Major chip (see
                  // organization_opportunity_details_screen.dart).
                  type: opportunitySkill.isRequired
                      ? AppStatusType.info
                      : AppStatusType.neutral,
                  compact: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The former plain label/value "Details" list, now a responsive grid of
/// icon-led fact tiles — the same information, presented with more visual
/// structure than a stack of text rows.
class _FactsSection extends StatelessWidget {
  const _FactsSection({
    required this.opportunity,
    required this.entranceController,
  });

  final OpportunityModel opportunity;
  final AnimationController entranceController;

  @override
  Widget build(BuildContext context) {
    final facts = [
      (
        Icons.place_outlined,
        'Location',
        opportunity.location ?? 'Not specified',
      ),
      // Opportunity Academic Matching Cleanup: Field of Study (legacy,
      // free-text) is deliberately not shown here any more -- Eligible
      // Majors is the sole authoritative academic requirement (see
      // [_EligibleMajorsSection] and the fallback fact just below).
      // Only shown when there's no explicit restriction -- an explicit
      // list gets its own prominent chip section ([_EligibleMajorsSection])
      // instead, so this never duplicates it. A truthful "All majors
      // welcome" beats an unexplained absence, making the actual business
      // rule explicit to the Student.
      if (opportunity.eligibleMajors.isEmpty)
        (Icons.diversity_3_outlined, 'Eligible Majors', 'All majors welcome'),
      (
        Icons.school_outlined,
        'Education Level',
        educationLevelLabels[opportunity.educationLevel] ?? 'Not specified',
      ),
      (Icons.payments_outlined, 'Salary Range', formatSalaryRange(opportunity)),
      (
        Icons.event_outlined,
        'Application Deadline',
        opportunity.applicationDeadline != null
            ? formatDate(opportunity.applicationDeadline!)
            : 'Not specified',
      ),
      (
        Icons.groups_outlined,
        'Positions Available',
        '${opportunity.positionsAvailable}',
      ),
      if (opportunity.createdAt != null)
        (Icons.history_outlined, 'Posted', formatDate(opportunity.createdAt!)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Details', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 520 ? 2 : 1;
            const spacing = AppSpacing.sm;
            final tileWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final (i, (icon, label, value)) in facts.indexed)
                  SizedBox(
                    width: tileWidth,
                    child: _Stagger(
                      controller: entranceController,
                      index: i,
                      count: facts.length + 2,
                      child: _FactTile(icon: icon, label: label, value: value),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// One "information module" (per this phase's own wording) — a large icon
/// badge, a clearly-muted label, and a strong, high-contrast value. A
/// subtle non-clickable hover (lift + border tint, no pointer cursor)
/// gives it life without implying it's tappable, since none of these
/// tiles do anything.
class _FactTile extends StatefulWidget {
  const _FactTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  State<_FactTile> createState() => _FactTileState();
}

class _FactTileState extends State<_FactTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final duration = AppMotion.reduced(context, AppMotion.normal);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: duration,
        curve: AppMotion.standard,
        transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: AppRadius.mediumRadius,
          border: Border.all(
            color: _hovered
                ? AppColors.primary.withValues(alpha: 0.4)
                : AppColors.border,
          ),
          boxShadow: _hovered ? AppShadows.card : const [],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: AppRadius.mediumRadius,
              ),
              child: Icon(widget.icon, size: 22, color: AppColors.primaryDark),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.label,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.value,
                    style: textTheme.titleMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
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

/// A compact organization-identity card — avatar, name, type, and industry
/// (all real fields already on [OrganizationProfileModel]; nothing
/// fabricated). Renders nothing when the relation wasn't eager-loaded.
/// Tappable (Organization Public Profile phase) — navigates to the real
/// public Company Profile for [organization.id].
class _OrganizationCard extends StatelessWidget {
  const _OrganizationCard({required this.organization});

  final OrganizationProfileModel? organization;

  @override
  Widget build(BuildContext context) {
    final organization = this.organization;
    if (organization == null) return const SizedBox.shrink();

    final textTheme = Theme.of(context).textTheme;

    final hasIndustry =
        organization.industry != null &&
        organization.industry!.trim().isNotEmpty;
    final hasWebsite =
        organization.website != null && organization.website!.trim().isNotEmpty;

    return AppCard(
      interactive: true,
      onTap: () => context.push(AppRoutes.companyProfile(organization.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'About the Organization'),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              AppAvatar(
                name: organization.organizationName,
                size: 52,
                fallbackIcon: Icons.apartment_outlined,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      organization.organizationName,
                      style: textTheme.titleMedium,
                    ),
                    Text(
                      _organizationTypeLabel(organization.organizationType),
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (hasIndustry) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Divider(height: 1),
            ),
            OpportunityDetailRow(
              label: 'Industry',
              value: organization.industry!,
            ),
          ],
          if (hasWebsite) ...[
            if (!hasIndustry)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Divider(height: 1),
              )
            else
              const SizedBox(height: AppSpacing.xxs),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Website',
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  // Selectable (copyable), not a live link -- this codebase
                  // deliberately avoids a `url_launcher` dependency (see
                  // StudentApplicationDetailsScreen's own meeting-link row
                  // for the same established pattern). The card itself
                  // (see this widget's own doc comment) is now the real
                  // way to reach the organization's public Company
                  // Profile, so no separate action is needed here.
                  Expanded(
                    child: SelectableText(
                      organization.website!,
                      textAlign: TextAlign.end,
                      style: textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _organizationTypeLabel(String type) {
    const labels = {
      'company': 'Company',
      'university': 'University',
      'ngo': 'NGO',
      'training_center': 'Training Center',
      'government': 'Government',
      'other': 'Other',
    };
    return labels[type] ?? type;
  }
}

/// The button/chip crossfade shared by [_ApplyPanelCard] and
/// [_StickyApplyBar] — driven by [applied] (itself
/// `StudentApplicationsProvider.hasAppliedTo`, the single source of truth
/// on the Flutter side) and [blockedReason] (a client-side *prediction* of
/// what the backend would say — see [_applyBlockedReasonFor] — never the
/// actual authority; the real Apply flow re-validates server-side exactly
/// as before). A fixed height keeps every branch the same size, so the
/// surrounding bar/card never resizes mid-crossfade.
///
/// [onGradient] switches the palette for the dominant blue-gradient panel
/// ([_ApplyPanelCard]): a large white "Apply Now" button with a primary
/// blue label (reads clearly on the gradient) instead of the standard
/// blue-on-white [PrimaryButton]. [_StickyApplyBar] (mobile) keeps the
/// standard palette -- a bottom bar should stay quiet, not compete with
/// the page.
class _ApplyActionButton extends StatelessWidget {
  const _ApplyActionButton({
    required this.applied,
    required this.blockedReason,
    required this.onApply,
    this.onGradient = false,
  });

  final bool applied;
  final _ApplyBlockedReason blockedReason;
  final VoidCallback onApply;
  final bool onGradient;

  String get _blockedLabel => switch (blockedReason) {
    _ApplyBlockedReason.closed => 'Opportunity Closed',
    _ApplyBlockedReason.deadlinePassed => 'Deadline Passed',
    _ApplyBlockedReason.ineligibleMajor => 'Not Eligible',
    _ApplyBlockedReason.none => '',
  };

  @override
  Widget build(BuildContext context) {
    final blocked = !applied && blockedReason != _ApplyBlockedReason.none;

    return SizedBox(
      height: 52,
      child: AnimatedSwitcher(
        duration: AppMotion.reduced(context, AppMotion.normal),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: applied
            ? KeyedSubtree(
                key: const ValueKey('applied'),
                child: onGradient
                    ? const _OnGradientPill(
                        icon: Icons.check_circle_rounded,
                        label: 'Application Submitted',
                      )
                    : const Align(
                        alignment: Alignment.centerLeft,
                        child: StatusChip(
                          label: 'Already Applied',
                          type: AppStatusType.success,
                          icon: Icons.check_circle_outline,
                        ),
                      ),
              )
            : blocked
            ? KeyedSubtree(
                key: const ValueKey('blocked'),
                child: onGradient
                    ? _OnGradientPill(
                        icon: Icons.block_rounded,
                        label: _blockedLabel,
                      )
                    : SizedBox(
                        width: double.infinity,
                        child: SecondaryButton(
                          label: _blockedLabel,
                          onPressed: null,
                        ),
                      ),
              )
            : KeyedSubtree(
                key: const ValueKey('apply'),
                child: onGradient
                    ? _WhiteApplyButton(onPressed: onApply)
                    : SizedBox(
                        width: double.infinity,
                        child: PrimaryButton(
                          label: 'Apply Now',
                          onPressed: onApply,
                        ),
                      ),
              ),
      ),
    );
  }
}

/// A large, white, full-width Apply button for the blue-gradient panel —
/// a primary-blue label (not the usual white-on-blue) so it reads clearly
/// against the gradient, plus a trailing arrow to reinforce it as the
/// page's primary action. Reuses [ButtonInteractionSurface] (the same
/// hover-lift/press-scale [PrimaryButton] itself uses) rather than
/// building bespoke hover handling.
class _WhiteApplyButton extends StatelessWidget {
  const _WhiteApplyButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ButtonInteractionSurface(
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.primary,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mediumRadius),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Apply Now'),
              SizedBox(width: AppSpacing.xs),
              Icon(Icons.arrow_forward_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "already applied" / "blocked" pill for the gradient panel — a
/// translucent white surface (readable on any tone) rather than
/// [StatusChip]'s solid light backgrounds, which would look washed out
/// directly on the blue gradient.
class _OnGradientPill extends StatelessWidget {
  const _OnGradientPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: AppRadius.mediumRadius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: Colors.white),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The explanation shown under a blocked [_ApplyActionButton] (section 12:
/// "disabled/blocked + explanation") — omitted once applied, and omitted
/// entirely when nothing blocks Apply. A restricted-but-eligible
/// opportunity instead shows a real, positive confirmation (section 8's
/// "Eligible: your major is eligible" state) rather than staying silent.
class _ApplyStatusLine extends StatelessWidget {
  const _ApplyStatusLine({
    required this.opportunity,
    required this.applied,
    required this.blockedReason,
  });

  final OpportunityModel opportunity;
  final bool applied;
  final _ApplyBlockedReason blockedReason;

  bool get _isRestricted => opportunity.eligibleMajors.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (applied) return const SizedBox.shrink();

    final (icon, color, text) = switch (blockedReason) {
      _ApplyBlockedReason.closed => (
        Icons.info_outline,
        AppColors.textSecondary,
        'This opportunity is no longer accepting applications.',
      ),
      _ApplyBlockedReason.deadlinePassed => (
        Icons.info_outline,
        AppColors.textSecondary,
        'The application deadline has passed.',
      ),
      _ApplyBlockedReason.ineligibleMajor => (
        Icons.cancel_outlined,
        AppColors.error,
        'Your major is not eligible for this opportunity.',
      ),
      _ApplyBlockedReason.none when _isRestricted => (
        Icons.check_circle_outline,
        AppColors.success,
        'Your major is eligible for this opportunity.',
      ),
      _ApplyBlockedReason.none => (null, null, null),
    };

    if (text == null) return const SizedBox.shrink();

    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(
            child: Text(
              text,
              style: textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// The desktop side-panel's (and tablet's in-flow) Apply card.
/// The dominant, unmissable Apply panel — a strong primary-blue gradient
/// surface (deliberately not just another white [AppCard], per this
/// phase's "impossible to miss" direction) holding the positions-available
/// count, the large white Apply CTA, and one truthful, generic supporting
/// line. The finer eligibility/blocked explanation ([_ApplyStatusLine])
/// sits just below, on the normal surface, since its longer sentence and
/// semantic (error/success) colors read better off the gradient than on
/// it.
class _ApplyPanelCard extends StatelessWidget {
  const _ApplyPanelCard({
    required this.opportunity,
    required this.applied,
    required this.blockedReason,
    required this.onApply,
  });

  final OpportunityModel opportunity;
  final bool applied;
  final _ApplyBlockedReason blockedReason;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.primaryDark],
            ),
            borderRadius: AppRadius.largeRadius,
            boxShadow: AppShadows.elevated,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${opportunity.positionsAvailable} position'
                '${opportunity.positionsAvailable == 1 ? '' : 's'} available',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _ApplyActionButton(
                applied: applied,
                blockedReason: blockedReason,
                onApply: onApply,
                onGradient: true,
              ),
              if (!applied) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  // Truthful and generic (section 13): this is exactly
                  // what `ApplyBottomSheet`'s real submit flow does --
                  // no screening/AI-matching/response-time claim, since
                  // none of those are real.
                  'Your application goes directly to the organization.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        _ApplyStatusLine(
          opportunity: opportunity,
          applied: applied,
          blockedReason: blockedReason,
        ),
      ],
    );
  }
}

/// The mobile equivalent of [_ApplyPanelCard] — a bar anchored to the
/// bottom of the screen via `Scaffold.bottomNavigationBar` (which already
/// handles the safe-area inset correctly), so Apply stays reachable no
/// matter how far the student has scrolled. Deliberately dense: no status
/// explanation line here (the disabled button's own label already says
/// why), to keep the bar's footprint minimal on a phone-sized viewport.
class _StickyApplyBar extends StatelessWidget {
  const _StickyApplyBar({
    required this.applied,
    required this.blockedReason,
    required this.onApply,
  });

  final bool applied;
  final _ApplyBlockedReason blockedReason;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: AppShadows.elevated,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
            vertical: AppSpacing.sm,
          ),
          child: _ApplyActionButton(
            applied: applied,
            blockedReason: blockedReason,
            onApply: onApply,
          ),
        ),
      ),
    );
  }
}

/// A shaped loading placeholder — a hero-sized block, a couple of text
/// lines, chip-sized blocks, and a few fact-tile blocks — matching the
/// real layout closely enough that the page doesn't visually "jump" once
/// content arrives, instead of a bare spinner.
class _DetailsSkeleton extends StatelessWidget {
  const _DetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSkeleton(height: 44, borderRadius: AppRadius.mediumRadius),
          const SizedBox(height: AppSpacing.sm),
          const AppSkeleton(width: 220, height: 16),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: const [
              AppSkeleton(
                width: 70,
                height: 24,
                borderRadius: AppRadius.pillRadius,
              ),
              SizedBox(width: AppSpacing.xs),
              AppSkeleton(
                width: 90,
                height: 24,
                borderRadius: AppRadius.pillRadius,
              ),
              SizedBox(width: AppSpacing.xs),
              AppSkeleton(
                width: 80,
                height: 24,
                borderRadius: AppRadius.pillRadius,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const AppSkeleton(height: 120, borderRadius: AppRadius.largeRadius),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: const [
              Expanded(
                child: AppSkeleton(
                  height: 64,
                  borderRadius: AppRadius.mediumRadius,
                ),
              ),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppSkeleton(
                  height: 64,
                  borderRadius: AppRadius.mediumRadius,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
