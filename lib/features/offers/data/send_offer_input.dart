/// The fields needed to send an Offer, shaped for
/// `OfferRepository.sendOrganizationOffer`.
class SendOfferInput {
  const SendOfferInput({
    this.title,
    this.salaryAmount,
    this.salaryCurrency,
    this.salaryPeriod,
    this.startDate,
    this.message,
  });

  final String? title;

  final double? salaryAmount;
  final String? salaryCurrency;

  /// One of: hourly, monthly, yearly. Only sent when [salaryAmount] is set
  /// — see [toJson].
  final String? salaryPeriod;

  final DateTime? startDate;
  final String? message;

  /// Builds the backend's expected `offer` request body. Optional text
  /// fields are trimmed and, if empty or whitespace-only, omitted entirely
  /// rather than sent as an empty string — matching
  /// `InterviewCreateInput.toJson`'s existing convention. Never includes
  /// `status`/`sent_at`/`responded_at`/`application_id` — those are always
  /// server-controlled.
  ///
  /// [salaryCurrency]/[salaryPeriod] are only ever included alongside
  /// [salaryAmount] — if [salaryAmount] is `null`, neither is sent, even if
  /// the caller set one, matching the backend's own bidirectional
  /// consistency rule (`SendOfferRequest`): all three together, or none.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};

    final titleValue = _cleaned(title);
    if (titleValue != null) json['title'] = titleValue;

    if (salaryAmount != null) {
      json['salary_amount'] = salaryAmount;

      final currencyValue = _cleaned(salaryCurrency);
      if (currencyValue != null) json['salary_currency'] = currencyValue;

      if (salaryPeriod != null) json['salary_period'] = salaryPeriod;
    }

    if (startDate != null) json['start_date'] = _formatDate(startDate!);

    final messageValue = _cleaned(message);
    if (messageValue != null) json['message'] = messageValue;

    return json;
  }

  static String? _cleaned(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  /// Formats as `YYYY-MM-DD`, the shape Laravel's `date` validation rule
  /// expects — deliberately not a dependency on `intl` (this app has never
  /// needed it — see `date_formatter.dart`), matching
  /// `InterviewCreateInput._formatScheduledAt`'s existing convention.
  static String _formatDate(DateTime value) {
    String pad(int n) => n.toString().padLeft(2, '0');
    final year = value.year.toString().padLeft(4, '0');
    return '$year-${pad(value.month)}-${pad(value.day)}';
  }
}
