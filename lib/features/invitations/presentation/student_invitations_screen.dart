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
import '../../../core/widgets/app_widgets.dart';
import '../../../models/invitation_model.dart';
import '../../../providers/student_invitations_provider.dart';
import '../../../routes/app_routes.dart';

const _tabletBreakpoint = 600.0;
const _desktopBreakpoint = 1200.0;

enum _ScreenTier { mobile, tablet, desktop }

_ScreenTier _tierFor(double width) {
  if (width >= _desktopBreakpoint) return _ScreenTier.desktop;
  if (width >= _tabletBreakpoint) return _ScreenTier.tablet;
  return _ScreenTier.mobile;
}

/// Real, locally-derived filters over the already-loaded invitation list —
/// no new backend query. Matches [InvitationModel.status] exactly (only
/// `pending`/`accepted`/`declined` really exist — see this screen's own
/// audit note below).
enum _Filter { all, pending, accepted, declined }

const _filterLabels = {
  _Filter.all: 'All',
  _Filter.pending: 'Pending',
  _Filter.accepted: 'Accepted',
  _Filter.declined: 'Declined',
};

bool _matchesFilter(_Filter filter, String status) {
  switch (filter) {
    case _Filter.all:
      return true;
    case _Filter.pending:
      return status == 'pending';
    case _Filter.accepted:
      return status == 'accepted';
    case _Filter.declined:
      return status == 'declined';
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'accepted':
      return 'Accepted';
    case 'declined':
      return 'Declined';
    case 'pending':
    default:
      return 'Pending';
  }
}

AppStatusType _statusChipType(String status) {
  switch (status) {
    case 'accepted':
      return AppStatusType.success;
    case 'declined':
      return AppStatusType.neutral;
    case 'pending':
    default:
      return AppStatusType.warning;
  }
}

/// Status is never color-only — a distinct icon always accompanies the
/// label (UI Phase 5's own accessibility requirement).
IconData _statusIcon(String status) {
  switch (status) {
    case 'accepted':
      return Icons.check_circle_outline_rounded;
    case 'declined':
      return Icons.cancel_outlined;
    case 'pending':
    default:
      return Icons.hourglass_top_rounded;
  }
}

/// The student's received-invitations inbox (UI Phase 5) — a premium
/// recruiting-invitation surface, deliberately distinct from
/// [StudentApplicationsScreen]'s tracking-focused card language (UI Phase
/// 4). Every field rendered here is audited against the real `Invitation`
/// data this app already loads:
///
/// - **Statuses**: only `pending`, `accepted`, `declined` really exist
///   (`invitations.status` is a 3-value DB enum — see
///   `2026_08_20_100000_create_invitations_table.php` on the read-only
///   backend). There is no `expires_at` column and no expiration business
///   rule anywhere in `docs/BUSINESS_RULES.md` — so no "Expired" state is
///   built here; inventing one would be fabricated data.
/// - **Fields**: `GET /api/student/invitations` (`Student\InvitationController
///   ::index()`) eager-loads only `opportunity:id,title,organization_id`
///   and `opportunity.organizationProfile:id,organization_name` — meaning
///   opportunity type, employment type, work mode, location, and deadline
///   are genuinely absent from this response (confirmed in
///   `docs/API.md` section 5a too), not just unparsed by
///   [InvitationModel]. This card therefore cannot show any of that
///   metadata without fabricating it — see this phase's own final report
///   for this gap. No organization logo/industry field exists either, so
///   [AppAvatar]'s real initials fallback is used, exactly as
///   `OpportunityCard`/`_ApplicationCard` already do for the same reason.
/// - **Accept**: `PUT /api/student/invitations/{id}/accept` only flips
///   `status` to `accepted` — it never creates an `Application` (`cv_id` is
///   required and no CV is chosen at invitation time). This screen
///   preserves that exactly: accepting still routes to the real Opportunity
///   Details/Apply flow afterward, never a fabricated "View Application"
///   link (there is no created Application ID to link to).
/// - **Decline**: `PUT /api/student/invitations/{id}/decline` flips
///   `status` to `declined`, never creates an Application. Both actions are
///   permanent — `docs/BUSINESS_RULES.md` §5a: "an invitation's `status`
///   ... can only ever be set once by the receiving Student" (a repeat
///   attempt is a `409`) — which is why this phase adds a real decline
///   confirmation warning it's irreversible, and why no Accept action is
///   ever shown again once declined.
class StudentInvitationsScreen extends StatefulWidget {
  const StudentInvitationsScreen({super.key});

  @override
  State<StudentInvitationsScreen> createState() =>
      _StudentInvitationsScreenState();
}

class _StudentInvitationsScreenState extends State<StudentInvitationsScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  _Filter _filter = _Filter.all;
  String _query = '';

  /// The invitation whose Accept just succeeded — kept true only for a
  /// brief celebratory beat (see [_accept]) before the real, preserved
  /// redirect to Opportunity Details/Apply happens. Reset once the student
  /// returns here, so a stale success panel never lingers.
  int? _justAcceptedId;

  late final AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<StudentInvitationsProvider>().loadInvitations();
    });

    final reducedMotion = SchedulerBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    _entranceController = AnimationController(
      vsync: this,
      duration: reducedMotion
          ? const Duration(milliseconds: 1)
          : const Duration(milliseconds: 600),
    )..forward();

    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  void _clearFilters() {
    setState(() {
      _filter = _Filter.all;
      _searchController.clear();
    });
  }

  void _viewOpportunity(InvitationModel invitation) {
    context.push(AppRoutes.studentOpportunityDetails(invitation.opportunityId));
  }

  /// Reuses [StudentInvitationsProvider.accept] exactly — no new Accept
  /// flow, no bypassed eligibility/CV/conflict handling. On real
  /// backend-confirmed success, the card gets a brief, one-shot success
  /// beat, then this screen still redirects to Opportunity Details, the
  /// same real place the previous implementation always sent the student
  /// (that's where they actually pick a CV and submit, per
  /// `Student\InvitationController::accept()`'s own doc comment).
  Future<void> _accept(InvitationModel invitation) async {
    final provider = context.read<StudentInvitationsProvider>();
    await provider.accept(invitation.id);
    if (!mounted) return;
    if (provider.respondErrorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.respondErrorMessage!)),
      );
      return;
    }

    setState(() => _justAcceptedId = invitation.id);
    await Future.delayed(
      AppMotion.reduced(context, const Duration(milliseconds: 650)),
    );
    if (!mounted) return;
    await context.push(
      AppRoutes.studentOpportunityDetails(invitation.opportunityId),
    );
    if (!mounted) return;
    setState(() => _justAcceptedId = null);
  }

  /// Real backend decline, unchanged — the confirmation step is new UI
  /// (not previously present) but the copy is truthful: per
  /// `docs/BUSINESS_RULES.md` §5a, a decline can never be reversed by the
  /// student (a second response attempt is rejected with `409`).
  Future<void> _decline(InvitationModel invitation) async {
    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Decline invitation?',
      message: "You won't be able to accept this invitation afterward.",
      confirmLabel: 'Decline',
      cancelLabel: 'Keep Invitation',
      type: AppConfirmationType.warning,
    );
    if (!confirmed || !mounted) return;

    final provider = context.read<StudentInvitationsProvider>();
    await provider.decline(invitation.id);
    if (!mounted) return;
    if (provider.respondErrorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.respondErrorMessage!)),
      );
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Invitation declined')));
  }

  List<InvitationModel> _filtered(List<InvitationModel> invitations) {
    return invitations.where((invitation) {
      if (!_matchesFilter(_filter, invitation.status)) return false;
      if (_query.isEmpty) return true;
      return invitation.opportunityTitle.toLowerCase().contains(_query) ||
          invitation.organizationName.toLowerCase().contains(_query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentInvitationsProvider>();
    final tier = _tierFor(MediaQuery.sizeOf(context).width);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invitations'),
        actions: const [ThemeToggleButton(), SizedBox(width: AppSpacing.xs)],
      ),
      body: SafeArea(child: _buildBody(provider, tier)),
    );
  }

  Widget _buildBody(StudentInvitationsProvider provider, _ScreenTier tier) {
    if (provider.isLoading && provider.invitations.isEmpty) {
      return _InvitationsSkeleton(tier: tier);
    }

    if (provider.listErrorMessage != null && provider.invitations.isEmpty) {
      return AppErrorView(
        message: provider.listErrorMessage!,
        onRetry: provider.loadInvitations,
      );
    }

    final all = provider.invitations;
    final horizontalPadding = tier == _ScreenTier.mobile
        ? AppSpacing.screenHorizontal
        : AppSpacing.xl;
    final maxWidth = tier == _ScreenTier.desktop ? 1100.0 : 760.0;

    if (all.isEmpty) {
      return RefreshIndicator(
        onRefresh: provider.loadInvitations,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PageHeader(
                tier: tier,
                entranceController: _entranceController,
              ),
              SizedBox(
                height: 420,
                child: AppEmptyView(
                  icon: Icons.mail_outline_rounded,
                  title: 'No Invitations Yet',
                  message:
                      'When an organization invites you to an opportunity, '
                      'it will appear here.',
                  actionLabel: 'Explore Opportunities',
                  onAction: () => context.go(AppRoutes.studentOpportunities),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filtered(all);
    final total = all.length;
    final pending = all.where((invitation) => invitation.isPending).length;
    final accepted = all.where((invitation) => invitation.isAccepted).length;
    final declined = all.where((invitation) => invitation.isDeclined).length;
    final counts = {
      _Filter.all: total,
      _Filter.pending: pending,
      _Filter.accepted: accepted,
      _Filter.declined: declined,
    };

    return RefreshIndicator(
      onRefresh: provider.loadInvitations,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PageHeader(
                  tier: tier,
                  entranceController: _entranceController,
                ),
                _Stagger(
                  controller: _entranceController,
                  index: 1,
                  count: 4,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      AppSpacing.lg,
                      horizontalPadding,
                      0,
                    ),
                    child: _SummaryRow(
                      total: total,
                      pending: pending,
                      accepted: accepted,
                      declined: declined,
                    ),
                  ),
                ),
                _Stagger(
                  controller: _entranceController,
                  index: 2,
                  count: 4,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      AppSpacing.lg,
                      horizontalPadding,
                      0,
                    ),
                    child: _SearchAndFilters(
                      controller: _searchController,
                      filter: _filter,
                      counts: counts,
                      onFilterChanged: (value) =>
                          setState(() => _filter = value),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    AppSpacing.md,
                    horizontalPadding,
                    AppSpacing.xxl,
                  ),
                  child: filtered.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xl),
                          child: AppEmptyView(
                            icon: Icons.search_off_rounded,
                            title: 'No Matching Invitations',
                            message:
                                'Try a different search term or clear your filters.',
                            actionLabel: 'Clear Filters',
                            onAction: _clearFilters,
                          ),
                        )
                      : _InvitationsGrid(
                          tier: tier,
                          invitations: filtered,
                          entranceController: _entranceController,
                          justAcceptedId: _justAcceptedId,
                          onAccept: _accept,
                          onDecline: _decline,
                          onViewOpportunity: _viewOpportunity,
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

/// Fades and slides a section in as part of the staged entrance. A private
/// per-file copy of the same small helper `StudentApplicationsScreen`
/// already defines — see that class's own doc comment on why it's kept
/// separate rather than shared.
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
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// A compact page identity — deliberately not a giant full-bleed hero like
/// [StudentApplicationsScreen]'s own header, so this screen reads as its
/// own place rather than a re-skinned Applications page. A subtle
/// primary-blue wash is the only color treatment (this app reserves true
/// purple/[AppColors.aiAccent] exclusively for AI-attributed content — see
/// that token's own doc comment — so the "blue/purple" identity this phase
/// asked for is expressed as a blue-family gradient instead of introducing
/// a second, conflicting purple).
class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.tier, required this.entranceController});

  final _ScreenTier tier;
  final AnimationController entranceController;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final horizontalPadding = tier == _ScreenTier.mobile
        ? AppSpacing.screenHorizontal
        : AppSpacing.xl;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryContainer.withValues(alpha: 0.55),
            AppColors.surface,
          ],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          AppSpacing.lg,
          horizontalPadding,
          AppSpacing.md,
        ),
        child: _Stagger(
          controller: entranceController,
          index: 0,
          count: 4,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary,
                  boxShadow: AppShadows.card,
                ),
                child: const Icon(
                  Icons.mail_outline_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Invitations',
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Opportunities organizations have invited you to explore.',
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Real, locally-derived counts only — [total]/[pending]/[accepted]/
/// [declined] are exactly the invitations already loaded from
/// `GET /api/student/invitations`, never a fabricated analytics number.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.total,
    required this.pending,
    required this.accepted,
    required this.declined,
  });

  final int total;
  final int pending;
  final int accepted;
  final int declined;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: AppRadius.largeRadius,
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryTile(
              icon: Icons.inbox_outlined,
              label: 'Total',
              value: total,
              color: AppColors.textSecondary,
            ),
          ),
          _SummaryDivider(),
          Expanded(
            child: _SummaryTile(
              icon: Icons.hourglass_top_rounded,
              label: 'Pending',
              value: pending,
              color: AppColors.warning,
            ),
          ),
          _SummaryDivider(),
          Expanded(
            child: _SummaryTile(
              icon: Icons.check_circle_outline_rounded,
              label: 'Accepted',
              value: accepted,
              color: AppColors.success,
            ),
          ),
          _SummaryDivider(),
          Expanded(
            child: _SummaryTile(
              icon: Icons.cancel_outlined,
              label: 'Declined',
              value: declined,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryDivider extends StatelessWidget {
  const _SummaryDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      color: AppColors.border,
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 2),
        TweenAnimationBuilder<int>(
          tween: IntTween(begin: 0, end: value),
          duration: AppMotion.reduced(context, const Duration(milliseconds: 700)),
          curve: AppMotion.entrance,
          builder: (context, animatedValue, _) => Text(
            '$animatedValue',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _SearchAndFilters extends StatelessWidget {
  const _SearchAndFilters({
    required this.controller,
    required this.filter,
    required this.counts,
    required this.onFilterChanged,
  });

  final TextEditingController controller;
  final _Filter filter;
  final Map<_Filter, int> counts;
  final ValueChanged<_Filter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSearchField(
          controller: controller,
          hint: 'Search by opportunity or organization',
        ),
        const SizedBox(height: AppSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final option in _Filter.values) ...[
                _FilterChip(
                  label: _filterLabels[option]!,
                  count: counts[option] ?? 0,
                  selected: filter == option,
                  // Pending is the key product moment (UI Phase 5) — it
                  // stays visually primary even unselected, via a warning
                  // tint instead of the neutral surface every other
                  // unselected chip uses.
                  emphasize: option == _Filter.pending,
                  onTap: () => onFilterChanged(option),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.emphasize,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final bool emphasize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = selected
        ? AppColors.primary
        : (emphasize ? AppColors.warningBackground : AppColors.surfaceVariant);
    final border = selected
        ? AppColors.primary
        : (emphasize ? AppColors.warning : AppColors.border);
    final foreground = selected
        ? AppColors.onPrimary
        : (emphasize ? AppColors.warning : AppColors.textSecondary);

    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $count',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.reduced(context, AppMotion.fast),
          curve: AppMotion.standard,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppRadius.pillRadius,
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.22)
                      : foreground.withValues(alpha: 0.12),
                  borderRadius: AppRadius.pillRadius,
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lays [invitations] out as a single column on mobile/tablet, or a real
/// two-column grid at the desktop tier (UI Phase 5 §20) — a plain `Wrap` of
/// fixed-width children rather than `GridView`, since invitation cards have
/// genuinely variable height (an optional message can make one card taller
/// than its neighbor) and `GridView`'s equal-height cells would either
/// clip or force awkward empty space.
class _InvitationsGrid extends StatelessWidget {
  const _InvitationsGrid({
    required this.tier,
    required this.invitations,
    required this.entranceController,
    required this.justAcceptedId,
    required this.onAccept,
    required this.onDecline,
    required this.onViewOpportunity,
  });

  final _ScreenTier tier;
  final List<InvitationModel> invitations;
  final AnimationController entranceController;
  final int? justAcceptedId;
  final ValueChanged<InvitationModel> onAccept;
  final ValueChanged<InvitationModel> onDecline;
  final ValueChanged<InvitationModel> onViewOpportunity;

  @override
  Widget build(BuildContext context) {
    if (tier != _ScreenTier.desktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < invitations.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            _Stagger(
              controller: entranceController,
              index: 3,
              count: 4,
              child: _InvitationCardBinding(
                invitation: invitations[i],
                justAcceptedId: justAcceptedId,
                onAccept: onAccept,
                onDecline: onDecline,
                onViewOpportunity: onViewOpportunity,
              ),
            ),
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppSpacing.md;
        final cardWidth = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final invitation in invitations)
              SizedBox(
                width: cardWidth,
                child: _Stagger(
                  controller: entranceController,
                  index: 3,
                  count: 4,
                  child: _InvitationCardBinding(
                    invitation: invitation,
                    justAcceptedId: justAcceptedId,
                    onAccept: onAccept,
                    onDecline: onDecline,
                    onViewOpportunity: onViewOpportunity,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Binds one [InvitationModel] to [_InvitationCard]'s per-invitation
/// callbacks/loading — kept separate purely so [_InvitationsGrid] doesn't
/// repeat the same closure wiring twice (mobile column vs. desktop grid).
class _InvitationCardBinding extends StatelessWidget {
  const _InvitationCardBinding({
    required this.invitation,
    required this.justAcceptedId,
    required this.onAccept,
    required this.onDecline,
    required this.onViewOpportunity,
  });

  final InvitationModel invitation;
  final int? justAcceptedId;
  final ValueChanged<InvitationModel> onAccept;
  final ValueChanged<InvitationModel> onDecline;
  final ValueChanged<InvitationModel> onViewOpportunity;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentInvitationsProvider>();

    return _InvitationCard(
      invitation: invitation,
      isResponding: provider.isRespondingTo(invitation.id),
      isJustAccepted: justAcceptedId == invitation.id,
      onAccept: () => onAccept(invitation),
      onDecline: () => onDecline(invitation),
      onViewOpportunity: () => onViewOpportunity(invitation),
    );
  }
}

/// A small "this came from an organization" identity tag — real, not a
/// fabricated verification badge (UI Phase 5 §9 explicitly forbids that).
class _InvitationBadge extends StatelessWidget {
  const _InvitationBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: AppRadius.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mail_outline_rounded, size: 11, color: AppColors.primaryDark),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              'Invitation',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _messageExpandThreshold = 140;

/// The redesigned invitation card (UI Phase 5) — organization identity
/// first, then the opportunity, then a clear action area. Deliberately not
/// a copy of `_ApplicationCard`: no left status-accent bar, no card-wide
/// tap target (there are three distinct real actions, not one), and a
/// dedicated organization-identity row up top so the card reads as
/// "a company reached out to me" rather than "track this submission."
class _InvitationCard extends StatefulWidget {
  const _InvitationCard({
    required this.invitation,
    required this.isResponding,
    required this.isJustAccepted,
    required this.onAccept,
    required this.onDecline,
    required this.onViewOpportunity,
  });

  final InvitationModel invitation;
  final bool isResponding;
  final bool isJustAccepted;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onViewOpportunity;

  @override
  State<_InvitationCard> createState() => _InvitationCardState();
}

class _InvitationCardState extends State<_InvitationCard> {
  bool _hovered = false;
  bool _messageExpanded = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final invitation = widget.invitation;
    final message = invitation.message?.trim();
    final hasMessage = message != null && message.isNotEmpty;
    final isLongMessage = hasMessage && message.length > _messageExpandThreshold;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppMotion.reduced(context, AppMotion.normal),
        curve: AppMotion.standard,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: AppRadius.largeRadius,
          border: Border.all(
            color: _hovered
                ? AppColors.primary.withValues(alpha: 0.35)
                : AppColors.border,
          ),
          boxShadow: _hovered ? AppShadows.elevated : AppShadows.card,
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _OrganizationAvatar(hovered: _hovered, name: invitation.organizationName),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _InvitationBadge(),
                      const SizedBox(height: 3),
                      Text(
                        invitation.organizationName.isEmpty
                            ? 'An organization'
                            : invitation.organizationName,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                AnimatedSwitcher(
                  duration: AppMotion.reduced(context, AppMotion.normal),
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: StatusChip(
                    key: ValueKey(invitation.status),
                    compact: true,
                    icon: _statusIcon(invitation.status),
                    label: _statusLabel(invitation.status),
                    type: _statusChipType(invitation.status),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'invited you to',
              style: textTheme.labelSmall?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 2),
            Text(
              invitation.opportunityTitle.isEmpty
                  ? 'an opportunity'
                  : invitation.opportunityTitle,
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (invitation.createdAt != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_outlined, size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    'Invited ${formatDate(invitation.createdAt!)}',
                    style: textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ],
            if (hasMessage) ...[
              const SizedBox(height: AppSpacing.sm),
              GestureDetector(
                onTap: isLongMessage
                    ? () => setState(() => _messageExpanded = !_messageExpanded)
                    : null,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: AppRadius.mediumRadius,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        message,
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: _messageExpanded ? null : 3,
                        overflow: _messageExpanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                      ),
                      if (isLongMessage) ...[
                        const SizedBox(height: 2),
                        Text(
                          _messageExpanded ? 'Show less' : 'Show more',
                          style: textTheme.labelSmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            AnimatedSwitcher(
              duration: AppMotion.reduced(context, AppMotion.normal),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: widget.isJustAccepted
                  ? const _AcceptSuccessPanel(key: ValueKey('success'))
                  : _InvitationActions(
                      key: const ValueKey('actions'),
                      invitation: invitation,
                      isResponding: widget.isResponding,
                      onAccept: widget.onAccept,
                      onDecline: widget.onDecline,
                      onViewOpportunity: widget.onViewOpportunity,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// UI Phase 5.1: uses the dedicated [OrganizationAvatar] identity mark
/// (real two-letter initials, e.g. "ABOMOHAMAD" → "AB") rather than the
/// generic [AppAvatar] — see that widget's own doc comment on why this had
/// to be a separate component instead of changing [AppAvatar] itself
/// (which is shared by every *person* avatar in the app and must not
/// change behavior). This wrapper only ever adds the Web hover lift; the
/// mark's own border/gradient/shadow live in [OrganizationAvatar].
class _OrganizationAvatar extends StatelessWidget {
  const _OrganizationAvatar({required this.hovered, required this.name});

  final bool hovered;
  final String name;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: AppMotion.reduced(context, AppMotion.fast),
      curve: AppMotion.standard,
      scale: hovered ? 1.06 : 1.0,
      child: OrganizationAvatar(
        name: name,
        size: 48,
        emphasized: hovered,
      ),
    );
  }
}

/// The action area for a card that is not showing the transient accept
/// success beat — a real "View Opportunity" navigation, and (only while
/// `pending`) real Accept/Decline actions. Responsive to this card's own
/// width (not the screen's), since desktop's 2-column grid gives each card
/// meaningfully less width than a single-column mobile layout would.
class _InvitationActions extends StatelessWidget {
  const _InvitationActions({
    super.key,
    required this.invitation,
    required this.isResponding,
    required this.onAccept,
    required this.onDecline,
    required this.onViewOpportunity,
  });

  final InvitationModel invitation;
  final bool isResponding;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onViewOpportunity;

  @override
  Widget build(BuildContext context) {
    if (!invitation.isPending) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SecondaryButton(
          label: 'View Opportunity',
          icon: Icons.open_in_new_rounded,
          height: 40,
          onPressed: onViewOpportunity,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 420;

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SecondaryButton(
                label: 'View Opportunity',
                icon: Icons.open_in_new_rounded,
                height: 40,
                onPressed: onViewOpportunity,
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: 'Decline',
                      height: 44,
                      onPressed: isResponding ? null : onDecline,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    flex: 2,
                    child: PrimaryButton(
                      label: 'Accept Invitation',
                      icon: Icons.check_rounded,
                      height: 44,
                      isLoading: isResponding,
                      onPressed: isResponding ? null : onAccept,
                    ),
                  ),
                ],
              ),
            ],
          );
        }

        // Every button is `Expanded` (never a fixed pixel width) so this
        // row can never overflow, at any container width `>= 420` — the
        // desktop 2-column grid gives each card meaningfully less room
        // than a single-column mobile layout would, and a fixed-width
        // guess previously overflowed there (UI Phase 5 QA).
        return Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: 'View Opportunity',
                icon: Icons.open_in_new_rounded,
                height: 40,
                onPressed: onViewOpportunity,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: SecondaryButton(
                label: 'Decline',
                height: 40,
                onPressed: isResponding ? null : onDecline,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              flex: 2,
              child: PrimaryButton(
                label: 'Accept Invitation',
                icon: Icons.check_rounded,
                height: 40,
                isLoading: isResponding,
                onPressed: isResponding ? null : onAccept,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A brief, one-shot celebratory beat shown right after a real
/// backend-confirmed Accept, before this screen's own preserved redirect
/// to Opportunity Details/Apply fires. Reuses [AppAnimatedStatusIcon] — the
/// same shared success-reveal primitive already used for other
/// backend-confirmed successes elsewhere in the app.
class _AcceptSuccessPanel extends StatelessWidget {
  const _AcceptSuccessPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      key: const ValueKey('accept-success'),
      children: [
        AppAnimatedStatusIcon(
          icon: Icons.check_circle_rounded,
          color: AppColors.success,
          backgroundColor: AppColors.successBackground,
          size: 24,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            'Invitation accepted — taking you to the opportunity…',
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _InvitationsSkeleton extends StatelessWidget {
  const _InvitationsSkeleton({required this.tier});

  final _ScreenTier tier;

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = tier == _ScreenTier.mobile
        ? AppSpacing.screenHorizontal
        : AppSpacing.xl;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 84, color: AppColors.primaryContainer.withValues(alpha: 0.4)),
          Padding(
            padding: EdgeInsets.all(horizontalPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppSkeleton(height: 68, borderRadius: AppRadius.largeRadius),
                const SizedBox(height: AppSpacing.lg),
                const AppSkeleton(height: 44, borderRadius: AppRadius.pillRadius),
                const SizedBox(height: AppSpacing.lg),
                const _InvitationCardSkeleton(),
                const SizedBox(height: AppSpacing.sm),
                const _InvitationCardSkeleton(),
                const SizedBox(height: AppSpacing.sm),
                const _InvitationCardSkeleton(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A higher-fidelity skeleton shaped like the real card above, rather than
/// the generic [AppCardSkeleton] — a round avatar block, a badge+name
/// block, a title block, and an action-row block.
class _InvitationCardSkeleton extends StatelessWidget {
  const _InvitationCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.largeRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppSkeleton(width: 44, height: 44, borderRadius: AppRadius.pillRadius),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppSkeleton(width: 70, height: 14, borderRadius: AppRadius.pillRadius),
                    const SizedBox(height: 6),
                    const AppSkeleton(width: 140, height: 14),
                  ],
                ),
              ),
              const AppSkeleton(width: 64, height: 20, borderRadius: AppRadius.pillRadius),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const AppSkeleton(height: 20, width: 220),
          const SizedBox(height: AppSpacing.sm),
          const AppSkeleton(height: 12, width: 140),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              const AppSkeleton(width: 100, height: 40, borderRadius: AppRadius.mediumRadius),
              const Spacer(),
              const AppSkeleton(width: 90, height: 40, borderRadius: AppRadius.mediumRadius),
              const SizedBox(width: AppSpacing.xs),
              const AppSkeleton(width: 130, height: 40, borderRadius: AppRadius.mediumRadius),
            ],
          ),
        ],
      ),
    );
  }
}
