import 'location_model.dart';
import 'user_model.dart';

/// An organization's profile, as returned by the Laravel
/// `organization_profile` endpoints (`GET/PUT /api/organization/profile`,
/// and nested inside `POST /api/register/organization`'s response), the
/// Admin organization-management endpoints
/// (`GET /api/admin/organizations`, `GET /api/admin/organizations/{id}`,
/// `PUT /api/admin/organizations/{id}/approval`), and, as of the
/// Organization Public Profile phase, the new public-facing
/// `GET /api/organizations/{id}` (a narrower, explicit-safe-field
/// response -- see `Public\OrganizationController`'s own doc comment --
/// which never actually sends [approvalStatus] or [user] at all; see
/// each field's own doc comment for how this model still fills them in
/// safely).
///
/// Only the fields this app collects and displays are modeled here.
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
    this.location,
    this.logoUrl,
    this.user,
  });

  final int id;
  final String organizationName;
  final String organizationType;

  /// One of: pending, approved, rejected. Never client-settable. The
  /// public-profile response never actually sends this field (it's
  /// internal workflow state -- see `Public\OrganizationController`'s own
  /// doc comment), but [fromJson] safely defaults it to `'approved'`
  /// there rather than leaving it nullable everywhere else this model is
  /// used: that response is only ever reachable at all for an
  /// already-`approved` organization (server-enforced via its own 404
  /// gate), so this is a guaranteed invariant, never a guess.
  final String approvalStatus;

  final String? industry;
  final String? description;
  final String? website;
  final String? phone;

  /// The Organization's own canonical Location Catalog reference
  /// (Organization Public Profile phase) — `null` when not set. Never a
  /// free-text location string.
  final LocationModel? location;

  /// The Company Logo's full, publicly-reachable URL (Company Profile
  /// Polish phase) — `null` until an Organization uploads one, in which
  /// case the existing initials-avatar fallback keeps rendering exactly
  /// as it already does everywhere else in this app. Never a raw storage
  /// path.
  final String? logoUrl;

  /// The organization's account, only present on responses that eager-load
  /// it (the Admin endpoints — `OrganizationProfile::with('user')`). The
  /// organization's own `GET /api/organization/profile` and the public
  /// profile endpoint don't send this, so it stays `null` there rather
  /// than being required.
  final UserModel? user;

  factory OrganizationProfileModel.fromJson(Map<String, dynamic> json) {
    final rawUser = json['user'];
    final locationJson = json['location'];
    return OrganizationProfileModel(
      id: json['id'] as int,
      organizationName: json['organization_name'] as String,
      organizationType: json['organization_type'] as String,
      approvalStatus: json['approval_status'] as String? ?? 'approved',
      industry: json['industry'] as String?,
      description: json['description'] as String?,
      website: json['website'] as String?,
      phone: json['phone'] as String?,
      location: locationJson is Map<String, dynamic>
          ? LocationModel.fromJson(locationJson)
          : null,
      logoUrl: json['logo_url'] as String?,
      user: rawUser is Map<String, dynamic>
          ? UserModel.fromJson(rawUser)
          : null,
    );
  }
}
