import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../features/messaging/data/conversation_repository.dart';
import '../models/conversation_model.dart';
import 'auth_provider.dart';

/// Holds the authenticated user's conversation list and single-conversation
/// (detail + messages) state, and exposes send/start actions. One shared
/// provider for both roles — `GET /conversations` and friends are
/// role-agnostic backend endpoints (see `ConversationRepository`'s own doc
/// comment), the same reasoning `NotificationProvider` already follows for
/// its own shared endpoint.
///
/// No WebSockets/Reverb — every refresh here is an explicit call (screen
/// open, after-send, pull-to-refresh), matching this MVP's backend, which
/// has no realtime push either.
class ConversationsProvider extends ChangeNotifier {
  ConversationsProvider({required this.repository, required this._authProvider}) {
    _authProvider.addListener(_handleAuthChanged);
  }

  final ConversationRepository repository;
  final AuthProvider _authProvider;

  List<ConversationSummaryModel> conversations = [];
  bool isLoadingList = false;
  String? listErrorMessage;

  ConversationModel? selectedConversation;
  bool isLoadingDetails = false;
  String? detailsErrorMessage;

  bool isSendingMessage = false;
  String? sendErrorMessage;

  bool isStartingConversation = false;
  String? startErrorMessage;

  /// The in-flight list fetch, if any — guards against concurrent
  /// duplicate requests without preventing an explicit refresh once the
  /// previous fetch has finished. Mirrors `NotificationProvider._pendingLoad`.
  Future<void>? _pendingListFetch;
  int _listLoadGeneration = 0;

  Future<void>? _pendingDetailsFetch;

  /// Which conversation [_pendingDetailsFetch] (or the most recently
  /// completed one) is for — mirrors
  /// `OrganizationApplicationsProvider._pendingListOpportunityId`.
  int? _pendingDetailsConversationId;
  int _detailsLoadGeneration = 0;

  /// The real total unread count across every conversation — powers the
  /// shared `MessagesBellAction` badge, derived from [conversations]
  /// itself (already-loaded, real `unread_count` values), never a
  /// separate fetch.
  int get totalUnreadCount =>
      conversations.fold(0, (sum, c) => sum + (c.unreadCount ?? 0));

  bool get hasUnread => totalUnreadCount > 0;

  void _handleAuthChanged() {
    // A different user may sign in next — don't leak the previous
    // session's conversations into theirs.
    if (!_authProvider.isAuthenticated) {
      reset();
    }
  }

  /// Loads the current user's conversations. Safe to call repeatedly — a
  /// fetch already in flight is reused rather than duplicated; pass
  /// [forceRefresh] to start a fresh one regardless.
  Future<void> loadConversations({bool forceRefresh = false}) {
    if (forceRefresh) {
      _pendingListFetch = null;
    }
    if (_pendingListFetch == null) {
      final generation = ++_listLoadGeneration;
      _pendingListFetch = _performLoadList(generation);
    }
    return _pendingListFetch!;
  }

  Future<void> _performLoadList(int generation) async {
    isLoadingList = true;
    listErrorMessage = null;
    notifyListeners();

    bool stillCurrent() => generation == _listLoadGeneration;

    try {
      final result = await repository.getConversations();
      if (stillCurrent()) {
        conversations = result;
      }
    } on ApiException catch (error) {
      if (stillCurrent()) {
        listErrorMessage = error.message;
      }
    } catch (_) {
      if (stillCurrent()) {
        listErrorMessage = 'Something went wrong. Please try again.';
      }
    } finally {
      if (stillCurrent()) {
        isLoadingList = false;
        _pendingListFetch = null;
      }
      notifyListeners();
    }
  }

  /// Loads one conversation's full message history. Safe to call
  /// repeatedly — a fetch already in flight *for the same conversation* is
  /// reused; a request for a different conversation always starts fresh.
  /// Pass [forceRefresh] to start a fresh one regardless. On success, also
  /// zeroes that conversation's [ConversationSummaryModel.unreadCount] in
  /// the already-loaded [conversations] list locally — opening a
  /// conversation really did just mark its incoming messages read
  /// server-side, so the list's badge must reflect that immediately rather
  /// than only after the next full list reload.
  Future<void> loadConversation(int conversationId, {bool forceRefresh = false}) {
    if (forceRefresh || _pendingDetailsConversationId != conversationId) {
      _pendingDetailsFetch = null;
    }
    _pendingDetailsConversationId = conversationId;
    if (_pendingDetailsFetch == null) {
      final generation = ++_detailsLoadGeneration;
      _pendingDetailsFetch = _performLoadDetails(conversationId, generation);
    }
    return _pendingDetailsFetch!;
  }

  Future<void> _performLoadDetails(int conversationId, int generation) async {
    isLoadingDetails = true;
    detailsErrorMessage = null;
    notifyListeners();

    bool stillCurrent() => generation == _detailsLoadGeneration;

    try {
      final result = await repository.getConversation(conversationId);
      if (stillCurrent()) {
        selectedConversation = result;
        _zeroUnreadLocally(conversationId);
      }
    } on ApiException catch (error) {
      if (stillCurrent()) {
        detailsErrorMessage = error.message;
      }
    } catch (_) {
      if (stillCurrent()) {
        detailsErrorMessage = 'Something went wrong. Please try again.';
      }
    } finally {
      if (stillCurrent()) {
        isLoadingDetails = false;
        _pendingDetailsFetch = null;
      }
      notifyListeners();
    }
  }

  void _zeroUnreadLocally(int conversationId) {
    final index = conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) return;
    final current = conversations[index];
    if ((current.unreadCount ?? 0) == 0) return;

    final updated = [...conversations];
    updated[index] = ConversationSummaryModel(
      id: current.id,
      opportunity: current.opportunity,
      applicationId: current.applicationId,
      otherPartyName: current.otherPartyName,
      studentId: current.studentId,
      lastMessage: current.lastMessage,
      updatedAt: current.updatedAt,
      unreadCount: 0,
    );
    conversations = updated;
  }

  /// Sends [body] in [conversationId]. Returns `true` only on success, in
  /// which case [selectedConversation] (when it's the same conversation)
  /// gets the new message appended immediately — no full re-fetch needed.
  /// A duplicate submission while one is already in flight is ignored.
  Future<bool> sendMessage(int conversationId, String body) async {
    if (isSendingMessage) return false;

    isSendingMessage = true;
    sendErrorMessage = null;
    notifyListeners();

    var success = false;
    try {
      final message = await repository.sendMessage(conversationId, body);
      if (selectedConversation?.id == conversationId) {
        selectedConversation = selectedConversation!.withAppendedMessage(
          message,
        );
      }
      success = true;
    } on ApiException catch (error) {
      sendErrorMessage = error.message;
    } catch (_) {
      sendErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      isSendingMessage = false;
      notifyListeners();
    }
    return success;
  }

  /// Starts (or reuses) a Conversation with [studentId] about
  /// [opportunityId], Organization-only. Returns the real conversation ID
  /// on success, `null` on failure (see [startErrorMessage]). A duplicate
  /// submission while one is already in flight is ignored.
  Future<int?> startConversation({
    required int studentId,
    required int opportunityId,
  }) async {
    if (isStartingConversation) return null;

    isStartingConversation = true;
    startErrorMessage = null;
    notifyListeners();

    int? conversationId;
    try {
      conversationId = await repository.startConversation(
        studentId: studentId,
        opportunityId: opportunityId,
      );
    } on ApiException catch (error) {
      startErrorMessage = error.message;
    } catch (_) {
      startErrorMessage = 'Something went wrong. Please try again.';
    } finally {
      isStartingConversation = false;
      notifyListeners();
    }
    return conversationId;
  }

  void clearSendError() {
    sendErrorMessage = null;
    notifyListeners();
  }

  /// Clears all conversation state — called when the signed-in user
  /// changes.
  void reset() {
    conversations = [];
    isLoadingList = false;
    listErrorMessage = null;
    selectedConversation = null;
    isLoadingDetails = false;
    detailsErrorMessage = null;
    isSendingMessage = false;
    sendErrorMessage = null;
    isStartingConversation = false;
    startErrorMessage = null;
    _listLoadGeneration++;
    _pendingListFetch = null;
    _detailsLoadGeneration++;
    _pendingDetailsFetch = null;
    _pendingDetailsConversationId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authProvider.removeListener(_handleAuthChanged);
    super.dispose();
  }
}
