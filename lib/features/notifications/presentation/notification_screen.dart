import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/notification_model.dart';
import '../../../providers/notification_provider.dart';
import 'notification_display.dart';

/// Shared across all three roles — see `NotificationProvider`'s own doc
/// comment on why one screen/provider serves everyone instead of a
/// per-role split. Read-only plus the two existing mark-read actions; no
/// delete, no pagination (the backend has neither — see
/// `NotificationRepository`).
class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  @override
  void initState() {
    super.initState();
    // Deferred to the post-frame callback — see
    // StudentOpportunitiesScreen.initState for why calling this directly
    // here would violate Flutter's build-phase constraints.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NotificationProvider>().load();
    });
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (provider.hasUnread)
            TextButton(
              onPressed: provider.isMarkingAll
                  ? null
                  : () => _markAllAsRead(provider),
              child: provider.isMarkingAll
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      ),
                    )
                  : const Text('Mark all as read'),
            ),
        ],
      ),
      body: SafeArea(child: _buildBody(provider)),
    );
  }

  Widget _buildBody(NotificationProvider provider) {
    if (provider.isLoading && provider.notifications.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.screenHorizontal),
        child: AppSkeletonList(),
      );
    }

    if (provider.errorMessage != null && provider.notifications.isEmpty) {
      return AppErrorView(
        message: provider.errorMessage!,
        onRetry: () => provider.load(forceRefresh: true),
      );
    }

    if (provider.notifications.isEmpty) {
      return const AppEmptyView(
        title: 'No Notifications',
        message: "You're all caught up.",
        icon: Icons.notifications_none_rounded,
      );
    }

    return RefreshIndicator(
      onRefresh: () => provider.load(forceRefresh: true),
      child: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.screenHorizontal),
        itemCount: provider.notifications.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final notification = provider.notifications[index];
          return _NotificationCard(
            notification: notification,
            isBusy: provider.isBusy(notification.id),
            onTap: () => _handleTap(notification),
          );
        },
      ),
    );
  }
}

/// One notification row. Unread notifications get a tinted background and
/// a small dot indicator — the only visual distinction, deliberately kept
/// simple (see this phase's own scope notes on avoiding a heavy custom
/// design system; final visual polish is a later phase).
class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.isBusy,
    required this.onTap,
  });

  final NotificationModel notification;
  final bool isBusy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isUnread = !notification.isRead;
    final time = notificationDisplayTime(notification);

    return AppCard(
      onTap: isBusy ? null : onTap,
      backgroundColor: isUnread ? AppColors.primaryContainer : AppColors.card,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isUnread) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  notification.title,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(notification.message, style: textTheme.bodyMedium),
                if (time != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    '${formatDate(time)} ${formatTime(time)}',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isBusy) ...[
            const SizedBox(width: AppSpacing.xs),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
      ),
    );
  }
}
