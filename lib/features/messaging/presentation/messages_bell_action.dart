import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_provider.dart';
import '../../../providers/conversations_provider.dart';
import '../../../routes/app_routes.dart';

/// A message icon `AppBar` action with an unread-count badge (Messaging
/// MVP) — mirrors [NotificationBellAction] exactly, backed by the one
/// shared [ConversationsProvider] instead of `NotificationProvider`.
/// Present on both Student Home and Organization Home (never Admin —
/// there is no Admin side to this MVP's messaging).
class MessagesBellAction extends StatelessWidget {
  const MessagesBellAction({super.key});

  @override
  Widget build(BuildContext context) {
    final unreadCount = context
        .watch<ConversationsProvider>()
        .totalUnreadCount;
    final role = context.watch<AuthProvider>().user?.role;
    final destination = role == 'organization'
        ? AppRoutes.organizationMessages
        : AppRoutes.studentMessages;

    return IconButton(
      tooltip: 'Messages',
      onPressed: () => context.push(destination),
      icon: Badge(
        isLabelVisible: unreadCount > 0,
        label: Text('$unreadCount'),
        child: const Icon(Icons.chat_bubble_outline_rounded),
      ),
    );
  }
}
