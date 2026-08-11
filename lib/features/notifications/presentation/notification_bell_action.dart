import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../providers/notification_provider.dart';
import '../../../routes/app_routes.dart';

/// A notification bell `AppBar` action with an unread-count badge —
/// identical on every Home screen (Student/Organization/Admin), backed by
/// the one shared `NotificationProvider` (see that class's own doc comment
/// on why a single provider/widget serves every role here instead of a
/// per-role variant). The badge hides entirely at zero unread rather than
/// showing an empty/zero badge.
class NotificationBellAction extends StatelessWidget {
  const NotificationBellAction({super.key});

  @override
  Widget build(BuildContext context) {
    final unreadCount = context.watch<NotificationProvider>().unreadCount;

    return IconButton(
      tooltip: 'Notifications',
      onPressed: () => context.push(AppRoutes.notifications),
      icon: Badge(
        isLabelVisible: unreadCount > 0,
        label: Text('$unreadCount'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
