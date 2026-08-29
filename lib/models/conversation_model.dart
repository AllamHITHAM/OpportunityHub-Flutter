import 'message_model.dart';

/// The real Opportunity a [ConversationSummaryModel]/[ConversationModel]
/// is about — `null` is not a state this MVP ever produces (every valid
/// "who can message" context is itself Opportunity-scoped), but the field
/// stays nullable to mirror the backend's own `conversations.opportunity_id`
/// (`nullOnDelete()`), so a real Opportunity later deleted by its
/// Organization degrades to "Opportunity" instead of crashing.
class ConversationOpportunityRef {
  const ConversationOpportunityRef({required this.id, required this.title});

  final int id;
  final String title;

  factory ConversationOpportunityRef.fromJson(Map<String, dynamic> json) {
    return ConversationOpportunityRef(
      id: json['id'] as int,
      title: json['title'] as String,
    );
  }
}

/// The one-line preview of a Conversation's most recent Message — used by
/// the conversation list, never the full message text beyond what's
/// already safe to preview (the backend sends the real, unredacted body
/// here; there is nothing more sensitive than what the recipient already
/// sees inside the conversation itself).
class ConversationLastMessagePreview {
  const ConversationLastMessagePreview({
    required this.body,
    required this.createdAt,
    required this.isOwnMessage,
  });

  final String body;
  final DateTime createdAt;
  final bool isOwnMessage;

  factory ConversationLastMessagePreview.fromJson(Map<String, dynamic> json) {
    return ConversationLastMessagePreview(
      body: json['body'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      isOwnMessage: json['is_own_message'] as bool? ?? false,
    );
  }
}

/// One row from `GET /conversations` (Messaging MVP) — shared between the
/// Organization Messages and Student Messages screens, since the backend
/// endpoint itself is role-agnostic (see `ConversationController`'s own
/// doc comment). [otherPartyName] is already resolved server-side to
/// whichever side the *viewer* isn't (the Organization's name for a
/// Student viewer, the Student's name for an Organization viewer), so
/// this model never needs to know the viewer's own role to render it.
class ConversationSummaryModel {
  const ConversationSummaryModel({
    required this.id,
    required this.opportunity,
    required this.applicationId,
    required this.otherPartyName,
    required this.studentId,
    required this.lastMessage,
    required this.updatedAt,
    this.unreadCount,
  });

  final int id;
  final ConversationOpportunityRef? opportunity;
  final int? applicationId;
  final String otherPartyName;

  /// The real `student_profiles.id` this conversation is about — the same
  /// ID `POST /organization/candidates/{student}/conversation` expects,
  /// present regardless of viewer role.
  final int studentId;

  /// `null` only for a Conversation that was just started and has no
  /// Message yet (never reachable through the normal "Message" button
  /// flow, since starting a conversation never sends an initial message
  /// automatically) — the empty-conversation UI handles this directly.
  final ConversationLastMessagePreview? lastMessage;
  final DateTime updatedAt;

  /// The real count of messages from the other party this viewer hasn't
  /// yet read — always present from `GET /conversations` (the list),
  /// deliberately omitted by `GET /conversations/{conversation}` (the
  /// detail fetch, which just marked those same messages read as a side
  /// effect of being opened, so re-sending a now-stale count there would
  /// be misleading).
  final int? unreadCount;

  factory ConversationSummaryModel.fromJson(Map<String, dynamic> json) {
    final opportunityJson = json['opportunity'];
    final lastMessageJson = json['last_message'];

    return ConversationSummaryModel(
      id: json['id'] as int,
      opportunity: opportunityJson is Map<String, dynamic>
          ? ConversationOpportunityRef.fromJson(opportunityJson)
          : null,
      applicationId: json['application_id'] as int?,
      otherPartyName: json['other_party_name'] as String,
      studentId: json['student_id'] as int,
      lastMessage: lastMessageJson is Map<String, dynamic>
          ? ConversationLastMessagePreview.fromJson(lastMessageJson)
          : null,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      unreadCount: json['unread_count'] as int?,
    );
  }
}

/// The full response of `GET /conversations/{conversation}` — the same
/// summary fields as [ConversationSummaryModel] (minus [unreadCount], see
/// that field's own doc comment) plus the complete, chronological
/// [messages] history.
class ConversationModel {
  const ConversationModel({
    required this.id,
    required this.opportunity,
    required this.applicationId,
    required this.otherPartyName,
    required this.studentId,
    required this.updatedAt,
    required this.messages,
  });

  final int id;
  final ConversationOpportunityRef? opportunity;
  final int? applicationId;
  final String otherPartyName;
  final int studentId;
  final DateTime updatedAt;

  /// Already chronological (oldest first) — exactly the order the backend
  /// returns, never re-sorted client-side.
  final List<MessageModel> messages;

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    final opportunityJson = json['opportunity'];
    final messagesJson = json['messages'] as List? ?? const [];

    return ConversationModel(
      id: json['id'] as int,
      opportunity: opportunityJson is Map<String, dynamic>
          ? ConversationOpportunityRef.fromJson(opportunityJson)
          : null,
      applicationId: json['application_id'] as int?,
      otherPartyName: json['other_party_name'] as String,
      studentId: json['student_id'] as int,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      messages: messagesJson
          .map((m) => MessageModel.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }

  /// A copy with one new [MessageModel] appended — used after a successful
  /// send, so the just-sent message appears immediately without a full
  /// re-fetch.
  ConversationModel withAppendedMessage(MessageModel message) {
    return ConversationModel(
      id: id,
      opportunity: opportunity,
      applicationId: applicationId,
      otherPartyName: otherPartyName,
      studentId: studentId,
      updatedAt: message.createdAt,
      messages: [...messages, message],
    );
  }
}
