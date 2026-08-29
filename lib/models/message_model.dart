/// One real chat message inside a [ConversationModel] (Messaging MVP) —
/// text-only, as returned by `GET /conversations/{conversation}` (full
/// history) and `POST /conversations/{conversation}/messages` (the
/// just-sent message). [isOwnMessage] is computed server-side
/// (`sender_user_id === viewer.id`) rather than derived here, so this
/// model never needs to separately know the viewer's own user ID.
class MessageModel {
  const MessageModel({
    required this.id,
    required this.senderUserId,
    required this.isOwnMessage,
    required this.body,
    this.readAt,
    required this.createdAt,
  });

  final int id;
  final int senderUserId;
  final bool isOwnMessage;
  final String body;

  /// `null` while still unread by the recipient — never set for the
  /// sender's own message (see `MessagingService::markIncomingMessagesRead()`
  /// on the backend, which only ever marks the *other* party's messages).
  final DateTime? readAt;
  final DateTime createdAt;

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'] as int,
      senderUserId: json['sender_user_id'] as int,
      isOwnMessage: json['is_own_message'] as bool? ?? false,
      body: json['body'] as String,
      readAt: _parseDate(json['read_at']),
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
