import '../import/util/address.dart';

/// One phone number of a contact in the phone's address book.
class PhoneContact {
  const PhoneContact({
    required this.name,
    required this.number,
    this.contactId,
    this.photoUri,
  });

  final String name;
  final String number;
  final String? contactId;

  /// `content://` URI of the contact's thumbnail, read through the platform.
  final String? photoUri;

  /// Matches the address keys used by imported chats.
  String get normalizedNumber => normalizeAddress(number);

  /// Rows from the Android `queryContacts` call. Contacts without a name use
  /// their number; numbers listed twice for one contact appear once.
  static List<PhoneContact> fromRows(List<Map<String, String>> rows) {
    final seen = <String>{};
    final out = <PhoneContact>[];
    for (final r in rows) {
      final number = (r['number'] ?? '').trim();
      if (number.isEmpty) continue;
      final name = (r['name'] ?? '').trim();
      final contactId = r['contactId'];
      if (!seen.add('$contactId|${normalizeAddress(number)}')) continue;
      out.add(PhoneContact(
        name: name.isEmpty ? number : name,
        number: number,
        contactId: contactId,
        photoUri: r['photoUri'],
      ));
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }
}
