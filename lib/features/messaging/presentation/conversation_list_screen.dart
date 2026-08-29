import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/conversation_model.dart';
import '../../../providers/conversations_provider.dart';
import '../../../routes/app_routes.dart';
import '../../notifications/presentation/notification_display.dart';

const _maxContentWidth = 800.0;

/// The real, shared conversation-list UI (Messaging MVP) — used by both
/// [StudentMessagesScreen] and [OrganizationMessagesScreen] rather than two
/// near-identical implementations, matching the phase spec's own "keep one
/// shared Conversation resource where possible" instruction on the backend
/// side. [otherPartyName]/[opportunity.title]/last-message preview/
/// timestamp/unread badge are exactly the fields
/// `ConversationController::summarize()` already returns — nothing here is
/// computed or guessed client-side.
class _ConversationListView extends StatefulWidget {
  const _ConversationListView({
    required this.title,
    required this.emptyMessage,
    required this.conversationPath,
  });

  final String title;
  final String emptyMessage;
  final String Function(int conversationId) conversationPath;

  @override
  State<_ConversationListView> createState() => _ConversationListViewState();
}

class _ConversationListViewState extends State<_ConversationListView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ConversationsProvider>().loadConversations();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ConversationsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: const [ThemeToggleSurface()],
      ),
      body: SafeArea(child: _buildBody(provider)),
    );
  }

  Widget _buildBody(ConversationsProvider provider) {
    if (provider.isLoadingList && provider.conversations.isEmpty) {
      return const AppSkeletonList();
    }

    if (provider.listErrorMessage != null && provider.conversations.isEmpty) {
      return AppErrorView(
        message: provider.listErrorMessage!,
        onRetry: () => provider.loadConversations(forceRefresh: true),
      );
    }

    if (provider.conversations.isEmpty) {
      return AppEmptyView(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'No Messages Yet',
        message: widget.emptyMessage,
      );
    }

    return RefreshIndicator(
      onRefresh: () => provider.loadConversations(forceRefresh: true),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: constraints.maxWidth >= _maxContentWidth
                  ? AppSpacing.xl
                  : AppSpacing.screenHorizontal,
              vertical: AppSpacing.md,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final conversation in provider.conversations) ...[
                      _ConversationTile(
                        conversation: conversation,
                        onTap: () => context.push(
                          widget.conversationPath(conversation.id),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.onTap});

  final ConversationSummaryModel conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final unread = conversation.unreadCount ?? 0;
    final lastMessage = conversation.lastMessage;

    return AppCard(
      onTap: onTap,
      interactive: true,
      borderColor: unread > 0 ? AppColors.primary : AppColors.secondaryLight,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAvatar(name: conversation.otherPartyName, size: 44),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        conversation.otherPartyName,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: unread > 0
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      notificationRelativeTime(conversation.updatedAt),
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
                if (conversation.opportunity != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    conversation.opportunity!.title,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xxs),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        lastMessage == null
                            ? 'No messages yet'
                            : (lastMessage.isOwnMessage ? 'You: ' : '') +
                                  lastMessage.body,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                        style: textTheme.bodyMedium?.copyWith(
                          color: unread > 0
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontWeight: unread > 0
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (unread > 0) ...[
                      const SizedBox(width: AppSpacing.xs),
                      _UnreadBadge(count: unread),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      constraints: const BoxConstraints(minWidth: 20),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.onPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Student-only conversation list — see [_ConversationListView].
class StudentMessagesScreen extends StatelessWidget {
  const StudentMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _ConversationListView(
      title: 'Messages',
      emptyMessage:
          'When an organization messages you about an opportunity, '
          'you\'ll see the conversation here.',
      conversationPath: AppRoutes.studentConversation,
    );
  }
}

/// Organization-only conversation list — see [_ConversationListView].
class OrganizationMessagesScreen extends StatelessWidget {
  const OrganizationMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _ConversationListView(
      title: 'Messages',
      emptyMessage:
          'Message a candidate from their profile to start a '
          'conversation.',
      conversationPath: AppRoutes.organizationConversation,
    );
  }
}
