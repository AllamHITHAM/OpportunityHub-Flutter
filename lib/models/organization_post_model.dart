/// One "Updates & Achievements" post (Organization Public Profile phase)
/// -- a simple, professional text update, as returned by
/// `GET /organizations/{id}/posts` (public/owner read),
/// `POST /organization/posts` (create), and
/// `PUT /organization/posts/{id}` (edit). Never a social-media post — no
/// like/comment/follower/share counts exist on this model, matching the
/// backend's own deliberately narrow schema.
class OrganizationPostModel {
  const OrganizationPostModel({
    required this.id,
    required this.organizationId,
    this.title,
    required this.body,
    this.imageUrl,
    required this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int organizationId;

  /// A post may have no headline — a short update stands on its own.
  final String? title;
  final String body;

  /// The post's optional single image (Company Profile Polish phase) —
  /// `null` when this post has none. Never a raw storage path, never a
  /// gallery.
  final String? imageUrl;

  final DateTime createdAt;
  final DateTime? updatedAt;

  factory OrganizationPostModel.fromJson(Map<String, dynamic> json) {
    return OrganizationPostModel(
      id: json['id'] as int,
      organizationId: json['organization_id'] as int,
      title: json['title'] as String?,
      body: json['body'] as String,
      imageUrl: json['image_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.tryParse(json['updated_at'] as String),
    );
  }
}
