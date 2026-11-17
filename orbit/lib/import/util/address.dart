import 'sha1.dart';

/// Normalizes a phone number or email so the same person matches across
/// sources. Emails are lower-cased; phone numbers keep digits only and are
/// reduced to their last 10 digits (so "+1 (555) 123-4567" == "5551234567"
/// and "+44 7700 900123" == "07700 900123"). Short codes are kept as-is.
String normalizeAddress(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.contains('@')) return trimmed.toLowerCase();
  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return trimmed.toLowerCase();
  return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
}

bool isOwnAddress(String address, Set<String> ownAddresses) {
  if (address == 'insert-address-token') return true;
  if (ownAddresses.isEmpty) return false;
  final n = normalizeAddress(address);
  return ownAddresses.any((o) => normalizeAddress(o) == n);
}

String directThreadKey(String address) => 'dm:${normalizeAddress(address)}';

String groupThreadKey(Iterable<String> addresses) {
  final sorted = addresses.map(normalizeAddress).toSet().toList()..sort();
  return 'group:${sorted.join(',')}';
}

/// Short stable hash for dedupe keys.
String stableHash(List<Object?> parts) => sha1Hex(parts.map((p) => p ?? '').join('\u001f')).substring(0, 24);
