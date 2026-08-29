/// Recruitment statistics shown on the Organization dashboard, as returned
/// by `GET /api/organization/dashboard`.
///
/// Every field here is a real backend count, not a derived/estimated one —
/// see [OrganizationDashboardRepository] for the parsing contract. No field
/// is optional: a dashboard missing one of these numbers isn't a smaller
/// dashboard, it's a malformed response that must surface as an error
/// rather than silently rendering a wrong (zero) value next to real ones.
/// Mirrors [AdminDashboardStatsModel]'s exact parsing conventions.
class OrganizationDashboardStatsModel {
  const OrganizationDashboardStatsModel({
    required this.totalOpportunities,
    required this.openOpportunities,
    required this.closedOpportunities,
    required this.draftOpportunities,
    required this.totalApplications,
    required this.pendingApplications,
    required this.shortlistedApplications,
    required this.offerSentApplications,
    required this.acceptedApplications,
    required this.rejectedApplications,
    required this.totalInterviews,
    required this.completedInterviews,
  });

  final int totalOpportunities;
  final int openOpportunities;
  final int closedOpportunities;
  final int draftOpportunities;

  final int totalApplications;
  final int pendingApplications;
  final int shortlistedApplications;
  final int offerSentApplications;
  final int acceptedApplications;
  final int rejectedApplications;

  final int totalInterviews;
  final int completedInterviews;

  factory OrganizationDashboardStatsModel.fromJson(Map<String, dynamic> json) {
    return OrganizationDashboardStatsModel(
      totalOpportunities: _requireInt(json, 'total_opportunities'),
      openOpportunities: _requireInt(json, 'open_opportunities'),
      closedOpportunities: _requireInt(json, 'closed_opportunities'),
      draftOpportunities: _requireInt(json, 'draft_opportunities'),
      totalApplications: _requireInt(json, 'total_applications'),
      pendingApplications: _requireInt(json, 'pending_applications'),
      shortlistedApplications: _requireInt(json, 'shortlisted_applications'),
      offerSentApplications: _requireInt(json, 'offer_sent_applications'),
      acceptedApplications: _requireInt(json, 'accepted_applications'),
      rejectedApplications: _requireInt(json, 'rejected_applications'),
      totalInterviews: _requireInt(json, 'total_interviews'),
      completedInterviews: _requireInt(json, 'completed_interviews'),
    );
  }

  /// Parses [field] from [json] as a non-null integer, accepting either a
  /// real JSON number or a numeric string (Laravel occasionally serializes
  /// counts as strings depending on the query driver). Unlike this app's
  /// usual `_parseInt` helpers (which return `null` for anything
  /// unparseable), this one throws — a dashboard statistic silently
  /// defaulting to `0` would be indistinguishable from a genuinely empty
  /// organization, which is a materially different (and misleading) thing
  /// to show. Mirrors `AdminDashboardStatsModel._requireInt` exactly.
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
