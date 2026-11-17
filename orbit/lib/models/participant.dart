/// Someone who took part in a conversation but may not be an Orbit user,
/// e.g. a phone number or email from imported history.
class Participant {
  const Participant({
    required this.address,
    this.displayName = '',
    this.uid,
  });

  /// Phone number (E.164 preferred) or email address.
  final String address;
  final String displayName;

  /// Set when the address belongs to a known Orbit user.
  final String? uid;

  String get label => displayName.trim().isNotEmpty ? displayName : address;

  Map<String, Object?> toMap() => {
        'address': address,
        'displayName': displayName,
        if (uid != null) 'uid': uid,
      };

  factory Participant.fromMap(Map<String, Object?> map) => Participant(
        address: map['address'] as String? ?? '',
        displayName: map['displayName'] as String? ?? '',
        uid: map['uid'] as String?,
      );
}
