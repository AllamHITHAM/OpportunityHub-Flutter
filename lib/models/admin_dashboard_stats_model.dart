/// Platform-wide statistics shown on the Admin dashboard, as returned by
/// `GET /api/admin/dashboard`.
///
/// Every field here is a real backend count, not a derived/estimated one —
/// see [AdminDashboardRepository] for the parsing contract. No field is
/// optional: a dashboard missing one of these numbers isn't a smaller
/// dashboard, it's a malformed response that must surface as an error
/// rather than silently rendering a wrong (zero) value next to real ones.
class AdminDashboardStatsModel {
  const AdminDashboardStatsModel({
    required this.totalUsers,
    required this.totalStudents,
    required this.totalOrganizations,
    required this.pendingOrganizations,
    required this.approvedOrganizations,
    required this.rejectedOrganizations,
    required this.totalOpportunities,
    required this.openOpportunities,
    required this.closedOpportunities,
    required this.totalApplications,
    required this.totalInterviews,
  });

  final int totalUsers;
  final int totalStudents;
  final int totalOrganizations;
  final int pendingOrganizations;
  final int approvedOrganizations;
  final int rejectedOrganizations;
  final int totalOpportunities;
  final int openOpportunities;
  final int closedOpportunities;
  final int totalApplications;
  final int totalInterviews;

  factory AdminDashboardStatsModel.fromJson(Map<String, dynamic> json) {
    return AdminDashboardStatsModel(
      totalUsers: _requireInt(json, 'total_users'),
      totalStudents: _requireInt(json, 'total_students'),
      totalOrganizations: _requireInt(json, 'total_organizations'),
      pendingOrganizations: _requireInt(json, 'pending_organizations'),
      approvedOrganizations: _requireInt(json, 'approved_organizations'),
      rejectedOrganizations: _requireInt(json, 'rejected_organizations'),
      totalOpportunities: _requireInt(json, 'total_opportunities'),
      openOpportunities: _requireInt(json, 'open_opportunities'),
      closedOpportunities: _requireInt(json, 'closed_opportunities'),
      totalApplications: _requireInt(json, 'total_applications'),
      totalInterviews: _requireInt(json, 'total_interviews'),
    );
  }

  /// Parses [field] from [json] as a non-null integer, accepting either a
  /// real JSON number or a numeric string (Laravel occasionally serializes
  /// counts as strings depending on the query driver). Unlike this app's
  /// usual `_parseInt` helpers (which return `null` for anything
  /// unparseable), this one throws — a dashboard statistic silently
  /// defaulting to `0` would be indistinguishable from a genuinely empty
  /// platform, which is a materially different (and misleading) thing to
  /// show an admin.
  static int _requireInt(Map<String, dynamic> json, String field) {
    final value = json[field];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw FormatException(
      'Dashboard field "$field" is missing or not a valid integer: $value',
    );
  }
}
