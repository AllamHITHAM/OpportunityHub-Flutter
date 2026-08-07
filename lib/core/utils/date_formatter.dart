const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Formats a [DateTime] as e.g. "Jan 15, 2027" — no `intl` dependency, since
/// this is the only format used across the app so far.
String formatDate(DateTime date) {
  return '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';
}

/// Formats a [DateTime]'s time-of-day as e.g. "2:05 PM" — no `intl`
/// dependency, matching [formatDate].
String formatTime(DateTime date) {
  final hour24 = date.hour;
  final period = hour24 >= 12 ? 'PM' : 'AM';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour12:$minute $period';
}
