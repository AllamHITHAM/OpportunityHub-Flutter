import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/notification_model.dart';
import '../../../providers/notification_provider.dart';
import 'notification_display.dart';

const _tabletBreakpoint = 600.0;
const _desktopBreakpoint = 1200.0;

enum _ScreenTier { mobile, tablet, desktop }

_ScreenTier _tierFor(double width) {
  if (width >= _desktopBreakpoint) return _ScreenTier.desktop;
  if (width >= _tabletBreakpoint) return _ScreenTier.tablet;
  return _ScreenTier.mobile;
}

/// The local, UI-only read-state filter -- never sent anywhere, purely a
/// client-side predicate over the already-fully-loaded list (the backend
/// has no pagination/filter params to call through to; see
/// `NotificationRepository`'s own doc comment).
enum _ReadFilter { all, unread, read }

/// The real `notification.type` -> icon mapping (UI Phase 9). Every value
/// the enum can hold gets a real icon (including the two never-yet-created
/// values `system`/`organization`, since they're still valid data the
/// backend could send); an entirely unrecognized future value falls back
/// to a generic bell, never a fabricated/arbitrary one. Deliberately no
/// per-type *color* here -- see `_NotificationCard`'s own doc comment on
/// why color is driven by real read-state instead, not decorative
/// per-category tinting.
IconData _iconForType(String type) {
  switch (type) {
    case 'application':
      return Icons.description_outlined;
    case 'interview':
      return Icons.event_outlined;
    case 'assessment':
      return Icons.quiz_outlined;
    case 'offer':
      return Icons.card_giftcard_outlined;
    case 'opportunity':
      return Icons.mail_outline_rounded;
    case 'organization':
      return Icons.business_outlined;
    case 'system':
      return Icons.info_outline_rounded;
    case 'message':
      return Icons.chat_bubble_outline_rounded;
    default:
      return Icons.notifications_outlined;
  }
}

/// A premium Notifications Center (UI Phase 9) driven entirely by real
/// backend data. Shared across all three roles by pre-existing
/// architecture (see `NotificationProvider`'s own doc comment on why one
/// provider/endpoint serves everyone) -- every choice here is therefore
/// deliberately role-neutral presentation, not new Student/Organization/
/// Admin feature work. Read-only plus the two existing real actions
/// (mark-one-read, mark-all-read); no delete, no pagination -- the backend
/// has neither (`GET /notifications` returns the user's complete list,
/// unpaginated, newest-first).
///
/// **Audited, deliberately preserved gaps:**
/// - No per-notification unread-count or type-filter endpoint exists --
///   both are computed locally from the already-fully-loaded list, which
///   is exactly what the backend already returns in one call.
/// - `action_url` is the sole navigation source of truth (never inferred
///   from `type`/`id`) and is validated (`isNavigableActionUrl`) before
///   ever reaching GoRouter -- unchanged from the pre-existing
///   implementation, which already got this right.
class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;
  _ReadFilter _filter = _ReadFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NotificationProvider>().load();
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
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  /// Marks [notification] as read (only if it isn't already), then
  /// navigates to its `action_url` regardless of whether the mark-read
  /// call succeeded — a failed mark-read must never permanently block
  /// navigation, it only leaves the notification visibly unread and shows
  /// a safe error.
  Future<void> _handleTap(NotificationModel notification) async {
    final provider = context.read<NotificationProvider>();

    if (!notification.isRead) {
      final success = await provider.markAsRead(notification.id);
      if (!mounted) return;
      if (!success && provider.actionErrorMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
      }
    }

    _navigateIfPossible(notification.actionUrl);
  }

  /// `action_url` is the sole source of truth for where a notification
  /// navigates — never inferred from `type`/`id`. A `null`/blank/
  /// non-app-relative value silently does nothing (the tap already marked
  /// the notification read, which is the only effect it has). A value that
  /// looks navigable but that GoRouter still can't resolve is caught here
  /// rather than crashing the app.
  void _navigateIfPossible(String? actionUrl) {
    if (!isNavigableActionUrl(actionUrl)) return;
    if (!mounted) return;

    try {
      context.push(actionUrl!);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open this notification.')),
      );
    }
  }

  Future<void> _markAllAsRead(NotificationProvider provider) async {
    final success = await provider.markAllAsRead();
    if (!mounted) return;
    if (!success && provider.actionErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
    }
  }

  Future<void> _markOneAsRead(NotificationProvider provider, int id) async {
    final success = await provider.markAsRead(id);
    if (!mounted) return;
    if (!success && provider.actionErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
    }
  }

  /// Confirms, then permanently deletes [notification] (Phase 9.1) --
  /// inbox cleanup only. Never called as a side effect of tapping the
  /// card itself (see `_NotificationCard`'s own overflow menu, which stops
  /// the tap from ever reaching the card's `onTap`/navigation).
  Future<void> _confirmDelete(
    NotificationProvider provider,
    NotificationModel notification,
  ) async {
    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Delete notification?',
      message:
          'This removes the notification from your inbox. It will not '
          'affect the related application or activity.',
      confirmLabel: 'Delete',
      type: AppConfirmationType.danger,
    );
    if (!confirmed || !mounted) return;

    final success = await provider.deleteNotification(notification.id);
    if (!mounted) return;
    if (!success && provider.actionErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
    }
  }

  Future<void> _confirmClearRead(NotificationProvider provider) async {
    final confirmed = await showAppConfirmationDialog(
      context,
      title: 'Clear read notifications?',
      message:
          "This removes all notifications you've already read. Unread "
          'notifications will stay in your inbox.',
      confirmLabel: 'Clear Read',
      type: AppConfirmationType.danger,
    );
    if (!confirmed || !mounted) return;

    final success = await provider.clearRead();
    if (!mounted) return;
    if (!success && provider.actionErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.actionErrorMessage!)));
    }
  }

  List<NotificationModel> _applyFilter(List<NotificationModel> notifications) {
    switch (_filter) {
      case _ReadFilter.unread:
        return notifications.where((n) => !n.isRead).toList();
      case _ReadFilter.read:
        return notifications.where((n) => n.isRead).toList();
      case _ReadFilter.all:
        return notifications;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();
    final tier = _tierFor(MediaQuery.sizeOf(context).width);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          const ThemeToggleButton(),
          // A manual refresh action is genuinely useful where pull-to-
          // refresh isn't a natural gesture (Web/desktop) -- kept off the
          // narrow mobile AppBar (which already has pull-to-refresh) to
          // avoid crowding it alongside "Mark all as read".
          if (tier != _ScreenTier.mobile)
            IconButton(
              onPressed: provider.isLoading
                  ? null
                  : () => provider.load(forceRefresh: true),
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
            ),
          if (provider.hasUnread)
            TextButton(
              onPressed: provider.isMarkingAll
                  ? null
                  : () => _markAllAsRead(provider),
              child: provider.isMarkingAll
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      ),
                    )
                  : const Text('Mark all as read'),
            ),
          // Secondary inbox management, deliberately tucked into an
          // overflow menu rather than sitting beside the primary "Mark
          // all as read" action -- and only shown once there's actually
          // something real to clear.
          if (provider.notifications.any((n) => n.isRead))
            PopupMenuButton<void>(
              tooltip: 'More options',
              icon: const Icon(Icons.more_vert_rounded),
              itemBuilder: (context) => [
                PopupMenuItem(
                  child: const Text('Clear read notifications'),
                  onTap: () => Future.microtask(() => _confirmClearRead(provider)),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(child: _buildBody(provider, tier)),
    );
  }

  Widget _buildBody(NotificationProvider provider, _ScreenTier tier) {
    if (provider.isLoading && provider.notifications.isEmpty) {
      return const _NotificationsSkeleton();
    }

    if (provider.errorMessage != null && provider.notifications.isEmpty) {
      return AppErrorView(
        message: provider.errorMessage!,
        onRetry: () => provider.load(forceRefresh: true),
      );
    }

    final horizontalPadding = tier == _ScreenTier.mobile
        ? AppSpacing.screenHorizontal
        : AppSpacing.xl;

    if (provider.notifications.isEmpty) {
      return SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Column(
          children: [
            _Stagger(controller: _entranceController, index: 0, count: 1, child: const _PageHeader()),
            const SizedBox(
              height: 440,
              child: AppEmptyView(
                icon: Icons.notifications_none_rounded,
                title: "You're All Caught Up",
                message:
                    'New updates about your applications and account '
                    'activity will appear here.',
              ),
            ),
          ],
        ),
      );
    }

    final allNotifications = provider.notifications;
    final filtered = _applyFilter(allNotifications);
    final maxWidth = tier == _ScreenTier.desktop ? 1100.0 : 760.0;

    return RefreshIndicator(
      onRefresh: () => provider.load(forceRefresh: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Stagger(controller: _entranceController, index: 0, count: 4, child: const _PageHeader()),
                const SizedBox(height: AppSpacing.md),
                _Stagger(
                  controller: _entranceController,
                  index: 1,
                  count: 4,
                  child: _NotificationsLayout(
                    tier: tier,
                    allNotifications: allNotifications,
                    filtered: filtered,
                    filter: _filter,
                    onFilterChanged: (value) => setState(() => _filter = value),
                    provider: provider,
                    entranceController: _entranceController,
                    onTap: _handleTap,
                    onMarkOneAsRead: (id) => _markOneAsRead(provider, id),
                    onDelete: (notification) => _confirmDelete(provider, notification),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades and slides a section in as part of the staged entrance — a
/// private per-file copy of the same small helper other premium screens
/// this session define.
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

class _PageHeader extends StatelessWidget {
  const _PageHeader();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xs),
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
              Icons.notifications_outlined,
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
                  'Notifications',
                  style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  'Stay updated on applications, assessments, interviews, '
                  'offers, and account activity.',
                  style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Main feed + a real activity summary sidebar on desktop, stacked on
/// mobile/tablet -- the sidebar only ever shows already-loaded, real
/// derived counts (never decorative filler).
class _NotificationsLayout extends StatelessWidget {
  const _NotificationsLayout({
    required this.tier,
    required this.allNotifications,
    required this.filtered,
    required this.filter,
    required this.onFilterChanged,
    required this.provider,
    required this.entranceController,
    required this.onTap,
    required this.onMarkOneAsRead,
    required this.onDelete,
  });

  final _ScreenTier tier;
  final List<NotificationModel> allNotifications;
  final List<NotificationModel> filtered;
  final _ReadFilter filter;
  final ValueChanged<_ReadFilter> onFilterChanged;
  final NotificationProvider provider;
  final AnimationController entranceController;
  final ValueChanged<NotificationModel> onTap;
  final ValueChanged<int> onMarkOneAsRead;
  final ValueChanged<NotificationModel> onDelete;

  @override
  Widget build(BuildContext context) {
    final feed = _NotificationFeed(
      tier: tier,
      allNotifications: allNotifications,
      filtered: filtered,
      filter: filter,
      onFilterChanged: onFilterChanged,
      provider: provider,
      entranceController: entranceController,
      onTap: onTap,
      onMarkOneAsRead: onMarkOneAsRead,
      onDelete: onDelete,
    );

    if (tier != _ScreenTier.desktop) return feed;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: feed),
        const SizedBox(width: AppSpacing.lg),
        Expanded(flex: 2, child: _ActivitySummaryCard(notifications: allNotifications)),
      ],
    );
  }
}

class _NotificationFeed extends StatelessWidget {
  const _NotificationFeed({
    required this.tier,
    required this.allNotifications,
    required this.filtered,
    required this.filter,
    required this.onFilterChanged,
    required this.provider,
    required this.entranceController,
    required this.onTap,
    required this.onMarkOneAsRead,
    required this.onDelete,
  });

  final _ScreenTier tier;
  final List<NotificationModel> allNotifications;
  final List<NotificationModel> filtered;
  final _ReadFilter filter;
  final ValueChanged<_ReadFilter> onFilterChanged;
  final NotificationProvider provider;
  final AnimationController entranceController;
  final ValueChanged<NotificationModel> onTap;
  final ValueChanged<int> onMarkOneAsRead;
  final ValueChanged<NotificationModel> onDelete;

  @override
  Widget build(BuildContext context) {
    final unreadCount = allNotifications.where((n) => !n.isRead).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryRow(total: allNotifications.length, unread: unreadCount),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            _FilterChip(
              key: const Key('notification-filter-all'),
              label: 'All',
              selected: filter == _ReadFilter.all,
              onTap: () => onFilterChanged(_ReadFilter.all),
            ),
            _FilterChip(
              key: const Key('notification-filter-unread'),
              label: 'Unread',
              selected: filter == _ReadFilter.unread,
              onTap: () => onFilterChanged(_ReadFilter.unread),
            ),
            _FilterChip(
              key: const Key('notification-filter-read'),
              label: 'Read',
              selected: filter == _ReadFilter.read,
              onTap: () => onFilterChanged(_ReadFilter.read),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AnimatedSize(
          duration: AppMotion.reduced(context, AppMotion.normal),
          alignment: Alignment.topCenter,
          curve: Curves.easeOutCubic,
          child: AnimatedSwitcher(
            duration: AppMotion.reduced(context, AppMotion.normal),
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: filtered.isEmpty
                ? _NoMatchState(key: ValueKey('empty-$filter'), filter: filter)
                : _GroupedNotificationList(
                    key: ValueKey('list-$filter'),
                    tier: tier,
                    notifications: filtered,
                    provider: provider,
                    entranceController: entranceController,
                    onTap: onTap,
                    onMarkOneAsRead: onMarkOneAsRead,
                    onDelete: onDelete,
                  ),
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.total, required this.unread});

  final int total;
  final int unread;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: AppRadius.largeRadius,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              total == 1 ? '1 notification' : '$total notifications',
              style: textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: AppMotion.reduced(context, AppMotion.normal),
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: unread > 0
                ? StatusChip(
                    key: ValueKey('unread-$unread'),
                    label: unread == 1 ? '1 unread' : '$unread unread',
                    type: AppStatusType.info,
                  )
                : Text(
                    "You're all caught up.",
                    key: const ValueKey('all-read'),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.reduced(context, AppMotion.fast);

    return Material(
      color: AppColors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.pillRadius,
        child: AnimatedContainer(
          duration: duration,
          curve: AppMotion.standard,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.surfaceVariant,
            borderRadius: AppRadius.pillRadius,
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.onPrimary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _NoMatchState extends StatelessWidget {
  const _NoMatchState({super.key, required this.filter});

  final _ReadFilter filter;

  @override
  Widget build(BuildContext context) {
    final message = switch (filter) {
      _ReadFilter.unread => "You're all caught up -- no unread notifications.",
      _ReadFilter.read => 'No read notifications yet.',
      _ReadFilter.all => 'No notifications match this filter.',
    };

    return AppEmptyView(
      icon: Icons.notifications_none_rounded,
      message: message,
      compact: true,
    );
  }
}

/// Real, presentation-only date grouping (Today/Yesterday/Earlier) over
/// the already-ordered (newest-first) list -- never re-sorts, only inserts
/// section headers, so the backend/provider's own ordering is preserved
/// exactly (see `notificationDateBucket`'s own doc comment).
class _GroupedNotificationList extends StatelessWidget {
  const _GroupedNotificationList({
    super.key,
    required this.tier,
    required this.notifications,
    required this.provider,
    required this.entranceController,
    required this.onTap,
    required this.onMarkOneAsRead,
    required this.onDelete,
  });

  final _ScreenTier tier;
  final List<NotificationModel> notifications;
  final NotificationProvider provider;
  final AnimationController entranceController;
  final ValueChanged<NotificationModel> onTap;
  final ValueChanged<int> onMarkOneAsRead;
  final ValueChanged<NotificationModel> onDelete;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    String? lastBucket;
    final children = <Widget>[];

    for (final notification in notifications) {
      final time = notificationDisplayTime(notification) ?? now;
      final bucket = notificationDateBucket(time, now: now);
      if (bucket != lastBucket) {
        if (lastBucket != null) children.add(const SizedBox(height: AppSpacing.sm));
        children.add(_BucketHeader(label: bucket));
        lastBucket = bucket;
      }
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: _NotificationCard(
            notification: notification,
            isBusy: provider.isBusy(notification.id),
            showExplicitMarkAsRead: tier == _ScreenTier.desktop,
            onTap: () => onTap(notification),
            onMarkAsRead: () => onMarkOneAsRead(notification.id),
            onDelete: () => onDelete(notification),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _BucketHeader extends StatelessWidget {
  const _BucketHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xxs),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// One notification row. Unread state is communicated through more than
/// color alone: a tinted background *and* a small unread dot *and* a
/// bolder title. The type icon's own tint is tied to real read-state
/// (primary when unread, muted when read) rather than an arbitrary
/// per-category color -- Part 8's own caution against "assigning
/// arbitrary colors to unknown types" is best honored by not inventing a
/// seven-color palette for a field (`type`) whose values carry no
/// inherent sentiment.
class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.isBusy,
    required this.showExplicitMarkAsRead,
    required this.onTap,
    required this.onMarkAsRead,
    required this.onDelete,
  });

  final NotificationModel notification;
  final bool isBusy;
  final bool showExplicitMarkAsRead;
  final VoidCallback onTap;
  final VoidCallback onMarkAsRead;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isUnread = !notification.isRead;
    final time = notificationDisplayTime(notification);

    return Semantics(
      label:
          '${isUnread ? "Unread. " : ""}${notification.title}. '
          '${notification.message}',
      child: AppCard(
        interactive: true,
        onTap: isBusy ? null : onTap,
        backgroundColor: isUnread ? AppColors.primaryContainer.withValues(alpha: 0.35) : AppColors.card,
        borderColor: isUnread ? AppColors.primary.withValues(alpha: 0.3) : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isUnread ? AppColors.primaryContainer : AppColors.surfaceVariant,
              ),
              child: Icon(
                _iconForType(notification.type),
                size: 18,
                color: isUnread ? AppColors.primaryDark : AppColors.textMuted,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (isUnread) ...[
                        const SizedBox(width: AppSpacing.xxs),
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    notification.message,
                    style: textTheme.bodyMedium?.copyWith(
                      color: isUnread ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Row(
                    children: [
                      if (time != null)
                        Text(
                          notificationRelativeTime(time),
                          style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
                        ),
                      const Spacer(),
                      if (isBusy)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else ...[
                        if (showExplicitMarkAsRead && isUnread)
                          TextButton(
                            onPressed: onMarkAsRead,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Mark as read', style: TextStyle(fontSize: 12)),
                          ),
                        _NotificationCardMenu(
                          isUnread: isUnread,
                          onMarkAsRead: onMarkAsRead,
                          onDelete: onDelete,
                        ),
                      ],
                    ],
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

/// The per-card three-dot overflow menu (⋯) — "Mark as read" (only when
/// unread) plus "Delete notification". Deliberately a *separate* widget
/// (not inline in [_NotificationCard]) so its `IconButton` owns its own
/// gesture handling and never bubbles a tap up into the ancestor
/// `AppCard`'s own `onTap` — opening the menu (or tapping a menu item)
/// must never trigger the card's navigation.
class _NotificationCardMenu extends StatelessWidget {
  const _NotificationCardMenu({
    required this.isUnread,
    required this.onMarkAsRead,
    required this.onDelete,
  });

  final bool isUnread;
  final VoidCallback onMarkAsRead;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<void>(
      tooltip: 'Notification options',
      icon: Icon(Icons.more_vert_rounded, size: 18, color: AppColors.textMuted),
      padding: EdgeInsets.zero,
      splashRadius: 18,
      itemBuilder: (context) => [
        if (isUnread)
          PopupMenuItem<void>(
            child: const Text('Mark as read'),
            onTap: () => Future.microtask(onMarkAsRead),
          ),
        PopupMenuItem<void>(
          child: const Text('Delete notification'),
          onTap: () => Future.microtask(onDelete),
        ),
      ],
    );
  }
}

/// Real, derived-only activity numbers -- total loaded, unread, and a
/// per-type unread breakdown for whichever real types are actually
/// present. Desktop-only (see `_NotificationsLayout`) -- never an empty
/// decorative column.
class _ActivitySummaryCard extends StatelessWidget {
  const _ActivitySummaryCard({required this.notifications});

  final List<NotificationModel> notifications;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final unread = notifications.where((n) => !n.isRead);
    final unreadByType = <String, int>{};
    for (final notification in unread) {
      unreadByType[notification.type] = (unreadByType[notification.type] ?? 0) + 1;
    }
    final typeEntries = unreadByType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: AppRadius.largeRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Activity Summary',
            style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          _SummaryStatRow(
            icon: Icons.notifications_outlined,
            label: 'Total',
            value: notifications.length,
          ),
          const SizedBox(height: AppSpacing.xs),
          _SummaryStatRow(
            icon: Icons.mark_email_unread_outlined,
            label: 'Unread',
            value: unread.length,
            valueColor: unread.isEmpty ? null : AppColors.primary,
          ),
          if (typeEntries.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Divider(color: AppColors.border, height: 1),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Unread by type',
              style: textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final entry in typeEntries)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: _SummaryStatRow(
                  icon: _iconForType(entry.key),
                  label: notificationTypeLabel(entry.key),
                  value: entry.value,
                  compact: true,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SummaryStatRow extends StatelessWidget {
  const _SummaryStatRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color? valueColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Icon(icon, size: compact ? 14 : 18, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            label,
            style: (compact ? textTheme.bodySmall : textTheme.bodyMedium)?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Text(
          '$value',
          style: (compact ? textTheme.labelLarge : textTheme.titleMedium)?.copyWith(
            fontWeight: FontWeight.w800,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _NotificationsSkeleton extends StatelessWidget {
  const _NotificationsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(AppSpacing.screenHorizontal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: AppSpacing.lg),
          AppSkeletonList(count: 5),
        ],
      ),
    );
  }
}
