/// The organization's final Offer for an application, as returned by
/// `POST /organization/applications/{applicationId}/offer` and
/// `GET /organization/applications/{applicationId}/offer`.
///
/// Deliberately never nests a full `ApplicationModel` — the backend's own
/// response is the Offer's own fields only, never a nested `application`
/// key (see `App\Http\Controllers\Organization\OfferController`), so this
/// model doesn't invent one either.
///
/// [salaryAmount] is kept as the raw `String?` the backend actually sends
/// (its `decimal:2` Eloquent cast serializes as e.g. `"90000.00"`, not a
/// JSON number) — passed through as-is rather than parsed into a `double`,
/// which would risk floating-point precision drift for a money value this
/// model only ever needs to display, never compute with.
class OfferModel {
  const OfferModel({
    required this.id,
    required this.applicationId,
    this.title,
    this.salaryAmount,
    this.salaryCurrency,
    this.salaryPeriod,
    this.startDate,
    this.message,
    required this.status,
    this.sentAt,
    this.respondedAt,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int applicationId;

  final String? title;

  /// Raw backend decimal string (e.g. `"90000.00"`), or `null` when no
  /// compensation was set on this Offer.
  final String? salaryAmount;

  final String? salaryCurrency;

  /// One of: hourly, monthly, yearly. Only meaningful when [salaryAmount]
  /// is non-null.
  final String? salaryPeriod;

  final DateTime? startDate;
  final String? message;

  /// One of: sent, accepted, declined.
  final String status;

  final DateTime? sentAt;
  final DateTime? respondedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory OfferModel.fromJson(Map<String, dynamic> json) {
    return OfferModel(
      id: json['id'] as int,
      applicationId: json['application_id'] as int,
      title: json['title'] as String?,
      salaryAmount: json['salary_amount'] as String?,
      salaryCurrency: json['salary_currency'] as String?,
      salaryPeriod: json['salary_period'] as String?,
      startDate: _parseDate(json['start_date']),
      message: json['message'] as String?,
      status: json['status'] as String,
      sentAt: _parseDate(json['sent_at']),
      respondedAt: _parseDate(json['responded_at']),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
