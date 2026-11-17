import 'dart:io';

import 'address.dart';

/// Optional address -> name lookup used to label imported participants.
class ContactBook {
  ContactBook([Map<String, String>? names]) {
    names?.forEach(add);
  }

  final Map<String, String> _byAddress = {};

  int get length => _byAddress.length;

  void add(String address, String name) {
    final key = normalizeAddress(address);
    if (key.isNotEmpty && name.trim().isNotEmpty) _byAddress[key] = name.trim();
  }

  String? lookup(String address) => _byAddress[normalizeAddress(address)];

  static Future<ContactBook> fromVcfFile(String path) async =>
      parseVcf(await File(path).readAsString());

  /// Parses vCard 2.1/3.0/4.0 text (as exported by iPhone, Android, Google
  /// Contacts, Outlook): FN (or N), TEL and EMAIL properties.
  static ContactBook parseVcf(String text) {
    final book = ContactBook();
    final unfolded = text.replaceAll(RegExp(r'\r?\n[ \t]'), '');
    String? name;
    final addresses = <String>[];
    for (final rawLine in unfolded.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      final upper = line.toUpperCase();
      if (upper == 'BEGIN:VCARD') {
        name = null;
        addresses.clear();
      } else if (upper == 'END:VCARD') {
        if (name != null) {
          for (final a in addresses) {
            book.add(a, name);
          }
        }
      } else {
        final colon = line.indexOf(':');
        if (colon < 0) continue;
        final prop = upper.substring(0, colon).split(';').first.split('.').last;
        final value = _unescape(line.substring(colon + 1));
        if (prop == 'FN' && value.isNotEmpty) {
          name = value;
        } else if (prop == 'N' && name == null) {
          final parts = value.split(';');
          final n = [if (parts.length > 1) parts[1], parts[0]].where((s) => s.isNotEmpty).join(' ');
          if (n.isNotEmpty) name = n;
        } else if (prop == 'TEL' || prop == 'EMAIL') {
          addresses.add(value.replaceFirst(RegExp(r'^tel:', caseSensitive: false), ''));
        }
      }
    }
    return book;
  }

  static String _unescape(String v) =>
      v.replaceAll(r'\,', ',').replaceAll(r'\;', ';').replaceAll(r'\n', ' ').replaceAll(r'\\', r'\').trim();
}
