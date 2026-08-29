import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/message_model.dart';
import '../../../providers/conversations_provider.dart';

const _maxContentWidth = 800.0;

/// A polling interval only ever active while this screen is on-screen
/// (section 26 of the phase spec: "optional lightweight polling ONLY
/// while Conversation screen open if safe" — no WebSockets/Reverb, no
/// global/background polling). Started in [initState], cancelled in
/// [dispose] — never runs a moment longer than the screen itself is
/// mounted.
const _pollInterval = Duration(seconds: 8);

/// The shared Conversation chat UI (Messaging MVP) — reached from either
/// [StudentMessagesScreen] or [OrganizationMessagesScreen]'s conversation
/// list, or directly via a notification's `action_url`. One real,
/// role-agnostic screen: [MessageModel.isOwnMessage] (computed
/// server-side) already tells this screen everything it needs to align
/// bubbles/show sender distinction, without needing to separately know
/// whether the viewer is the Organization or the Student.
///
/// No fake typing animation, no fake delivered/read ticks — this MVP's
/// backend has no typing-indicator concept at all, and the only read
/// signal that exists ([MessageModel.readAt]) is real but not surfaced as
/// a per-message tick here (see this phase's own final report on why: a
/// tick implies delivery/read *confirmation* semantics this MVP never
/// promised — the conversation list's own real unread badge is the
/// user-facing read-state signal instead).
class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.conversationId});

  final int conversationId;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _bodyController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await context.read<ConversationsProvider>().loadConversation(
        widget.conversationId,
      );
      _scrollToBottom();
    });
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (!mounted) return;
      context.read<ConversationsProvider>().loadConversation(
        widget.conversationId,
        forceRefresh: true,
      );
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _bodyController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final body = _bodyController.text.trim();
    if (body.isEmpty) return;

    final provider = context.read<ConversationsProvider>();
    _bodyController.clear();
    final sent = await provider.sendMessage(widget.conversationId, body);
    if (!mounted) return;

    if (sent) {
      _scrollToBottom();
    } else if (provider.sendErrorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.sendErrorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ConversationsProvider>();
    final conversation = provider.selectedConversation;
    final isThisOne = conversation?.id == widget.conversationId;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isThisOne ? conversation!.otherPartyName : 'Conversation'),
            if (isThisOne && conversation!.opportunity != null)
              Text(
                conversation.opportunity!.title,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
          ],
        ),
        actions: const [ThemeToggleSurface()],
      ),
      body: SafeArea(child: _buildBody(provider, isThisOne)),
    );
  }

  Widget _buildBody(ConversationsProvider provider, bool isThisOne) {
    if (provider.isLoadingDetails && !isThisOne) {
      return const AppLoading();
    }

    if (provider.detailsErrorMessage != null && !isThisOne) {
      return AppErrorView(
        message: provider.detailsErrorMessage!,
        onRetry: () => provider.loadConversation(
          widget.conversationId,
          forceRefresh: true,
        ),
      );
    }

    if (!isThisOne) {
      return const AppEmptyView(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'Conversation Not Found',
        message: 'This conversation is no longer available.',
      );
    }

    final conversation = provider.selectedConversation!;

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => provider.loadConversation(
              widget.conversationId,
              forceRefresh: true,
            ),
            child: conversation.messages.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      AppEmptyView(
                        icon: Icons.chat_bubble_outline_rounded,
                        title: 'No Messages Yet',
                        message: 'Send the first message below.',
                        compact: true,
                      ),
                    ],
                  )
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _maxContentWidth,
                      ),
                      child: ListView.builder(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.screenHorizontal,
                          vertical: AppSpacing.md,
                        ),
                        itemCount: conversation.messages.length,
                        itemBuilder: (context, index) =>
                            _MessageBubble(message: conversation.messages[index]),
                      ),
                    ),
                  ),
          ),
        ),
        _Composer(controller: _bodyController, onSend: _send, provider: provider),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final MessageModel message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isOwn = message.isOwnMessage;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: isOwn
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.75,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: isOwn ? AppColors.primary : AppColors.surfaceVariant,
                borderRadius: AppRadius.largeRadius,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.body,
                    style: textTheme.bodyMedium?.copyWith(
                      color: isOwn
                          ? AppColors.onPrimary
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatTime(message.createdAt),
                    style: textTheme.labelSmall?.copyWith(
                      color: isOwn
                          ? AppColors.onPrimary.withValues(alpha: 0.75)
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.provider,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final ConversationsProvider provider;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.only(
        left: AppSpacing.sm,
        right: AppSpacing.sm,
        top: AppSpacing.sm,
        bottom: AppSpacing.sm + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AppTextField(
                  controller: controller,
                  hint: 'Type a message…',
                  maxLines: 4,
                  minLines: 1,
                  maxLength: 2000,
                  textInputAction: TextInputAction.newline,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              IconButton.filled(
                tooltip: 'Send',
                onPressed: provider.isSendingMessage ? null : onSend,
                icon: provider.isSendingMessage
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
