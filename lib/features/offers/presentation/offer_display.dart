import '../../../core/widgets/status_chip.dart';
import '../../../models/offer_model.dart';

// Display helpers for Offer data — kept feature-local, mirroring
// `assessment_display.dart`'s own separation from
// `application_display.dart` (Application/Assessment/Offer each have their
// own status vocabulary; mixing them into one file would blur three
// genuinely different concerns together).

/// User-facing labels for every documented `offer.status` value.
const offerStatusLabels = {
  'sent': 'Sent',
  'accepted': 'Accepted',
  'declined': 'Declined',
};

AppStatusType offerStatusChipType(String status) {
  switch (status) {
    case 'accepted':
      return AppStatusType.success;
    case 'declined':
      return AppStatusType.neutral;
    case 'sent':
    default:
      return AppStatusType.info;
  }
}

/// User-facing labels for every documented `offer.salary_period` value.
const salaryPeriodLabels = {
  'hourly': 'Hourly',
  'monthly': 'Monthly',
  'yearly': 'Yearly',
};

/// The short suffix used when formatting a salary line, e.g. "/ month".
const salaryPeriodSuffixes = {
  'hourly': 'hour',
  'monthly': 'month',
  'yearly': 'year',
};

/// Formats an Offer's compensation as e.g. "USD 1,500.00 / month" — only
/// when every one of [amount]/[currency]/[period] is present (matching the
/// backend's own all-or-nothing compensation consistency rule; see
/// `SendOfferInput`). Returns `null` otherwise, so the caller can decide
/// how to represent "no compensation specified" without this helper
/// guessing at partial/malformed data.
///
/// [amount] is the raw backend decimal string (e.g. `"90000.00"`) — see
/// [OfferModel.salaryAmount]'s own doc comment for why it's never parsed
/// into a `double` here. Thousands separators are inserted directly on
/// that string's integer part; no `intl` dependency, matching
/// `date_formatter.dart`'s existing convention.
String? formatSalary({
  required String? amount,
  required String? currency,
  required String? period,
}) {
  if (amount == null || currency == null || period == null) return null;

  final suffix = salaryPeriodSuffixes[period];
  if (suffix == null) return null;

  return '$currency ${_withThousandsSeparators(amount)} / $suffix';
}

/// Inserts `,` every three digits of the integer part of a decimal string
/// like `"90000.00"` -> `"90,000.00"`. Malformed input (no digits, or a
/// shape this simple grouping can't make sense of) is returned unchanged
/// rather than thrown on — a display helper must never crash the section
/// it's rendering into.
String _withThousandsSeparators(String decimalString) {
  final parts = decimalString.split('.');
  final integerPart = parts[0];
  final isNegative = integerPart.startsWith('-');
  final digits = isNegative ? integerPart.substring(1) : integerPart;

  if (digits.isEmpty || int.tryParse(digits) == null) return decimalString;

  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }

  final grouped = '${isNegative ? '-' : ''}$buffer';
  return parts.length > 1 ? '$grouped.${parts[1]}' : grouped;
}
