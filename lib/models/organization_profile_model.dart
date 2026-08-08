import 'user_model.dart';

/// An organization's profile, as returned by the Laravel
/// `organization_profile` endpoints (`GET /api/organization/profile`, and
/// nested inside `POST /api/register/organization`'s response) as well as
/// the Admin organization-management endpoints
/// (`GET /api/admin/organizations`, `GET /api/admin/organizations/{id}`,
/// `PUT /api/admin/organizations/{id}/approval`).
///
/// Only the fields this app collects and displays are modeled here — the
/// backend record also has `logo`, but nothing in the app collects or
/// shows that yet (no file/image upload in this phase).
class OrganizationProfileModel {
  const OrganizationProfileModel({
    required this.id,
    required this.organizationName,
    required this.organizationType,
    required this.approvalStatus,
    this.industry,
    this.description,
    this.website,
    this.phone,
    this.user,
  });

  final int id;
  final String organizationName;
  final String organizationType;

  /// One of: pending, approved, rejected. Never client-settable.
  final String approvalStatus;

  final String? industry;
  final String? description;
  final String? website;
  final String? phone;

  /// The organization's account, only present on responses that eager-load
  /// it (the Admin endpoints — `OrganizationProfile::with('user')`). The
  /// organization's own `GET /api/organization/profile` doesn't send this,
  /// so it stays `null` there rather than being required.
  final UserModel? user;

  factory OrganizationProfileModel.fromJson(Map<String, dynamic> json) {
    final rawUser = json['user'];
    return OrganizationProfileModel(
      id: json['id'] as int,
      organizationName: json['organization_name'] as String,
      organizationType: json['organization_type'] as String,
      approvalStatus: json['approval_status'] as String,
      industry: json['industry'] as String?,
      description: json['description'] as String?,
      website: json['website'] as String?,
      phone: json['phone'] as String?,
      user: rawUser is Map<String, dynamic>
          ? UserModel.fromJson(rawUser)
          : null,
    );
  }
}
