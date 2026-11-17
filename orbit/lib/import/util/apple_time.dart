/// Seconds between the Unix epoch and Apple's Core Data epoch (2001-01-01 UTC).
const int appleEpochOffsetSeconds = 978307200;

/// Converts a Messages `date` / `date_read` / `date_delivered` value to UTC.
///
/// Before macOS 10.13 / iOS 11 the value is seconds since 2001-01-01; since
/// then it is nanoseconds. A seconds value only exceeds 1e11 after year 5000,
/// and a nanosecond value is below it only for the first ~100 s of 2001, so
/// the magnitude reliably tells them apart. Returns null for 0 / null
/// ("never", e.g. unread).
DateTime? appleTimestampToDateTime(num? value) {
  if (value == null || value == 0) return null;
  final micros = value.abs() > 1e11
      ? (value / 1000).round()
      : (value * 1000000).round();
  return DateTime.fromMicrosecondsSinceEpoch(
    micros + appleEpochOffsetSeconds * 1000000,
    isUtc: true,
  );
}

/// Inverse of [appleTimestampToDateTime] producing the modern nanosecond form.
int dateTimeToAppleNanoseconds(DateTime dt) =>
    (dt.toUtc().microsecondsSinceEpoch - appleEpochOffsetSeconds * 1000000) * 1000;
