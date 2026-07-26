/// An organization's opportunity, as returned by the Laravel
/// `organization/opportunities` endpoints.
///
/// The backend has a single `opportunities` table — `opportunityType` is
/// purely a categorization label (job, internship, volunteer, scholarship,
/// competition); there are no type-specific fields (no internship-only
/// university/major/GPA/hours-per-week fields exist anywhere in the
/// documented contract). Every field below applies uniformly regardless of
/// type.
class OpportunityModel {
  const OpportunityModel({
    required this.id,
    required this.title,
    required this.description,
    required this.opportunityType,
    required this.employmentType,
    required this.workMode,
    required this.experienceLevel,
    required this.positionsAvailable,
    required this.status,
    this.educationLevel,
    this.fieldOfStudy,
    this.location,
    this.salaryMin,
    this.salaryMax,
    this.applicationDeadline,
    this.createdAt,
  });

  final int id;
  final String title;
  final String description;

  /// One of: job, internship, volunteer, scholarship, competition.
  final String opportunityType;

  /// One of: full_time, part_time, contract.
  final String employmentType;

  /// One of: remote, hybrid, onsite.
  final String workMode;

  /// One of: no_experience, junior, mid, senior, expert.
  final String experienceLevel;

  /// One of: high_school, diploma, bachelor, master, phd — or `null`.
  final String? educationLevel;

  final String? fieldOfStudy;
  final String? location;

  /// Parsed from the backend's `decimal:2`-cast fields, which serialize as
  /// JSON strings (e.g. `"1500.00"`), not numbers.
  final double? salaryMin;
  final double? salaryMax;

  final DateTime? applicationDeadline;

  final int positionsAvailable;

  /// One of: draft, open, closed.
  final String status;

  final DateTime? createdAt;

  factory OpportunityModel.fromJson(Map<String, dynamic> json) {
    return OpportunityModel(
      id: json['id'] as int,
      title: json['title'] as String,
      description: json['description'] as String,
      opportunityType: json['opportunity_type'] as String,
      employmentType: json['employment_type'] as String,
      workMode: json['work_mode'] as String,
      experienceLevel: json['experience_level'] as String,
      educationLevel: json['education_level'] as String?,
      fieldOfStudy: json['field_of_study'] as String?,
      location: json['location'] as String?,
      salaryMin: _parseDecimal(json['salary_min']),
      salaryMax: _parseDecimal(json['salary_max']),
      applicationDeadline: _parseDate(json['application_deadline']),
      positionsAvailable: json['positions_available'] as int? ?? 1,
      status: json['status'] as String,
      createdAt: _parseDate(json['created_at']),
    );
  }

  static double? _parseDecimal(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
