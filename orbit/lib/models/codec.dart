import 'package:cloud_firestore/cloud_firestore.dart';

/// Reads a date stored as a Firestore [Timestamp], [DateTime], epoch millis,
/// or ISO-8601 string. Pending server timestamps arrive as `null`.
DateTime? readDate(Object? value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  return null;
}

Timestamp writeDate(DateTime value) => Timestamp.fromDate(value);

Timestamp? writeDateOrNull(DateTime? value) =>
    value == null ? null : Timestamp.fromDate(value);

List<String> readStringList(Object? value) {
  if (value is Iterable) return value.whereType<String>().toList();
  return const [];
}

Map<String, Object?> readMap(Object? value) {
  if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
  return const {};
}

T readEnum<T extends Enum>(List<T> values, Object? raw, T fallback) {
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return fallback;
}

/// Stable 64-bit FNV-1a hash, used to derive idempotent document ids.
String stableHash(String input) {
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  final mask = (BigInt.one << 64) - BigInt.one;
  for (final unit in input.codeUnits) {
    hash = ((hash ^ BigInt.from(unit)) * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
