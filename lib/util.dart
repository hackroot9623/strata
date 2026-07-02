// Tiny formatting helpers. ponytail: no intl dependency — these few cases
// don't justify it. Add `intl` if locale-aware formatting is ever needed.

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _cardinals = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

String weekday(DateTime d) => _weekdays[d.weekday - 1];

String fmtTime(DateTime? d) {
  if (d == null) return '—';
  final h = d.hour.toString().padLeft(2, '0');
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

String windCardinal(int deg) => _cardinals[(((deg % 360) + 22) ~/ 45) % 8];

String uvLabel(double uv) {
  if (uv < 3) return 'Low';
  if (uv < 6) return 'Moderate';
  if (uv < 8) return 'High';
  if (uv < 11) return 'Very High';
  return 'Extreme';
}

/// European AQI bands -> (label, color).
(String, int) aqiBand(int aqi) {
  if (aqi <= 20) return ('Good', 0xFF43A047);
  if (aqi <= 40) return ('Fair', 0xFF7CB342);
  if (aqi <= 60) return ('Moderate', 0xFFFDD835);
  if (aqi <= 80) return ('Poor', 0xFFFB8C00);
  if (aqi <= 100) return ('Very Poor', 0xFFE53935);
  return ('Extreme', 0xFF8E24AA);
}

/// "Today"/"Tomorrow"/weekday for [date] relative to [now] (date-only compare).
String dayLabel(DateTime date, DateTime now) {
  final d0 = DateTime(now.year, now.month, now.day);
  final d = DateTime(date.year, date.month, date.day);
  final diff = d.difference(d0).inDays;
  if (diff <= 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  return weekday(date);
}

String hourLabel(DateTime t) {
  final h = t.hour;
  final ampm = h < 12 ? 'AM' : 'PM';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12 $ampm';
}
