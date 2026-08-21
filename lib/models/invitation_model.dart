/// An Organization-driven invitation to apply (Phase 8B-3, Flow B), as
/// returned by both `GET /api/student/invitations` and the response of
/// `POST /api/organization/invitations`.
class InvitationModel {
  const InvitationModel({
    required this.id,
    required this.opportunityId,
    required this.status,
    required this.opportunityTitle,
    required this.organizationName,
    this.message,
    this.createdAt,
  });

  final int id;
  final int opportunityId;

  /// `pending`, `accepted`, or `declined`.
  final String status;

  final String opportunityTitle;
  final String organizationName;
  final String? message;
  final DateTime? createdAt;

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isDeclined => status == 'declined';

  factory InvitationModel.fromJson(Map<String, dynamic> json) {
    final opportunity = json['opportunity'] as Map<String, dynamic>?;
    final organizationProfile =
        opportunity?['organization_profile'] as Map<String, dynamic>?;
    final createdAtRaw = json['created_at'] as String?;

    return InvitationModel(
      id: json['id'] as int,
      opportunityId: json['opportunity_id'] as int,
      status: json['status'] as String,
      opportunityTitle: opportunity?['title'] as String? ?? '',
      organizationName:
          organizationProfile?['organization_name'] as String? ?? '',
      message: json['message'] as String?,
      createdAt: createdAtRaw == null ? null : DateTime.tryParse(createdAtRaw),
    );
  }
}
